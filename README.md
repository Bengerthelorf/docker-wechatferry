# docker-wechatferry

Run [WeChatFerry](https://github.com/KeJunMao/WeChatFerry) (WeChat PC 3.9.12.17) inside Docker via Wine, with a Node.js HTTP bridge.

> **Platform:** `linux/amd64` only (Wine + WeChat Windows binary)

---

## Architecture

```
┌─────────────────────────────────────────────────────────┐
│  Docker container (linux/amd64)                          │
│                                                          │
│  Xvfb :1 ──► x11vnc ──► noVNC (6080)   ← QR scan here  │
│                │                                         │
│                ▼                                         │
│         WeChat.exe (Wine)                                │
│                │                                         │
│         sdk.dll (injector)                               │
│                │                                         │
│         spy.dll (injected) ──► NNG RPC                   │
│                                    │                     │
│  Node.js bridge ◄──────────────────┘                     │
│  HTTP API → 127.0.0.1:10086                             │
└─────────────────────────────────────────────────────────┘
```

---

## Quick Start

### 1. Build the image

```bash
docker build -t docker-wechatferry .
```

> **Note:** The `Dockerfile` pulls `sdk.dll` / `spy.dll` from the latest [GitHub Release](https://github.com/Bengerthelorf/docker-wechatferry/releases). You must push a tagged release first (see CI section below).

Pin a specific release:
```bash
docker build --build-arg SDK_RELEASE_TAG=v1.0.0 -t docker-wechatferry .
```

### 2. Run

```bash
docker run -d \
  --name wcf \
  -p 127.0.0.1:10086:10086 \   # WCF API — local only
  -p 127.0.0.1:6080:6080 \     # noVNC web UI — for QR scan login
  -e VNC_PASSWORD=changeme \
  docker-wechatferry
```

### 3. Log in to WeChat

Open your browser: `http://localhost:6080/vnc.html`

Scan the WeChat QR code with your phone to log in.

### 4. Use the API

```bash
# Health check
curl http://localhost:10086/health

# List contacts
curl http://localhost:10086/contacts

# Send a message
curl -X POST http://localhost:10086/send \
  -H 'Content-Type: application/json' \
  -d '{"to": "wxid_xxx", "text": "Hello from WCF!"}'
```

---

## CI — Compiling sdk.dll / spy.dll

The GitHub Actions workflow (`.github/workflows/build-sdk.yml`) compiles the C++ DLLs on `windows-latest` and attaches them to a GitHub Release.

### Trigger a build + release

```bash
git tag v1.0.0
git push origin v1.0.0
```

The workflow will:
1. Clone [KeJunMao/WeChatFerry](https://github.com/KeJunMao/WeChatFerry)
2. Install vcpkg + `nng` + `magic-enum` (x64-windows-static)
3. Generate protobuf files (nanopb)
4. Build `spy.dll` then `sdk.dll` with MSBuild (Release|x64)
5. Compute SHA256 checksums
6. Upload to GitHub Release as `sdk.dll`, `spy.dll`, `checksums.sha256`

### Verify checksums

```bash
sha256sum -c checksums.sha256
```

---

## Security Notes

| Risk | Mitigation |
|------|-----------|
| WCF API exposed externally | `WCF_HOST` defaults to `127.0.0.1`. Never publish port 10086 without auth. |
| VNC exposed externally | Set `VNC_PASSWORD` env var. Use SSH tunnel in production. |
| WeChat credentials | Stored in WINEPREFIX. Mount a named volume to persist sessions. |
| DLL integrity | All DLLs are SHA256-verified at build and runtime. |

### Persist WeChat login session

```bash
docker run -d \
  -v wcf-wineprefix:/root/.wine-wechat \
  -p 127.0.0.1:10086:10086 \
  -p 127.0.0.1:6080:6080 \
  docker-wechatferry
```

---

## Build Requirements (local Windows compile)

If you want to build the DLLs locally instead of via CI:

| Component | Version |
|-----------|---------|
| Visual Studio | 2019 (v142 toolset) |
| Windows SDK | 10.0 |
| vcpkg | latest (`C:\Tools\vcpkg`) |
| vcpkg packages | `nng:x64-windows-static` `magic-enum:x64-windows-static` |
| Python | 3.x + `grpcio-tools` |

```batch
cd WeChatFerry\rpc\proto
python ..\tool\protoc --nanopb_out=. wcf.proto

cd ..\..
msbuild WeChatFerry.sln /p:Configuration=Release /p:Platform=x64
```

Output: `WeChatFerry\x64\Release\sdk.dll` and `spy.dll`

---

## Components

| File | Purpose |
|------|---------|
| `Dockerfile` | Container image definition |
| `supervisord.conf` | Process supervision (Xvfb, WeChat, WCF bridge) |
| `scripts/entrypoint.sh` | Container entrypoint, safety checks |
| `scripts/start-vnc.sh` | Start Xvfb + x11vnc + noVNC |
| `scripts/start-wechat.sh` | Launch WeChat under Wine |
| `scripts/start-wcf.sh` | Wait for WeChat, then start Node.js bridge |
| `app/index.js` | Node.js HTTP API wrapping `@wechatferry/core` |
| `.github/workflows/build-sdk.yml` | Windows CI for compiling DLLs |

---

## WeChat Version

| Attribute | Value |
|-----------|-------|
| Version | 3.9.12.17 |
| Source | [tom-snow/wechat-windows-versions](https://github.com/tom-snow/wechat-windows-versions/releases/tag/v3.9.12.17) |
| SHA256 | `4985f96235154fc4176e3972f14709f5f10fc0606e5589075a6da9b6dc7fccd3` |

---

## Credits

- [lich0821/WeChatFerry](https://github.com/lich0821/WeChatFerry) — original project
- [KeJunMao/WeChatFerry](https://github.com/KeJunMao/WeChatFerry) — C++ source fork used for CI builds
- [tom-snow/wechat-windows-versions](https://github.com/tom-snow/wechat-windows-versions) — WeChat installer archive
