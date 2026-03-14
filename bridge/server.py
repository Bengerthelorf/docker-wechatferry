#!/usr/bin/env python3
"""
WeChatFerry HTTP Bridge

Connects to spy.dll's NNG PAIR1 sockets and exposes a simple HTTP API.
- CMD socket: tcp://127.0.0.1:{port}   (request/response)
- MSG socket: tcp://127.0.0.1:{port+1} (push messages from WeChat)
"""

import json
import logging
import os
import signal
import sys
import threading
import time
from collections import deque

import pynng
from flask import Flask, Response, jsonify, request
from google.protobuf.json_format import MessageToDict

# Generate protobuf if not done yet
try:
    import wcf_pb2
except ImportError:
    print("[bridge] Generating protobuf bindings...")
    import subprocess
    subprocess.run([
        sys.executable, "-m", "grpc_tools.protoc",
        "-I.", "--python_out=.",
        "wcf.proto"
    ], cwd=os.path.dirname(os.path.abspath(__file__)), check=True)
    import wcf_pb2

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(message)s",
)
log = logging.getLogger("wcf-bridge")

# ── Configuration ───────────────────────────────────────────────────────────
NNG_PORT = int(os.environ.get("NNG_PORT", "10087"))
HTTP_HOST = os.environ.get("WCF_HOST", "127.0.0.1")
HTTP_PORT = int(os.environ.get("WCF_PORT", "10086"))
NNG_CMD_URL = f"tcp://127.0.0.1:{NNG_PORT}"
NNG_MSG_URL = f"tcp://127.0.0.1:{NNG_PORT + 1}"
NNG_TIMEOUT_MS = 5000

# ── NNG Client ──────────────────────────────────────────────────────────────

cmd_lock = threading.Lock()
cmd_sock = None
msg_sock = None
msg_queue = deque(maxlen=10000)
is_receiving = False


def connect_cmd():
    """Connect to spy.dll's CMD NNG socket."""
    global cmd_sock
    cmd_sock = pynng.Pair1()
    cmd_sock.send_timeout = NNG_TIMEOUT_MS
    cmd_sock.recv_timeout = NNG_TIMEOUT_MS
    cmd_sock.dial(NNG_CMD_URL, block=True)
    log.info(f"Connected to CMD socket: {NNG_CMD_URL}")


def send_cmd(req: wcf_pb2.Request) -> wcf_pb2.Response:
    """Send a protobuf Request and receive a Response."""
    with cmd_lock:
        data = req.SerializeToString()
        cmd_sock.send(data)
        raw = cmd_sock.recv()
        rsp = wcf_pb2.Response()
        if raw:
            rsp.ParseFromString(raw)
        return rsp


def msg_listener():
    """Background thread: receive pushed messages from spy.dll."""
    global msg_sock, is_receiving
    msg_sock = pynng.Pair1()
    msg_sock.recv_timeout = 2000
    msg_sock.dial(NNG_MSG_URL, block=True)
    log.info(f"Connected to MSG socket: {NNG_MSG_URL}")

    is_receiving = True
    while is_receiving:
        try:
            raw = msg_sock.recv()
            rsp = wcf_pb2.Response()
            rsp.ParseFromString(raw)
            if rsp.HasField("wxmsg"):
                msg = MessageToDict(rsp.wxmsg, preserving_proto_field_name=True)
                msg_queue.append(msg)
                log.debug(f"Received msg from {msg.get('sender', '?')}: "
                          f"{msg.get('content', '')[:50]}")
        except pynng.Timeout:
            continue
        except pynng.Closed:
            log.warning("MSG socket closed")
            break
        except Exception as e:
            log.error(f"MSG listener error: {e}")
            time.sleep(1)


# ── Flask App ───────────────────────────────────────────────────────────────

app = Flask(__name__)


@app.route("/health")
def health():
    return jsonify({"status": "ok", "ts": int(time.time() * 1000)})


@app.route("/is_login")
def is_login():
    req = wcf_pb2.Request()
    req.func = wcf_pb2.FUNC_IS_LOGIN
    req.empty.CopyFrom(wcf_pb2.Empty())
    rsp = send_cmd(req)
    return jsonify({"is_login": bool(rsp.status)})


@app.route("/self")
def get_self():
    req = wcf_pb2.Request()
    req.func = wcf_pb2.FUNC_GET_SELF_WXID
    req.empty.CopyFrom(wcf_pb2.Empty())
    rsp = send_cmd(req)
    return jsonify({"wxid": rsp.str})


