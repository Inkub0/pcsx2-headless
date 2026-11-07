# Shared helpers for PCSX2 Headless scripts. Sourced, not executed.

RUNTIME_DIR=/run/pcsx2-headless
RUNTIME_ENV=$RUNTIME_DIR/env
USER_RUNTIME_DIR=/tmp/runtime-pcsx2
PULSE_SOCKET=$USER_RUNTIME_DIR/pulse/native
# Messages from commands Sunshine runs (whose own output Sunshine discards) go here;
# the "events" service copies them to the container log.
EVENT_LOG=$USER_RUNTIME_DIR/events.log
export DISPLAY=:0

log()  { echo "[pcsx2-headless] $*" >&2; }   # stderr: never pollute redirected output (e.g. xorg.conf)
warn() { echo "[pcsx2-headless] WARNING: $*" >&2; }
die()  { echo "[pcsx2-headless] ERROR: $*" >&2; exit 1; }

is_true() { case "${1,,}" in 1|true|yes|on) return 0 ;; *) return 1 ;; esac; }

# Values detected by the entrypoint (GPU type, DRM card, render node).
load_runtime_env() {
    if [ -f "$RUNTIME_ENV" ]; then
        set -a
        # shellcheck disable=SC1090
        . "$RUNTIME_ENV"
        set +a
    fi
}

# Run a command as the pcsx2 user (with its supplementary groups) and return.
# /usr/local/bin/user-env sets HOME, XDG_* and audio/display variables and drops SUNSHINE_PASS.
as_user() {
    setpriv --reuid="${PUID:-568}" --regid="${PGID:-568}" --init-groups /usr/local/bin/user-env "$@"
}

# Replace the current process with a command running as the pcsx2 user.
exec_as_user() {
    exec setpriv --reuid="${PUID:-568}" --regid="${PGID:-568}" --init-groups /usr/local/bin/user-env "$@"
}

wait_for_x() {
    local i
    for i in $(seq 1 "${1:-60}"); do
        xset -display :0 q >/dev/null 2>&1 && return 0
        sleep 1
    done
    return 1
}

wait_for_file() {
    local f=$1 t=${2:-30} i
    for i in $(seq 1 "$t"); do
        [ -e "$f" ] && return 0
        sleep 1
    done
    return 1
}

nvidia_driver_version() {
    local v=""
    if [ -r /proc/driver/nvidia/version ]; then
        v=$(head -n1 /proc/driver/nvidia/version | grep -oE '[0-9]+\.[0-9]+(\.[0-9]+)?' | head -n1 || true)
    fi
    if [ -z "$v" ] && command -v nvidia-smi >/dev/null 2>&1; then
        v=$(nvidia-smi --query-gpu=driver_version --format=csv,noheader 2>/dev/null | head -n1 || true)
    fi
    echo "$v"
}

# "0000:0a:00.0" or "00000000:0A:00.0" -> "PCI:10:0:0" (Xorg wants decimal)
pci_to_busid() {
    local addr=${1##*/} bus dev fn
    addr=${addr#*:}
    bus=${addr%%:*}
    dev=${addr#*:}; dev=${dev%%.*}
    fn=${addr##*.}
    printf 'PCI:%d:%d:%d' "0x$bus" "0x$dev" "0x$fn"
}
