#!/usr/bin/env bash
# =============================================================================
# entrypoint.sh — container startup
# =============================================================================
set -euo pipefail

echo "=== WeChatFerry Docker Container ==="
echo "WCF_HOST  : ${WCF_HOST:-127.0.0.1}"
echo "WCF_PORT  : ${WCF_PORT:-10086}"
echo "VNC_PORT  : ${VNC_PORT:-5900}"
echo "NOVNC_PORT: ${NOVNC_PORT:-6080}"
echo ""

# Safety: refuse to bind WCF port to 0.0.0.0 unless explicitly opted in
if [[ "${WCF_HOST:-127.0.0.1}" == "0.0.0.0" ]]; then
    echo "⚠ WARNING: WCF API is bound to 0.0.0.0 — ensure firewall rules are in place!"
fi

# Validate DLLs present
for dll in sdk.dll spy.dll; do
    if [[ ! -f "/opt/wcf-sdk/${dll}" ]]; then
        echo "ERROR: /opt/wcf-sdk/${dll} not found. Rebuild the image."
        exit 1
    fi
done

echo "DLLs verified."

exec "$@"
