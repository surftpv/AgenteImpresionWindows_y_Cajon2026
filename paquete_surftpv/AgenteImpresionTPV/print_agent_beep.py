import requests
import base64
from escpos.printer import Network
from time import sleep
from PIL import Image
from io import BytesIO
import threading
import signal
import sys
import logging

# Ultima modificacion 19 Dic 2025

_logger = logging.getLogger(__name__)
logging.basicConfig(level=logging.INFO)

class PrintAgent:
    def __init__(self, odoo_url, api_key, printer_ips, poll_interval=5):
        """
        :param odoo_url: Base URL of the Odoo server
        :param api_key:  API key for authentication
        :param printer_ips: List of printer IP addresses
        :param poll_interval: Seconds between polling cycles
        """
        self.odoo_url = odoo_url.rstrip('/')
        self.headers = {'Authorization': f'Bearer {api_key}'}
        self.printer_ips = printer_ips
        self.poll_interval = poll_interval
        self._stop_event = threading.Event()
        self.threads = []

    def start(self):
        """Start polling threads for each configured printer."""
        _logger.info("Starting PrintAgent for printers: %s", self.printer_ips)
        # Handle graceful shutdown
        signal.signal(signal.SIGINT, self._signal_handler)
        signal.signal(signal.SIGTERM, self._signal_handler)

        for ip in self.printer_ips:
            print('i', ip)
            t = threading.Thread(target=self._poll_printer, args=(ip,), daemon=True)
            t.start()
            self.threads.append(t)

        # Wait for threads to finish
        for t in self.threads:
            t.join()

    def _signal_handler(self, signum, frame):
        _logger.info("Shutdown signal received (%s). Stopping threads...", signum)
        self._stop_event.set()

    def _poll_printer(self, printer_ip):
        """Continuously fetch jobs for a given printer IP."""
        _logger.info("Thread started for printer %s", printer_ip)
        while not self._stop_event.is_set():
            try:
                resp = requests.get(
                    f"{self.odoo_url}/pos_print_agent/jobs",
                    json={"printer_ip": printer_ip},
                    headers=self.headers,
                    timeout=10
                )
                resp.raise_for_status()
                jobs = resp.json().get('result', [])

                for job in jobs:
                    job_id = job.get('id')
                    img_data = job.get('data')
                    try:
                        self._print_receipt(img_data, printer_ip)
                        self._confirm_job(job_id)
                    except Exception as e:
                        _logger.error("Failed to print job %s on %s: %s", job_id, printer_ip, e)
            except Exception as e:
                _logger.error("Error polling jobs for %s: %s", printer_ip, e)

            sleep(self.poll_interval)

        _logger.info("Thread exiting for printer %s", printer_ip)

    def _print_receipt(self, img_data, printer_ip):
        """Decode the base64 image, split if needed, and send to printer."""
        im = Image.open(BytesIO(base64.b64decode(img_data)))
        slices = self._imgcrop(im)
        printer = Network(printer_ip)

        for slice_img in slices:
            printer.image(slice_img)

        # ----------------------------------------------------------
        # 🔔 EXTRA: BEEP PARA IMPRIMIR 
        # ----------------------------------------------------------
        try:
            printer._raw(b'\x1b\x42\x02\x05')
        except Exception as e:
            _logger.error("Error en el BEEP", printer_ip, e)
        # ----------------------------------------------------------

        # ----------------------------------------------------------
        # EXTRA: FEED PARA SACAR PAPEL EN BLANCO
        # ----------------------------------------------------------
        try:
            printer._raw(b'\x1b\x64\x02')
        except Exception as j:
            _logger.error("Error en el FEED Extra", printer_ip, j)
        # ----------------------------------------------------------


        printer.cut()
        printer.close()
        _logger.info("Printed receipt on %s", printer_ip)

    def _imgcrop(self, im):
        """Split tall images into chunks for ESC/POS printers."""
        ret = []
        w, h = im.size
        max_height = 2000  # adjust as per printer buffer capability
        y_slices = (h + max_height - 1) // max_height
        slice_h = h // y_slices

        for i in range(y_slices):
            top = i * slice_h
            bottom = h if i == y_slices - 1 else (top + slice_h)
            ret.append(im.crop((0, top, w, bottom)))
        return ret

    def _confirm_job(self, job_id):
        """Mark the job as done in Odoo."""
        try:
            resp = requests.post(
                f"{self.odoo_url}/pos_print_agent/jobs/{job_id}",
                json={"status": "done"},
                headers=self.headers,
                timeout=5
            )
            resp.raise_for_status()
            _logger.info("Confirmed job %s", job_id)
        except Exception as e:
            _logger.error("Error confirming job %s: %s", job_id, e)

if __name__ == "__main__":
    agent = PrintAgent(
        odoo_url="https://demo.surftpv.app/",
        api_key="d45c04c9ef8fce49ac244d5057458b8b091bbebd",
        printer_ips=["192.168.1.23", "192.168.1.24"]
    )
    agent.start()
