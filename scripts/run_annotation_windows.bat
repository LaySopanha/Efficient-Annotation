@echo off
REM Windows helper to start Label Studio, serve local files, and run PaddleOCR batch annotations.
REM Run this from an Anaconda Prompt where your environment (with paddleocr + label-studio) is already active.

setlocal enabledelayedexpansion

REM Determine repository root relative to this script.
set "SCRIPT_DIR=%~dp0"
for %%I in ("%SCRIPT_DIR%..") do set "REPO_ROOT=%%~fI"

REM Resolve the images directory: optional first argument overrides the default.
set "IMAGES_DIR=%ANNOTATION_INPUT_DIR%"
if not defined IMAGES_DIR (
    set "IMAGES_DIR=%REPO_ROOT%\data\raw"
)
if not "%~1"=="" (
    set "IMAGES_DIR=%~f1"
    shift
)

REM Additional args passed to run_paddle_annotation.py after optional positional override.
set "PY_ARGS=%*"

REM Allow SERVE_PORT override via environment variable.
if not defined SERVE_PORT (
    set "SERVE_PORT=8081"
)

set "LABEL_STUDIO_MODE=http"
set "LABEL_STUDIO_ROOT=%IMAGES_DIR%"
set "LABEL_STUDIO_PREFIX=http://localhost:%SERVE_PORT%/"

echo [INFO] Launching Label Studio, local file server, and PaddleOCR annotator in separate Command Prompt windows.
echo [INFO] Images directory: %IMAGES_DIR%
echo [INFO] Port: %SERVE_PORT%

call :launch_window "Label Studio" "label-studio start"
call :launch_window "Label Studio Files" "python serve_local_files.py --directory ""%IMAGES_DIR%"" --host 0.0.0.0 --port %SERVE_PORT%"
call :launch_window "Paddle Annotation" "python scripts\run_paddle_annotation.py ""%IMAGES_DIR%"" %PY_ARGS%"

echo [OK] Commands dispatched. Close each window manually when finished.

endlocal
goto :eof

:launch_window
set "TITLE=%~1"
set "CMD=%~2"
set "TMP=%TEMP%\annot_%RANDOM%%RANDOM%.cmd"
(
    echo @echo off
    echo cd /d "%REPO_ROOT%"
    echo set "LABEL_STUDIO_MODE=%LABEL_STUDIO_MODE%"
    echo set "LABEL_STUDIO_ROOT=%LABEL_STUDIO_ROOT%"
    echo set "LABEL_STUDIO_PREFIX=%LABEL_STUDIO_PREFIX%"
    echo %CMD%
) > "%TMP%"
start "%TITLE%" cmd /k "%TMP%"
goto :eof
