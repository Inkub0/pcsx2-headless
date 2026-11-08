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

# CVT reduced-blanking modeline (the same numbers as "cvt -r"), e.g.
#   cvt_rb 1920 1080 60 -> "1920x1080R" 138.50 1920 1968 2000 2080 1080 1083 1088 1111 +hsync -vsync
# Names: "<W>x<H>R" at 60 Hz, "<W>x<H>_<rate>R" otherwise.
cvt_rb() {
    awk -v W="$1" -v H="$2" -v R="$3" 'BEGIN {
        w = int(W / 8) * 8; h = H
        if      (h % 3 == 0  && h * 4 / 3   == w) vs = 4
        else if (h % 9 == 0  && h * 16 / 9  == w) vs = 5
        else if (h % 10 == 0 && h * 16 / 10 == w) vs = 6
        else if (h % 4 == 0  && h * 5 / 4   == w) vs = 7
        else if (h % 9 == 0  && h * 15 / 9  == w) vs = 7
        else vs = 10
        hperiod = ((1000000.0 / R) - 460.0) / h
        vbi = int(460.0 / hperiod + 1)
        if (vbi < 3 + vs + 6) vbi = 3 + vs + 6
        vtotal = h + vbi
        htotal = w + 160
        clock = int(R * vtotal * htotal / 1000.0)
        clock -= clock % 250
        name = (R == 60) ? sprintf("%dx%dR", w, h) : sprintf("%dx%d_%dR", w, h, R)
        printf "\"%s\" %.2f %d %d %d %d %d %d %d %d +hsync -vsync\n", name, clock / 1000.0,
            w, w + 48, w + 80, htotal, h, h + 3, h + 3 + vs, vtotal
    }'
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
