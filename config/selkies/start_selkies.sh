#!/bin/bash
# Starts Xvfb, XFCE, PipeWire, coturn, and selkies-gstreamer.
# Invoked by JupyterLab ServerProxy when the user opens the Desktop launcher.
set -e

# Clean up child processes on exit
cleanup() {
    echo "[selkies] Shutting down..."
    kill $(jobs -p) 2>/dev/null || true
}
trap cleanup EXIT

echo "[selkies] Starting desktop environment..."

# -------------------------------------------------------------------
# GStreamer environment
# -------------------------------------------------------------------
. /opt/gstreamer/gst-env

export DISPLAY="${DISPLAY:-:20}"
export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/tmp/runtime-$(id -u)}"
mkdir -p "${XDG_RUNTIME_DIR}"
chmod 700 "${XDG_RUNTIME_DIR}"

# -------------------------------------------------------------------
# Xvfb (virtual framebuffer)
# -------------------------------------------------------------------
if [ ! -S "/tmp/.X11-unix/X${DISPLAY#*:}" ]; then
    /usr/bin/Xvfb "${DISPLAY}" -screen 0 "8192x4096x24" \
        +extension COMPOSITE +extension DAMAGE +extension GLX \
        +extension RANDR +extension RENDER +extension MIT-SHM \
        +extension XFIXES +extension XTEST \
        +iglx +render -nolisten tcp -ac -noreset -shmem \
        >/tmp/Xvfb.log 2>&1 &
    echo "[selkies] Waiting for X socket..."
    until [ -S "/tmp/.X11-unix/X${DISPLAY#*:}" ]; do sleep 0.5; done
fi
echo "[selkies] X server ready on ${DISPLAY}"

# Set initial resolution (user can resize dynamically via Selkies UI)
selkies-resize "${SELKIES_INIT_RESOLUTION:-1920x1080}" 2>/dev/null || true

# -------------------------------------------------------------------
# XFCE desktop session
# -------------------------------------------------------------------
/usr/bin/dbus-launch --exit-with-session /usr/bin/xfce4-session \
    >/tmp/xfce4.log 2>&1 &
echo "[selkies] XFCE session started"

# -------------------------------------------------------------------
# PipeWire audio (best-effort -- not critical for PoC)
# -------------------------------------------------------------------
export PIPEWIRE_LATENCY="128/48000"
export PIPEWIRE_RUNTIME_DIR="${XDG_RUNTIME_DIR}"
export PULSE_RUNTIME_PATH="${XDG_RUNTIME_DIR}/pulse"
export PULSE_SERVER="unix:${PULSE_RUNTIME_PATH}/native"
mkdir -p "${PULSE_RUNTIME_PATH}"

if command -v pipewire >/dev/null 2>&1; then
    pipewire >/tmp/pipewire.log 2>&1 &
    sleep 1
    wireplumber >/tmp/wireplumber.log 2>&1 &
    sleep 0.5
    # PulseAudio compatibility layer
    if command -v pipewire-pulse >/dev/null 2>&1; then
        pipewire-pulse >/tmp/pipewire-pulse.log 2>&1 &
    else
        pipewire -c pipewire-pulse.conf >/tmp/pipewire-pulse.log 2>&1 &
    fi
    echo "[selkies] PipeWire audio started"
else
    echo "[selkies] PipeWire not found, skipping audio"
fi

# -------------------------------------------------------------------
# Embedded TURN server (coturn)
# Required for WebRTC media transport inside containers.
# The browser cannot reach the container IP directly, so TURN
# relays the video/audio stream.
# -------------------------------------------------------------------
TURN_PASSWORD="$(tr -dc 'A-Za-z0-9' < /dev/urandom 2>/dev/null | head -c 24)"
TURN_PORT="${SELKIES_TURN_PORT:-3478}"
TURN_HOST="${SELKIES_TURN_HOST:-$(hostname -I 2>/dev/null | awk '{print $1; exit}' || echo '127.0.0.1')}"

if [ "${SELKIES_DISABLE_TURN:-false}" != "true" ]; then
    turnserver \
        --listening-ip=0.0.0.0 \
        --listening-port="${TURN_PORT}" \
        --realm=example.com \
        --external-ip="${TURN_HOST}" \
        --min-port="${TURN_MIN_PORT:-49152}" \
        --max-port="${TURN_MAX_PORT:-49252}" \
        --lt-cred-mech \
        --user="selkies:${TURN_PASSWORD}" \
        --no-cli \
        --cli-password="${TURN_PASSWORD}" \
        --log-file=stdout \
        --allow-loopback-peers \
        --pidfile="${XDG_RUNTIME_DIR}/turnserver.pid" \
        >/tmp/coturn.log 2>&1 &
    echo "[selkies] TURN server started (${TURN_HOST}:${TURN_PORT})"
else
    echo "[selkies] TURN disabled via SELKIES_DISABLE_TURN"
    TURN_HOST=""
    TURN_PORT=""
    TURN_PASSWORD=""
fi

# -------------------------------------------------------------------
# Selkies-GStreamer (foreground -- keeps ServerProxy alive)
# -------------------------------------------------------------------
echo "[selkies] Starting Selkies-GStreamer on port 8082..."

SELKIES_ARGS=(
    --addr=0.0.0.0
    --port=8082
    --enable_https=false
    --web_root="${SELKIES_WEB_ROOT:-/opt/gst-web}"
    --encoder="${SELKIES_ENCODER:-x264enc}"
    --enable_resize="${SELKIES_ENABLE_RESIZE:-true}"
    --basic_auth_user="${USER:-jovyan}"
    --basic_auth_password="${SELKIES_PASSWORD:-password}"
)

# Only pass TURN args if TURN is enabled
if [ -n "${TURN_HOST}" ]; then
    SELKIES_ARGS+=(
        --turn_host="${TURN_HOST}"
        --turn_port="${TURN_PORT}"
        --turn_username="selkies"
        --turn_password="${TURN_PASSWORD}"
    )
fi

exec selkies-gstreamer "${SELKIES_ARGS[@]}" ${SELKIES_EXTRA_ARGS:-}
