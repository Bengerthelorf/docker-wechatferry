# syntax=docker/dockerfile:1.6
# =============================================================================
# WeChatFerry Docker Image
# Platform: linux/amd64 (runs via OrbStack Rosetta on Apple Silicon)
# WeChat PC: 3.9.12.17 (Wine)
# =============================================================================

FROM --platform=linux/amd64 ubuntu:22.04

LABEL maintainer="Bengerthelorf" \
      description="WeChatFerry: WeChat PC under Wine + NNG RPC + HTTP Bridge" \
      wechat.version="3.9.12.17"

# ── Build arguments ──────────────────────────────────────────────────────────
ARG NNG_PORT=10087
ARG WCF_PORT=10086
ARG VNC_PORT=5900
ARG NOVNC_PORT=6080

ARG WECHAT_VERSION=3.9.12.17
ARG WECHAT_URL=https://github.com/tom-snow/wechat-windows-versions/releases/download/v3.9.12.17/WeChatSetup-3.9.12.17.exe
ARG WECHAT_SHA256=4985f96235154fc4176e3972f14709f5f10fc0606e5589075a6da9b6dc7fccd3

# ── Environment ──────────────────────────────────────────────────────────────
ENV DEBIAN_FRONTEND=noninteractive \
    DISPLAY=:1 \
    WINEPREFIX=/root/.wine \
    WINEARCH=win64 \
    NNG_PORT=${NNG_PORT} \
    WCF_PORT=${WCF_PORT} \
    WCF_HOST=127.0.0.1 \
    VNC_PORT=${VNC_PORT} \
    NOVNC_PORT=${NOVNC_PORT}

# ── System packages ──────────────────────────────────────────────────────────
RUN dpkg --add-architecture i386 && \
    apt-get update && apt-get install -y --no-install-recommends \
    # Basic utilities
    ca-certificates curl wget gnupg software-properties-common \
    # X11 virtual display + VNC
    xvfb x11vnc x11-utils \
    # noVNC
    novnc websockify \
    # Python 3
    python3 python3-pip python3-venv \
    # Process management
    supervisor \
    # Build tools (for MinGW cross-compile)
    gcc-mingw-w64-x86-64 \
    # SHA256 checksums
    coreutils \
    # Wine dependencies
    cabextract \
    && rm -rf /var/lib/apt/lists/*

# ── Install Wine from WineHQ (stable) ────────────────────────────────────────
RUN mkdir -pm755 /etc/apt/keyrings && \
    curl -fsSL https://dl.winehq.org/wine-builds/winehq.key \
       | gpg --dearmor -o /etc/apt/keyrings/winehq-archive.key && \
    echo "deb [arch=amd64,i386 signed-by=/etc/apt/keyrings/winehq-archive.key] \
    https://dl.winehq.org/wine-builds/ubuntu/ jammy main" \
       > /etc/apt/sources.list.d/winehq.list && \
    apt-get update && \
    apt-get install -y --install-recommends winehq-stable || \
    apt-get install -y wine64 wine32 && \
    rm -rf /var/lib/apt/lists/*

# ── Initialize WINEPREFIX ─────────────────────────────────────────────────────
RUN Xvfb :1 -screen 0 1024x768x16 & \
    sleep 2 && \
    WINEDLLOVERRIDES="mscoree,mshtml=" wine64 wineboot --init && \
    wineserver --wait && \
    kill %1 2>/dev/null; true

# ── Download and install WeChat 3.9.12.17 ────────────────────────────────────
RUN set -e && \
    echo "Downloading WeChat ${WECHAT_VERSION}..." && \
    curl -fsSL -o /tmp/WeChatSetup.exe "${WECHAT_URL}" && \
    echo "Verifying SHA256..." && \
    echo "${WECHAT_SHA256}  /tmp/WeChatSetup.exe" | sha256sum -c - && \
    echo "SHA256 OK" && \
    Xvfb :1 -screen 0 1024x768x16 & \
    sleep 2 && \
    # WeChat NSIS installer: /S for silent
    wine64 /tmp/WeChatSetup.exe /S && \
    wineserver --wait && \
    kill %1 2>/dev/null; true && \
    rm -f /tmp/WeChatSetup.exe && \
    echo "WeChat installed." && \
    # Show where it was installed
    find "${WINEPREFIX}/drive_c" -name "WeChat.exe" -o -name "WeChatWin.dll" 2>/dev/null || true

# ── Copy pre-built WeChatFerry DLLs ──────────────────────────────────────────
COPY dlls/sdk.dll dlls/spy.dll /opt/wcf-sdk/

# Place DLLs next to WeChat.exe (try both possible install paths)
RUN for d in \
      "${WINEPREFIX}/drive_c/Program Files/Tencent/WeChat" \
      "${WINEPREFIX}/drive_c/Program Files (x86)/Tencent/WeChat"; do \
        if [ -d "$d" ]; then \
            cp /opt/wcf-sdk/sdk.dll "$d/sdk.dll"; \
            cp /opt/wcf-sdk/spy.dll "$d/spy.dll"; \
            echo "DLLs placed in $d"; \
        fi; \
    done

# ── Cross-compile injector.exe ────────────────────────────────────────────────
COPY injector/injector.c /tmp/injector.c
RUN x86_64-w64-mingw32-gcc -o /opt/wcf-sdk/injector.exe /tmp/injector.c \
    -lshlwapi -static && \
    rm /tmp/injector.c && \
    echo "injector.exe compiled."

# Copy injector to WeChat directory
RUN for d in \
      "${WINEPREFIX}/drive_c/Program Files/Tencent/WeChat" \
      "${WINEPREFIX}/drive_c/Program Files (x86)/Tencent/WeChat"; do \
        if [ -d "$d" ]; then \
            cp /opt/wcf-sdk/injector.exe "$d/injector.exe"; \
        fi; \
    done

# ── Install Python bridge dependencies ───────────────────────────────────────
COPY bridge/requirements.txt /opt/bridge/requirements.txt
RUN pip3 install --no-cache-dir -r /opt/bridge/requirements.txt

# ── Copy bridge code ──────────────────────────────────────────────────────────
COPY bridge/ /opt/bridge/

# Generate protobuf bindings at build time
RUN cd /opt/bridge && python3 -m grpc_tools.protoc -I. --python_out=. wcf.proto

# ── Copy scripts ──────────────────────────────────────────────────────────────
COPY scripts/ /opt/scripts/
RUN chmod +x /opt/scripts/*.sh

# ── Supervisor config ─────────────────────────────────────────────────────────
COPY supervisord.conf /etc/supervisor/conf.d/wcf.conf

# ── Block WeChat auto-update ──────────────────────────────────────────────────
# Prevent WeChat from phoning home for updates
RUN echo "127.0.0.1 dldir1.qq.com" >> /etc/hosts && \
    echo "127.0.0.1 dldir1v6.qq.com" >> /etc/hosts

# ── Ports ─────────────────────────────────────────────────────────────────────
EXPOSE ${WCF_PORT} ${VNC_PORT} ${NOVNC_PORT}

# ── Healthcheck ───────────────────────────────────────────────────────────────
HEALTHCHECK --interval=30s --timeout=10s --start-period=180s --retries=3 \
    CMD curl -sf http://localhost:${WCF_PORT}/health || exit 1

# ── Entrypoint ────────────────────────────────────────────────────────────────
ENTRYPOINT ["/opt/scripts/entrypoint.sh"]
CMD ["supervisord", "-n", "-c", "/etc/supervisor/conf.d/wcf.conf"]
