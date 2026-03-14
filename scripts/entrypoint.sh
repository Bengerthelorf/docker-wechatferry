#!/usr/bin/env bash
# =============================================================================
# entrypoint.sh — container startup
# =============================================================================
set -euo pipefail

echo "=== WeChatFerry Docker Container ==="
echo "NNG_PORT  : ${NNG_PORT:-10087}"
echo "WCF_PORT  : ${WCF_PORT:-10086}"
echo "VNC_PORT  : ${VNC_PORT:-5900}"
echo "NOVNC_PORT: ${NOVNC_PORT:-6080}"
echo ""

# Validate DLLs present
WECHAT_DIR="${WINEPREFIX}/drive_c/Program Files/Tencent/WeChat"
for dll in sdk.dll spy.dll; do
    if [[ ! -f "${WECHAT_DIR}/${dll}" ]]; then
        echo "ERROR: ${WECHAT_DIR}/${dll} not found."
        # Try alternate path
        ALT_DIR="${WINEPREFIX}/drive_c/Program Files (x86)/Tencent/WeChat"
        if [[ -f "${ALT_DIR}/${dll}" ]]; then
            echo "Found at ${ALT_DIR}/${dll}"
        else
            echo "Also not found at ${ALT_DIR}/${dll}"
            echo "Attempting to copy from /opt/wcf-sdk..."
            mkdir -p "${WECHAT_DIR}"
            cp "/opt/wcf-sdk/${dll}" "${WECHAT_DIR}/${dll}" 2>/dev/null || true
            cp "/opt/wcf-sdk/${dll}" "${ALT_DIR}/${dll}" 2>/dev/null || true
        fi
    fi
done

# Block WeChat auto-update domains
echo "127.0.0.1 dldir1.qq.com" >> /etc/hosts 2>/dev/null || true
echo "127.0.0.1 dldir1v6.qq.com" >> /etc/hosts 2>/dev/null || true

echo "Starting supervisord..."
exec "$@"