@app.route("/userinfo")
def get_user_info():
    req = wcf_pb2.Request()
    req.func = wcf_pb2.FUNC_GET_USER_INFO
    req.empty.CopyFrom(wcf_pb2.Empty())
    rsp = send_cmd(req)
    return jsonify(MessageToDict(rsp.ui, preserving_proto_field_name=True))


@app.route("/contacts")
def get_contacts():
    req = wcf_pb2.Request()
    req.func = wcf_pb2.FUNC_GET_CONTACTS
    req.empty.CopyFrom(wcf_pb2.Empty())
    rsp = send_cmd(req)
    contacts = MessageToDict(rsp.contacts, preserving_proto_field_name=True)
    return jsonify(contacts.get("contacts", []))


@app.route("/msg_types")
def get_msg_types():
    req = wcf_pb2.Request()
    req.func = wcf_pb2.FUNC_GET_MSG_TYPES
    req.empty.CopyFrom(wcf_pb2.Empty())
    rsp = send_cmd(req)
    return jsonify(MessageToDict(rsp.types, preserving_proto_field_name=True))


@app.route("/msgs")
def get_msgs():
    """Return buffered messages (received via MSG socket)."""
    msgs = list(msg_queue)
    return jsonify(msgs)


@app.route("/msgs/pop", methods=["POST"])
def pop_msgs():
    """Pop all buffered messages."""
    msgs = []
    while msg_queue:
        msgs.append(msg_queue.popleft())
    return jsonify(msgs)


@app.route("/send", methods=["POST"])
def send_text():
    data = request.json or {}
    to = data.get("to", "")
    text = data.get("text", "")
    aters = data.get("aters", "")
    if not to or not text:
        return jsonify({"error": "Missing 'to' or 'text'"}), 400

    req = wcf_pb2.Request()
    req.func = wcf_pb2.FUNC_SEND_TXT
    req.txt.msg = text
    req.txt.receiver = to
    req.txt.aters = aters
    rsp = send_cmd(req)
    return jsonify({"status": rsp.status})


@app.route("/send_image", methods=["POST"])
def send_image():
    data = request.json or {}
    to = data.get("to", "")
    path = data.get("path", "")
    if not to or not path:
        return jsonify({"error": "Missing 'to' or 'path'"}), 400

    req = wcf_pb2.Request()
    req.func = wcf_pb2.FUNC_SEND_IMG
    req.file.path = path
    req.file.receiver = to
    rsp = send_cmd(req)
    return jsonify({"status": rsp.status})


@app.route("/send_file", methods=["POST"])
def send_file():
    data = request.json or {}
    to = data.get("to", "")
    path = data.get("path", "")
    if not to or not path:
        return jsonify({"error": "Missing 'to' or 'path'"}), 400

    req = wcf_pb2.Request()
    req.func = wcf_pb2.FUNC_SEND_FILE
    req.file.path = path
    req.file.receiver = to
    rsp = send_cmd(req)
    return jsonify({"status": rsp.status})


@app.route("/enable_recv", methods=["POST"])
def enable_recv():
    """Enable message receiving (starts MSG socket push from spy.dll)."""
    req = wcf_pb2.Request()
    req.func = wcf_pb2.FUNC_ENABLE_RECV_TXT
    req.flag = True  # include pyq
    rsp = send_cmd(req)

    # Start msg listener thread if not already running
    global is_receiving
    if not is_receiving:
        t = threading.Thread(target=msg_listener, daemon=True)
        t.start()

    return jsonify({"status": rsp.status})


@app.route("/disable_recv", methods=["POST"])
def disable_recv():
    """Disable message receiving."""
    global is_receiving
    req = wcf_pb2.Request()
    req.func = wcf_pb2.FUNC_DISABLE_RECV_TXT
    req.empty.CopyFrom(wcf_pb2.Empty())
    rsp = send_cmd(req)
    is_receiving = False
    return jsonify({"status": rsp.status})


@app.route("/refresh_qrcode")
def refresh_qrcode():
    """Get login QR code URL."""
    req = wcf_pb2.Request()
    req.func = wcf_pb2.FUNC_REFRESH_QRCODE
    req.empty.CopyFrom(wcf_pb2.Empty())
    rsp = send_cmd(req)
    return jsonify({"url": rsp.str})


@app.route("/forward", methods=["POST"])
def forward_msg():
    data = request.json or {}
    msg_id = data.get("id", 0)
    to = data.get("to", "")
    if not msg_id or not to:
        return jsonify({"error": "Missing 'id' or 'to'"}), 400

    req = wcf_pb2.Request()
    req.func = wcf_pb2.FUNC_FORWARD_MSG
    req.fm.id = int(msg_id)
    req.fm.receiver = to
    rsp = send_cmd(req)
    return jsonify({"status": rsp.status})


