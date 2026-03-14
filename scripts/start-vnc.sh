#!/usr/bin/env bash
# =============================================================================
# start-vnc.sh — start Xvfb + x11vnc + noVNC for login QR code scanning
# =============================================================================
set -euo pipefail

DISPLAY="${DISPLAY:-:1}"
VNC_PORT="${VNC_PORT:-5900}"
NOVNC_PORT="${NOVNC_PORT:-6080}"
VNC_PASSWD_FILE=/tmp/vnc-passwd

# Set optional VNC password (set VNC_PASSWORD env var to enable)
if [[ -n "${VNC_PASSWORD:-}" ]]; then
    x11vnc -storepasswd "${VNC_PASSWORD}" "${VNC_PASSWD_FILE}"
    VNC_AUTH="-rfbauth ${VNC_PASSWD_FILE}"
else
    echo "⚠ VNC: No password set. Set VNC_PASSWORD env var for production use."
    VNC_AUTH="-nopw"
fi

# Start virtual framebuffer
echo "Starting Xvfb on display ${DISPLAY}..."
Xvfb "${DISPLAY}" -screen 0 1280x1024x24 -ac +extension GLX +render -noreset &
XVFB_PID=$!
sleep 1

# Start x11vnc
echo "Starting x11vnc on port ${VNC_PORT}..."
x11vnc \
    -display "${DISPLAY}" \
    -forever \
    -shared \
    -rfbport "${VNC_PORT}" \
    ${VNC_AUTH} \
    -o /var/log/x11vnc.log &

# Start noVNC websocket proxy
echo "Starting noVNC on port ${NOVNC_PORT}..."
websockify \
    --web /usr/share/novnc/ \
    "${NOVNC_PORT}" \
    "localhost:${VNC_PORT}" &

echo ""
echo "✅ VNC ready — connect via:"
echo "   VNC client  : localhost:${VNC_PORT}"
echo "   Web browser : http://localhost:${NOVNC_PORT}/vnc.html"
echo ""

# Keep alive
wait $XVFB_PID
