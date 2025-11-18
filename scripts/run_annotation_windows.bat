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
if not defined RUN_LABELSTUDIO set "RUN_LABELSTUDIO=1"
if not defined RUN_SERVER set "RUN_SERVER=1"
if not defined RUN_ANNOTATOR set "RUN_ANNOTATOR=1"

set "IMAGES_DIR="
set "CLI_ARGS="

:parse_wrapper_args
if "%~1"=="" goto after_wrapper_args
if /I "%~1"=="--help" (
    call :print_usage
    exit /b 0
)
if /I "%~1"=="--no-labelstudio" (
    set "RUN_LABELSTUDIO=0"
    shift
    goto parse_wrapper_args
)
if /I "%~1"=="--no-serve" (
    set "RUN_SERVER=0"
    shift
    goto parse_wrapper_args
)
if /I "%~1"=="--no-annotator" (
    set "RUN_ANNOTATOR=0"
    shift
    goto parse_wrapper_args
)
if "%~1"=="--" (
    shift
    goto collect_args
)
if not defined IMAGES_DIR (
    set "IMAGES_DIR=%~1"
    shift
    goto collect_args
)
goto collect_args

:after_wrapper_args
if not defined IMAGES_DIR set "IMAGES_DIR=%ANNOTATION_INPUT_DIR%"

:collect_args
if "%~1"=="" goto args_done
set "CLI_ARGS=%CLI_ARGS% %~1"
shift
goto collect_args
:args_done

set "NEED_IMAGE_DIR=0"
if "%RUN_SERVER%"=="1" set "NEED_IMAGE_DIR=1"
if "%RUN_ANNOTATOR%"=="1" set "NEED_IMAGE_DIR=1"

if "%NEED_IMAGE_DIR%"=="1" (
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
)

echo [INFO] Repository root: %REPO_ROOT%
if "%NEED_IMAGE_DIR%"=="1" (
    echo [INFO] Serving directory: %LABEL_STUDIO_ROOT%
)
if defined CLI_ARGS (
    echo [INFO] Extra PaddleOCR args:%CLI_ARGS%
)

echo [INFO] Launching requested processes...

if "%RUN_LABELSTUDIO%"=="1" (
    start "Label Studio" /D "%REPO_ROOT%" cmd /k "%LABELSTUDIO_CMD%"
) else (
    echo [INFO] Skipping Label Studio (--no-labelstudio).
)

if "%RUN_SERVER%"=="1" (
    start "Label Studio Files" /D "%REPO_ROOT%" cmd /k ""%PYTHON_CMD%" serve_local_files.py --directory "%LABEL_STUDIO_ROOT%" --host %SERVE_HOST% --port %SERVE_PORT%""
) else (
    echo [INFO] Skipping local file server (--no-serve).
)

if "%RUN_ANNOTATOR%"=="1" (
    start "Paddle Annotation" /D "%REPO_ROOT%" cmd /k ""%PYTHON_CMD%" scripts\run_paddle_annotation.py "%ABS_IMAGES_DIR%"%CLI_ARGS%""
) else (
    echo [INFO] Skipping PaddleOCR annotator (--no-annotator).
)

echo [OK] Processes started. Close each window to stop its process.
exit /b 0

:print_usage
echo Usage: scripts\run_annotation_windows.bat [wrapper options] [images_dir] [-- paddle_args...]
echo.
echo Wrapper options:
echo   --no-labelstudio    Do not launch Label Studio.
echo   --no-serve          Do not start the local file server.
echo   --no-annotator      Do not run the PaddleOCR annotator.
echo   --help              Show this message.
echo   --                  Treat the rest of the arguments as PaddleOCR CLI flags.
goto :eof