@app.route("/revoke", methods=["POST"])
def revoke_msg():
    data = request.json or {}
    msg_id = data.get("id", 0)
    if not msg_id:
        return jsonify({"error": "Missing 'id'"}), 400

    req = wcf_pb2.Request()
    req.func = wcf_pb2.FUNC_REVOKE_MSG
    req.ui64 = int(msg_id)
    rsp = send_cmd(req)
    return jsonify({"status": rsp.status})


@app.route("/db/names")
def get_db_names():
    req = wcf_pb2.Request()
    req.func = wcf_pb2.FUNC_GET_DB_NAMES
    req.empty.CopyFrom(wcf_pb2.Empty())
    rsp = send_cmd(req)
    return jsonify(MessageToDict(rsp.dbs, preserving_proto_field_name=True))


@app.route("/db/tables", methods=["POST"])
def get_db_tables():
    data = request.json or {}
    db = data.get("db", "")
    if not db:
        return jsonify({"error": "Missing 'db'"}), 400

    req = wcf_pb2.Request()
    req.func = wcf_pb2.FUNC_GET_DB_TABLES
    req.str = db
    rsp = send_cmd(req)
    return jsonify(MessageToDict(rsp.tables, preserving_proto_field_name=True))


@app.route("/db/query", methods=["POST"])
def exec_db_query():
    data = request.json or {}
    db = data.get("db", "")
    sql = data.get("sql", "")
    if not db or not sql:
        return jsonify({"error": "Missing 'db' or 'sql'"}), 400

    req = wcf_pb2.Request()
    req.func = wcf_pb2.FUNC_EXEC_DB_QUERY
    req.query.db = db
    req.query.sql = sql
    rsp = send_cmd(req)
    return jsonify(MessageToDict(rsp.rows, preserving_proto_field_name=True))


@app.route("/sse")
def sse_messages():
    """Server-Sent Events endpoint for real-time message streaming."""
    def generate():
        last_idx = len(msg_queue)
        while True:
            while last_idx < len(msg_queue):
                msg = msg_queue[last_idx]
                yield f"data: {json.dumps(msg, ensure_ascii=False)}\n\n"
                last_idx += 1
            time.sleep(0.5)

    return Response(generate(), mimetype="text/event-stream")


# ── Main ────────────────────────────────────────────────────────────────────

def wait_for_nng(url, timeout=120):
    """Wait for the NNG socket to become available."""
    log.info(f"Waiting for NNG endpoint {url} (timeout={timeout}s)...")
    start = time.time()
    while time.time() - start < timeout:
        try:
            sock = pynng.Pair1()
            sock.recv_timeout = 1000
            sock.dial(url, block=True)
            # Try a simple is_login request
            req = wcf_pb2.Request()
            req.func = wcf_pb2.FUNC_IS_LOGIN
            req.empty.CopyFrom(wcf_pb2.Empty())
            sock.send(req.SerializeToString())
            sock.recv()
            sock.close()
            log.info(f"NNG endpoint {url} is ready!")
            return True
        except Exception:
            time.sleep(2)
    return False


def main():
    log.info(f"WeChatFerry HTTP Bridge starting...")
    log.info(f"NNG CMD: {NNG_CMD_URL}")
    log.info(f"NNG MSG: {NNG_MSG_URL}")
    log.info(f"HTTP: {HTTP_HOST}:{HTTP_PORT}")

    # Wait for spy.dll's NNG server to be ready
    if not wait_for_nng(NNG_CMD_URL, timeout=180):
        log.error("Timed out waiting for NNG CMD socket. Is the injector running?")
        sys.exit(1)

    # Connect CMD socket
    connect_cmd()

    # Check login status
    req = wcf_pb2.Request()
    req.func = wcf_pb2.FUNC_IS_LOGIN
    req.empty.CopyFrom(wcf_pb2.Empty())
    rsp = send_cmd(req)
    log.info(f"WeChat login status: {'logged in' if rsp.status else 'not logged in'}")

    # Auto-enable message receiving
    req2 = wcf_pb2.Request()
    req2.func = wcf_pb2.FUNC_ENABLE_RECV_TXT
    req2.flag = False  # no pyq by default
    try:
        rsp2 = send_cmd(req2)
        log.info(f"Message receiving enabled (status={rsp2.status})")
        # Start listener thread
        t = threading.Thread(target=msg_listener, daemon=True)
        t.start()
    except Exception as e:
        log.warning(f"Could not enable msg recv: {e}")

    # Start HTTP server
    app.run(host=HTTP_HOST, port=HTTP_PORT, threaded=True)


if __name__ == "__main__":
    main()
