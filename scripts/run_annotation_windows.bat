@echo off
rem Windows helper that launches Label Studio, the local file server, and the PaddleOCR annotator.
setlocal

set "SCRIPT_DIR=%~dp0"
for %%i in ("%SCRIPT_DIR%..") do set "REPO_ROOT=%%~fi"
if not defined REPO_ROOT (
    echo [ERROR] Unable to determine repository root based on %SCRIPT_DIR%.
    exit /b 1
)

if defined PYTHON_BIN (
    set "PYTHON_CMD=%PYTHON_BIN%"
) else (
    set "PYTHON_CMD=python"
)

if defined LABELSTUDIO_CMD (
    set "LABELSTUDIO_CMD=%LABELSTUDIO_CMD%"
) else (
    set "LABELSTUDIO_CMD=label-studio start"
)

if not defined SERVE_HOST set "SERVE_HOST=0.0.0.0"
if not defined SERVE_PORT set "SERVE_PORT=8081"
if not defined ANNOTATION_INPUT_DIR set "ANNOTATION_INPUT_DIR=data\raw"

set "IMAGES_DIR=%ANNOTATION_INPUT_DIR%"
if not "%~1"=="" (
    set "IMAGES_DIR=%~1"
    shift
)

set "CLI_ARGS="
:collect_args
if "%~1"=="" goto args_done
set "CLI_ARGS=%CLI_ARGS% %~1"
shift
goto collect_args
:args_done

pushd "%REPO_ROOT%" >nul
for %%i in ("%IMAGES_DIR%") do set "ABS_IMAGES_DIR=%%~fi"
popd >nul

if not defined ABS_IMAGES_DIR (
    echo [ERROR] Could not resolve images directory "%IMAGES_DIR%".
    exit /b 2
)

if not exist "%ABS_IMAGES_DIR%" (
    echo [ERROR] Images directory "%ABS_IMAGES_DIR%" does not exist.
    exit /b 3
)

set "LABEL_STUDIO_MODE=http"
set "LABEL_STUDIO_ROOT=%ABS_IMAGES_DIR%"
set "LABEL_STUDIO_PREFIX=http://localhost:%SERVE_PORT%/"

echo [INFO] Repository root: %REPO_ROOT%
echo [INFO] Serving directory: %LABEL_STUDIO_ROOT%
if defined CLI_ARGS (
    echo [INFO] Extra PaddleOCR args:%CLI_ARGS%
)
echo [INFO] Launching Label Studio, local file server, and PaddleOCR CLI in separate Command Prompt windows...

start "Label Studio" /D "%REPO_ROOT%" cmd /k "%LABELSTUDIO_CMD%"
start "Label Studio Files" /D "%REPO_ROOT%" cmd /k ""%PYTHON_CMD%" serve_local_files.py --directory "%LABEL_STUDIO_ROOT%" --host %SERVE_HOST% --port %SERVE_PORT%""
start "Paddle Annotation" /D "%REPO_ROOT%" cmd /k ""%PYTHON_CMD%" scripts\run_paddle_annotation.py "%ABS_IMAGES_DIR%"%CLI_ARGS%""

echo [OK] Processes started. Close each window to stop its process.
exit /b 0
