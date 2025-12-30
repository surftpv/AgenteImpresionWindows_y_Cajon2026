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

:: CONFIGURACION PYTHON
set "PYTHON_WINGET_ID=Python.Python.3.14"
set "PYTHON_DIRECT_URL=https://www.python.org/ftp/python/3.13.1/python-3.13.1-amd64.exe"
set "PYTHON_INSTALLER=python_setup.exe"

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

:: Busqueda preventiva de instalacion real (evitando los stubs de MS Store)
if exist "C:\Python314\python.exe" goto Step3
if exist "C:\Python313\python.exe" goto Step3
if exist "%ProgramFiles%\Python314\python.exe" goto Step3
if exist "%ProgramFiles%\Python313\python.exe" goto Step3

echo Intento 1: Winget...
winget install -e --id %PYTHON_WINGET_ID% -s winget --accept-source-agreements --accept-package-agreements

if %ERRORLEVEL% EQU 0 goto Step3

echo.
echo [AVISO] Winget fallo. Iniciando descarga directa...
curl -L -o "%BASE_DIR%\%PYTHON_INSTALLER%" "%PYTHON_DIRECT_URL%"

if not exist "%BASE_DIR%\%PYTHON_INSTALLER%" (
    echo [ERROR FATAL] No se pudo descargar Python.
    pause
    exit /b
)

echo Instalando Python (Ruta C:\Python313 para evitar problemas de PATH)...
:: Forzamos instalacion en C:\Python313 para saber EXACTAMENTE donde esta
"%BASE_DIR%\%PYTHON_INSTALLER%" /quiet InstallAllUsers=1 PrependPath=1 TargetDir=C:\Python313 Include_test=0

del "%BASE_DIR%\%PYTHON_INSTALLER%"

echo.
echo ===================================================
echo  PASO 3: LOCALIZANDO EL EJECUTABLE REAL
echo ===================================================

:Step3
set "REAL_PYTHON="

:: 1. Si instalamos manualmente en el paso anterior, sabemos que esta aqui:
if exist "C:\Python313\python.exe" set "REAL_PYTHON=C:\Python313\python.exe"
if defined REAL_PYTHON goto FoundPy

:: 2. Buscar instalaciones estandar de Winget
if exist "%ProgramFiles%\Python314\python.exe" set "REAL_PYTHON=%ProgramFiles%\Python314\python.exe"
if defined REAL_PYTHON goto FoundPy

if exist "%ProgramFiles%\Python313\python.exe" set "REAL_PYTHON=%ProgramFiles%\Python313\python.exe"
if defined REAL_PYTHON goto FoundPy

:: 3. Buscar el lanzador PY de Windows (Solo si existe el real, no el fake)
if exist "C:\Windows\py.exe" (
    :: Probamos si responde
    "C:\Windows\py.exe" --version >nul 2>nul
    if %ERRORLEVEL% EQU 0 set "REAL_PYTHON=C:\Windows\py.exe"
)
if defined REAL_PYTHON goto FoundPy

:: 4. Ultimo recurso: Buscar en AppData local
for /d %%D in ("%LocalAppData%\Programs\Python\Python3*") do (
    if exist "%%D\python.exe" set "REAL_PYTHON=%%D\python.exe"
)

if defined REAL_PYTHON goto FoundPy

echo [ERROR] No se encuentra un Python.exe valido.
echo Los alias de ejecucion de Windows pueden estar interfiriendo.
echo Por favor reinicia o instala Python manualmente.
pause
exit /b

:FoundPy
echo Python encontrado en: "%REAL_PYTHON%"

echo.
echo ===================================================
echo  PASO 4: CREANDO ENTORNO VIRTUAL
echo ===================================================

if exist "%VENV_PATH%" goto VenvExists

echo Creando entorno virtual...
:: Usamos las comillas por si la ruta tiene espacios
"%REAL_PYTHON%" -m venv "%VENV_PATH%"

if %ERRORLEVEL% NEQ 0 (
    echo [ERROR CRITICO] Fallo la creacion del entorno virtual.
    echo Asegurate de no tener una version corrupta de Python.
    pause
    exit /b
)

:VenvExists
echo El entorno virtual ya existe.

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

echo Instalando servicio...
nssm install %SERVICE_NAME% "%VENV_PYTHON%" "%TARGET_SCRIPT%"

if %ERRORLEVEL% NEQ 0 goto Finish

echo Configurando parametros...
nssm set %SERVICE_NAME% AppDirectory "%BASE_DIR%\AgenteImpresionTPV"
nssm set %SERVICE_NAME% Description "Servicio Agente Impresion SurfTPV"

echo Configurando LOGS y Rotacion (5MB)...
nssm set %SERVICE_NAME% AppStdout "%LOG_OUT%"
nssm set %SERVICE_NAME% AppStderr "%LOG_ERR%"
nssm set %SERVICE_NAME% AppRotateFiles 1
nssm set %SERVICE_NAME% AppRotateOnline 1
nssm set %SERVICE_NAME% AppRotateBytes 5242880

echo Inyectando entorno virtual...
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
