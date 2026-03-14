#!/usr/bin/env bash
# =============================================================================
# start-injector.sh — Run injector.exe under Wine to load sdk.dll + inject spy.dll
# =============================================================================
set -euo pipefail

NNG_PORT="${NNG_PORT:-10087}"

# Wait for Xvfb to be ready
echo "Waiting for display ${DISPLAY}..."
TIMEOUT=30
ELAPSED=0
while ! xdpyinfo -display "${DISPLAY}" >/dev/null 2>&1; do
    if [[ $ELAPSED -ge $TIMEOUT ]]; then
        echo "ERROR: Display ${DISPLAY} not ready after ${TIMEOUT}s"
        exit 1
    fi
    sleep 1
    ELAPSED=$((ELAPSED + 1))
done
echo "Display ready."

# Find WeChat installation directory (could be Program Files or Program Files (x86))
WECHAT_DIR=""
for d in \
    "${WINEPREFIX}/drive_c/Program Files/Tencent/WeChat" \
    "${WINEPREFIX}/drive_c/Program Files (x86)/Tencent/WeChat"; do
    if [[ -f "${d}/WeChat.exe" ]]; then
        WECHAT_DIR="${d}"
        break
    fi
done

if [[ -z "${WECHAT_DIR}" ]]; then
    echo "ERROR: WeChat.exe not found in any expected path"
    echo "Checking wine prefix structure..."
    find "${WINEPREFIX}/drive_c" -name "WeChat.exe" 2>/dev/null || echo "No WeChat.exe found"
    exit 1
fi

echo "WeChat dir: ${WECHAT_DIR}"

# Ensure DLLs are in place
for dll in sdk.dll spy.dll; do
    if [[ ! -f "${WECHAT_DIR}/${dll}" ]]; then
        echo "Copying ${dll} to WeChat directory..."
        cp "/opt/wcf-sdk/${dll}" "${WECHAT_DIR}/${dll}"
    fi
done

# Ensure injector.exe is in WeChat directory (so it can find sdk.dll)
if [[ ! -f "${WECHAT_DIR}/injector.exe" ]]; then
    cp /opt/wcf-sdk/injector.exe "${WECHAT_DIR}/injector.exe"
fi

echo "Starting injector (port=${NNG_PORT})..."
cd "${WECHAT_DIR}"

# Run injector under Wine — this will:
# 1. Load sdk.dll
# 2. Call WxInitSDK which starts WeChat and injects spy.dll
# 3. spy.dll starts NNG server on port ${NNG_PORT} and ${NNG_PORT}+1
exec wine64 "${WECHAT_DIR}/injector.exe" "${NNG_PORT}"
