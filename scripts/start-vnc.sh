#!/usr/bin/env bash
# =============================================================================
# start-vnc.sh — Xvfb + x11vnc + noVNC for login QR scanning
# =============================================================================
set -euo pipefail

DISPLAY="${DISPLAY:-:1}"
VNC_PORT="${VNC_PORT:-5900}"
NOVNC_PORT="${NOVNC_PORT:-6080}"

# Start virtual framebuffer
echo "Starting Xvfb on display ${DISPLAY}..."
Xvfb "${DISPLAY}" -screen 0 1280x1024x24 -ac +extension GLX +render -noreset &
XVFB_PID=$!
sleep 2

# Start x11vnc (no password for local use)
echo "Starting x11vnc on port ${VNC_PORT}..."
x11vnc \
    -display "${DISPLAY}" \
    -forever \
    -shared \
    -rfbport "${VNC_PORT}" \
    -nopw \
    -o /var/log/x11vnc.log &

sleep 1

# Start noVNC websocket proxy
echo "Starting noVNC on port ${NOVNC_PORT}..."
websockify \
    --web /usr/share/novnc/ \
    "${NOVNC_PORT}" \
    "localhost:${VNC_PORT}" &

echo ""
echo "✅ VNC ready:"
echo "   VNC client  : localhost:${VNC_PORT}"
echo "   Web browser : http://localhost:${NOVNC_PORT}/vnc.html"
echo ""

# Keep alive
wait $XVFB_PID
