#!/usr/bin/env bash
# Wrapper that can spin up the local-file server and run the PaddleOCR batch annotator.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
PYTHON_BIN="${PYTHON_BIN:-python3}"

SERVE=1
LABELSTUDIO=1
SERVE_HOST="${SERVE_HOST:-0.0.0.0}"
SERVE_PORT="${SERVE_PORT:-8081}"
SERVE_DIR_OVERRIDE=""
LABELSTUDIO_CMD_DEFAULT="label-studio start"
LABELSTUDIO_CMD="${LABELSTUDIO_CMD:-$LABELSTUDIO_CMD_DEFAULT}"
USE_TERMINALS="${USE_TERMINALS:-0}"
TERMINAL_CMD="${TERMINAL_CMD:-gnome-terminal}"

POSITIONAL_ARGS=()
while [[ $# -gt 0 ]]; do
    case "$1" in
        --no-serve)
            SERVE=0
            shift
            ;;
        --no-labelstudio)
            LABELSTUDIO=0
            shift
            ;;
        --terminals)
            USE_TERMINALS=1
            shift
            ;;
        --serve-host)
            SERVE_HOST="$2"
            shift 2
            ;;
        --serve-port)
            SERVE_PORT="$2"
            shift 2
            ;;
        --serve-dir)
            SERVE_DIR_OVERRIDE="$2"
            shift 2
            ;;
        --)
            shift
            break
            ;;
        --help-serve)
            cat <<'EOF'
Wrapper options (must appear before PaddleOCR arguments):
  --no-serve             Do not launch serve_local_files.py
  --no-labelstudio       Do not launch Label Studio (assumes it's already running)
  --terminals            Open each process (Label Studio, server, annotator) in separate terminals
  --serve-host HOST      Host/IP for serve_local_files.py (default: 0.0.0.0)
  --serve-port PORT      Port for serve_local_files.py and LABEL_STUDIO_PREFIX (default: 8081)
  --serve-dir DIR        Directory to expose + default LABEL_STUDIO_ROOT (default: repo/data/raw)
  --labelstudio-cmd CMD  Command used to start Label Studio (default: "label-studio start")
  --terminal-cmd CMD     Terminal emulator command (default: gnome-terminal)
  --help-serve           Show this message
EOF
            exit 0
            ;;
        --labelstudio-cmd)
            LABELSTUDIO_CMD="$2"
            shift 2
            ;;
        --terminal-cmd)
            TERMINAL_CMD="$2"
            shift 2
            ;;
        *)
            break
            ;;
    esac
done
POSITIONAL_ARGS+=("$@")

if [[ -n "$SERVE_DIR_OVERRIDE" ]]; then
    LABEL_STUDIO_ROOT="$SERVE_DIR_OVERRIDE"
fi
: "${LABEL_STUDIO_ROOT:=${REPO_ROOT}/data/raw}"
LABEL_STUDIO_ROOT="$(cd "${LABEL_STUDIO_ROOT}" && pwd)"

: "${LABEL_STUDIO_MODE:=http}"
: "${LABEL_STUDIO_PREFIX:=http://localhost:${SERVE_PORT}/}"
export LABEL_STUDIO_MODE
export LABEL_STUDIO_ROOT
export LABEL_STUDIO_PREFIX

require_terminal_cmd() {
    if ! command -v "${TERMINAL_CMD}" >/dev/null 2>&1; then
        echo "[ERROR] Terminal command '${TERMINAL_CMD}' not found. Specify --terminal-cmd." >&2
        exit 2
    fi
}

join_cmd() {
    local result=""
    for arg in "$@"; do
        result+=$(printf '%q ' "$arg")
    done
    printf '%s' "${result% }"
}

