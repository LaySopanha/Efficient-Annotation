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

REM Shared command prefix to ensure each window uses the same env + working directory.
set "BASE_CMD=cd /d "%REPO_ROOT%" && set LABEL_STUDIO_MODE=%LABEL_STUDIO_MODE% && set LABEL_STUDIO_ROOT=%LABEL_STUDIO_ROOT% && set LABEL_STUDIO_PREFIX=%LABEL_STUDIO_PREFIX%"

echo [INFO] Launching Label Studio, local file server, and PaddleOCR annotator in separate Command Prompt windows.
echo [INFO] Images directory: %IMAGES_DIR%
echo [INFO] Port: %SERVE_PORT%

REM Start Label Studio (leaves window open).
start "Label Studio" cmd /k %BASE_CMD% ^&^& label-studio start

REM Start the local file server.
start "Label Studio Files" cmd /k %BASE_CMD% ^&^& python serve_local_files.py --directory "%IMAGES_DIR%" --host 0.0.0.0 --port %SERVE_PORT%

REM Run the PaddleOCR annotator.
start "Paddle Annotation" cmd /k %BASE_CMD% ^&^& python scripts\run_paddle_annotation.py "%IMAGES_DIR%" %PY_ARGS%

echo [OK] Commands dispatched. Close each window manually when finished.

endlocal
