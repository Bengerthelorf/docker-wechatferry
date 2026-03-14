#!/usr/bin/env bash
# =============================================================================
# start-wechat.sh — launch WeChat under Wine
# =============================================================================
set -euo pipefail

WECHAT_EXE="${WINEPREFIX}/drive_c/Program Files (x86)/Tencent/WeChat/WeChat.exe"

if [[ ! -f "${WECHAT_EXE}" ]]; then
    echo "ERROR: WeChat.exe not found at ${WECHAT_EXE}"
    exit 1
fi

echo "Starting WeChat ${WECHAT_EXE} ..."
exec wine64 "${WECHAT_EXE}"