launch_in_terminal() {
    local title="$1"
    local hold="$2"
    shift 2
    local cmd="$*"
    require_terminal_cmd
    local script
    script="$(mktemp)"
    {
        printf '#!/usr/bin/env bash\n'
        printf 'set -euo pipefail\n'
        printf 'cd %q\n' "${REPO_ROOT}"
        printf 'export LABEL_STUDIO_MODE=%q\n' "${LABEL_STUDIO_MODE}"
        printf 'export LABEL_STUDIO_ROOT=%q\n' "${LABEL_STUDIO_ROOT}"
        printf 'export LABEL_STUDIO_PREFIX=%q\n' "${LABEL_STUDIO_PREFIX}"
        printf '%s\n' "${cmd}"
        printf 'status=$?\n'
        if [[ "${hold}" -eq 1 ]]; then
            printf 'echo\n'
            printf 'echo "[%s] exited with code ${status}."\n' "${title}"
            printf 'read -r -p "Press Enter to close this window..." _\n'
        else
            printf 'exit ${status}\n'
        fi
        printf 'rm -- "$0"\n'
    } > "${script}"
    chmod +x "${script}"
    "${TERMINAL_CMD}" --title "${title}" -- bash -lc "exec $(printf '%q' "${script}")" &
    echo $!
}

server_pid=""
labelstudio_pid=""
cleanup() {
    if [[ "${USE_TERMINALS}" -eq 1 ]]; then
        return
    fi
    if [[ -n "$server_pid" ]]; then
        if kill -0 "$server_pid" 2>/dev/null; then
            kill "$server_pid" 2>/dev/null || true
            wait "$server_pid" 2>/dev/null || true
        fi
    fi
    if [[ -n "$labelstudio_pid" ]]; then
        if kill -0 "$labelstudio_pid" 2>/dev/null; then
            kill "$labelstudio_pid" 2>/dev/null || true
            wait "$labelstudio_pid" 2>/dev/null || true
        fi
    fi
}
trap cleanup EXIT

if [[ "$LABELSTUDIO" -eq 1 ]]; then
    if [[ "${USE_TERMINALS}" -eq 1 ]]; then
        echo "[INFO] Launching Label Studio in a new terminal window."
        launch_in_terminal "Label Studio" 0 "${LABELSTUDIO_CMD}" >/dev/null
    else
        echo "[INFO] Starting Label Studio via: ${LABELSTUDIO_CMD}"
        bash -c "${LABELSTUDIO_CMD}" &
        labelstudio_pid=$!
        sleep 5
    fi
fi

if [[ "$SERVE" -eq 1 ]]; then
    if [[ "${USE_TERMINALS}" -eq 1 ]]; then
        echo "[INFO] Launching local file server in a new terminal window."
        launch_in_terminal "Label Studio Files" 0 "$(join_cmd "${PYTHON_BIN}" "${REPO_ROOT}/serve_local_files.py" --directory "${LABEL_STUDIO_ROOT}" --host "${SERVE_HOST}" --port "${SERVE_PORT}")" >/dev/null
    else
        echo "[INFO] Starting local file server on ${SERVE_HOST}:${SERVE_PORT} serving ${LABEL_STUDIO_ROOT}"
        "${PYTHON_BIN}" "${REPO_ROOT}/serve_local_files.py" \
            --directory "${LABEL_STUDIO_ROOT}" \
            --host "${SERVE_HOST}" \
            --port "${SERVE_PORT}" &
        server_pid=$!
        sleep 1
    fi
fi

if [[ "${USE_TERMINALS}" -eq 1 ]]; then
    echo "[INFO] Launching PaddleOCR batch annotator in a new terminal window."
    launch_in_terminal "Paddle Annotation" 1 "$(join_cmd "${PYTHON_BIN}" "${REPO_ROOT}/scripts/run_paddle_annotation.py" "${POSITIONAL_ARGS[@]}")" >/dev/null
    echo "[OK] All processes started in separate terminals. Close each window to stop its process."
    exit 0
fi

set +e
"${PYTHON_BIN}" "${REPO_ROOT}/scripts/run_paddle_annotation.py" "${POSITIONAL_ARGS[@]}"
status=$?
set -e

exit "$status"
