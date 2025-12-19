@echo off
setlocal

:: --- CONFIGURACIÓN ---
set "SCRIPT_DIR=%~dp0"
set "BASE_DIR=C:\SurfTPV"
set "ZIP_FILE=%SCRIPT_DIR%paquete_surftpv.zip"

:: Nombre de la carpeta anidada
set "NESTED_FOLDER_NAME=paquete_surftpv"
set "NESTED_FULL_PATH=%BASE_DIR%\%NESTED_FOLDER_NAME%"

:: Rutas finales
set "VENV_PATH=%BASE_DIR%\.venv"
set "REQ_FILE=%BASE_DIR%\requirements.txt"
set "TARGET_SCRIPT=%BASE_DIR%\AgenteImpresionTPV\print_agent_beep.py"

:: Rutas de LOGS
set "LOG_OUT=%BASE_DIR%\AgenteImpresionTPV\service_out.log"
set "LOG_ERR=%BASE_DIR%\AgenteImpresionTPV\service_err.log"

set "SERVICE_NAME=SurfTPV_PrintAgent"
set "PYTHON_WINGET_ID=Python.Python.3.14"

echo ===================================================
echo  PASO 1: DESPLEGANDO ARCHIVOS
echo ===================================================

if exist "%ZIP_FILE%" goto ZipFound
echo [ERROR FATAL] No se encuentra el archivo: paquete_surftpv.zip
pause
exit /b

:ZipFound
if not exist "%BASE_DIR%" mkdir "%BASE_DIR%"

echo Descomprimiendo ZIP...
tar -xf "%ZIP_FILE%" -C "%BASE_DIR%"

:: --- LOGICA DE MOVIDO ---
if not exist "%NESTED_FULL_PATH%" goto FilesReady
echo Moviendo archivos al raiz...
robocopy "%NESTED_FULL_PATH%" "%BASE_DIR%" /E /MOVE /IS >nul 2>nul
rmdir /s /q "%NESTED_FULL_PATH%" >nul 2>nul

:FilesReady
echo Estructura lista en %BASE_DIR%

echo.
echo ===================================================
echo  PASO 1.5: INSTALANDO NSSM EN SISTEMA
echo ===================================================

if exist "%BASE_DIR%\nssm.exe" goto MoveNssm
if exist "C:\Windows\nssm.exe" goto NssmInstalled

echo [ERROR] No se encuentra nssm.exe en %BASE_DIR%
goto Finish

:MoveNssm
echo Moviendo nssm.exe a C:\Windows...
move /y "%BASE_DIR%\nssm.exe" "C:\Windows\nssm.exe" >nul
if %ERRORLEVEL% EQU 0 goto NssmInstalled
echo [ERROR] No se pudo mover nssm.exe. Revisa permisos Admin.
goto Finish

:NssmInstalled
echo NSSM esta listo en C:\Windows.

echo.
echo ===================================================
echo  PASO 2: INSTALANDO PYTHON
echo ===================================================

echo Instalando Python...
winget install -e --id %PYTHON_WINGET_ID% --accept-source-agreements --accept-package-agreements

echo.
echo ===================================================
echo  PASO 3: LOCALIZANDO EL LANZADOR PY
echo ===================================================

set "PY_CMD="
where py >nul 2>nul
if %ERRORLEVEL% EQU 0 set "PY_CMD=py"
if defined PY_CMD goto Step4
if exist "C:\Windows\py.exe" set "PY_CMD=C:\Windows\py.exe"
if defined PY_CMD goto Step4
if exist "%LocalAppData%\Programs\Python\Launcher\py.exe" set "PY_CMD=%LocalAppData%\Programs\Python\Launcher\py.exe"
if defined PY_CMD goto Step4
where python >nul 2>nul
if %ERRORLEVEL% EQU 0 set "PY_CMD=python"

if defined PY_CMD goto Step4
echo [ERROR] No se encuentra Python.
pause
exit /b

:Step4
echo.
echo ===================================================
echo  PASO 4: CREANDO ENTORNO VIRTUAL
echo ===================================================

if exist "%VENV_PATH%" goto VenvExists

echo Creando entorno virtual...
"%PY_CMD%" -3.14 -m venv "%VENV_PATH%"
if %ERRORLEVEL% EQU 0 goto Step5

echo [AVISO] Intentando con version reciente...
"%PY_CMD%" -3 -m venv "%VENV_PATH%"
if %ERRORLEVEL% EQU 0 goto Step5

echo [ERROR CRITICO] Fallo la creacion del entorno virtual.
pause
exit /b

:VenvExists
echo El entorno virtual ya existe.

:Step5
echo.
echo ===================================================
echo  PASO 5: INSTALANDO LIBRERIAS
echo ===================================================

if not exist "%VENV_PATH%\Scripts\activate.bat" goto ErrorVenv

echo Activando entorno...
call "%VENV_PATH%\Scripts\activate.bat"

echo Actualizando pip...
python -m pip install --upgrade pip

if exist "%REQ_FILE%" goto InstallReq
echo [ERROR] No se encontro requirements.txt
goto Finish

:InstallReq
echo Instalando librerias...
pip install -r "%REQ_FILE%"

echo.
echo ===================================================
echo  PASO 6: INSTALANDO SERVICIO CON NSSM
echo ===================================================

:: Verificar NSSM global
where nssm >nul 2>nul
if %ERRORLEVEL% NEQ 0 (
    echo [ERROR] NSSM no responde.
    goto Finish
)

set "VENV_PYTHON=%VENV_PATH%\Scripts\python.exe"

if exist "%TARGET_SCRIPT%" goto ConfigureService
echo [ERROR] Falta el script Python: %TARGET_SCRIPT%
goto Finish

:ConfigureService
echo Reinstalando servicio %SERVICE_NAME% ...
nssm stop %SERVICE_NAME% >nul 2>nul
nssm remove %SERVICE_NAME% confirm >nul 2>nul

echo Instalando servicio apuntando al Python del VENV...
nssm install %SERVICE_NAME% "%VENV_PYTHON%" "%TARGET_SCRIPT%"

if %ERRORLEVEL% NEQ 0 goto Finish

echo Configurando parametros base...
nssm set %SERVICE_NAME% AppDirectory "%BASE_DIR%\AgenteImpresionTPV"
nssm set %SERVICE_NAME% Description "Servicio Agente Impresion SurfTPV"

echo Configurando LOGS y Rotacion (5MB)...
nssm set %SERVICE_NAME% AppStdout "%LOG_OUT%"
nssm set %SERVICE_NAME% AppStderr "%LOG_ERR%"
nssm set %SERVICE_NAME% AppRotateFiles 1
nssm set %SERVICE_NAME% AppRotateOnline 1
nssm set %SERVICE_NAME% AppRotateBytes 5242880

echo --- CONFIGURACION AVANZADA DE ENTORNO VIRTUAL ---
echo Inyectando PATH del entorno virtual en el servicio...

:: Esto es crucial: Añadimos la carpeta Scripts al PATH del servicio
:: Así simulamos que se ha hecho un "activate" real.
nssm set %SERVICE_NAME% AppEnvironmentExtra "PATH=%VENV_PATH%\Scripts;%VENV_PATH%;%PATH%"

echo Iniciando servicio...
nssm start %SERVICE_NAME%
echo [EXITO] Despliegue completado.
goto Finish

:ErrorVenv
echo [ERROR] Entorno virtual corrupto.

:Finish
echo.
pause
exit /b
