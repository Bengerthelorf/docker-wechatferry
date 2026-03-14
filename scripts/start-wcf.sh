#!/usr/bin/env bash
# =============================================================================
# start-wcf.sh — start WeChatFerry Node.js bridge
# =============================================================================
set -euo pipefail

# Wait for WeChat to be fully up before injecting
echo "Waiting for WeChat process to appear..."
TIMEOUT=120
ELAPSED=0
while ! wine64 tasklist 2>/dev/null | grep -qi "WeChat.exe"; do
    if [[ $ELAPSED -ge $TIMEOUT ]]; then
        echo "ERROR: WeChat did not start within ${TIMEOUT}s"
        exit 1
    fi
    sleep 2
    ELAPSED=$((ELAPSED + 2))
done
echo "WeChat detected, waiting extra 3s for full init..."
sleep 3

echo "Starting WeChatFerry Node.js bridge on ${WCF_HOST:-127.0.0.1}:${WCF_PORT:-10086}..."
exec node /app/app/index.js
