#!/usr/bin/env bash
# =============================================================================
# start-bridge.sh — start WeChatFerry Python HTTP bridge
# =============================================================================
set -euo pipefail

echo "Starting WeChatFerry HTTP Bridge..."
echo "NNG_PORT: ${NNG_PORT:-10087}"
echo "WCF_PORT: ${WCF_PORT:-10086}"

cd /opt/bridge

# Generate protobuf Python bindings if not yet generated
if [[ ! -f wcf_pb2.py ]]; then
    echo "Generating protobuf bindings..."
    python3 -m grpc_tools.protoc -I. --python_out=. wcf.proto
fi

exec python3 server.py
