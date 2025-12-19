#!/usr/bin/env python3
import socket

def abrir_cajon(ip, puerto=9100):
    # Comandos ESC/POS comunes
    comandos = [
        b'\x1b\x70\x00\x3c\xf0',
        b'\x1B\x70\x00\x19\xFA',  # Epson estándar
        b'\x1B\x70\x00',          # Alternativo
        b'\x1B\x70',              # Minimalista
        b'\x10\x14\x01\x00\x00',  # Otro formato
    ]
    
    try:
        sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        sock.settimeout(5)
        sock.connect((ip, puerto))
        sock.send(comandos[0])  # Probar primer comando
        sock.close()
        print("✅ Cajón abierto correctamente")
        return True
    except Exception as e:
        print(f"❌ Error: {e}")
        return False

# Uso
if __name__ == "__main__":
    abrir_cajon("192.168.1.24")
