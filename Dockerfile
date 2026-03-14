# syntax=docker/dockerfile:1.6
# =============================================================================
# WeChatFerry Docker Image
# Platform: linux/amd64
# WeChat PC: 3.9.12.17 (Wine)
# =============================================================================

FROM --platform=linux/amd64 ubuntu:22.04

LABEL maintainer="Bengerthelorf" \
      description="WeChatFerry running under Wine on Linux/Docker" \
      wechat.version="3.9.12.17" \
      wcf.api.port="10086"

# ── Build arguments ──────────────────────────────────────────────────────────
# Override SDK_RELEASE_TAG to pin a specific GitHub Release tag
ARG SDK_RELEASE_TAG=latest
ARG WCF_PORT=10086
ARG VNC_PORT=5900
ARG NOVNC_PORT=6080

# WeChat 3.9.12.17 from tom-snow/wechat-windows-versions
ARG WECHAT_VERSION=3.9.12.17
ARG WECHAT_URL=https://github.com/tom-snow/wechat-windows-versions/releases/download/v3.9.12.17/WeChatSetup-3.9.12.17.exe
ARG WECHAT_SHA256=4985f96235154fc4176e3972f14709f5f10fc0606e5589075a6da9b6dc7fccd3

# ── Environment ──────────────────────────────────────────────────────────────
ENV DEBIAN_FRONTEND=noninteractive \
    DISPLAY=:1 \
    WINEPREFIX=/root/.wine-wechat \
    WINEARCH=win64 \
    WINE_MONO_VERSION=9.3.0 \
    WCF_PORT=${WCF_PORT} \
    VNC_PORT=${VNC_PORT} \
    NOVNC_PORT=${NOVNC_PORT} \
    # Bind WCF only to localhost — never expose externally by default
    WCF_HOST=127.0.0.1

# ── System packages ──────────────────────────────────────────────────────────
RUN apt-get update && apt-get install -y --no-install-recommends \
    # Basic utilities
    ca-certificates curl wget gnupg software-properties-common \
    # Wine deps
    wine64 wine32 winbind \
    # X11 virtual display
    xvfb x11vnc \
    # noVNC (web-based VNC)
    novnc websockify \
    # Node.js runtime
    nodejs npm \
    # Process management
    supervisor \
    # SHA256 checksums
    coreutils \
    # Wine gecko/mono fonts
    cabextract \
    && rm -rf /var/lib/apt/lists/*

# ── Install Wine from WineHQ (stable, newer than Ubuntu default) ─────────────
# Uncomment the block below if you want a newer Wine version.
# The default Ubuntu 22.04 wine64 is sufficient for WeChat 3.9.12.17.
#
# RUN dpkg --add-architecture i386 \
#     && mkdir -pm755 /etc/apt/keyrings \
#     && curl -fsSL https://dl.winehq.org/wine-builds/winehq.key \
#        | gpg --dearmor -o /etc/apt/keyrings/winehq-archive.key \
#     && curl -fsSL \
#        "https://dl.winehq.org/wine-builds/ubuntu/dists/$(. /etc/os-release; echo $VERSION_CODENAME)/winehq-$(. /etc/os-release; echo $VERSION_CODENAME).sources" \
#        -o /etc/apt/sources.list.d/winehq.sources \
#     && apt-get update \
#     && apt-get install -y --install-recommends winehq-stable \
#     && rm -rf /var/lib/apt/lists/*

# ── Install Node.js 20 LTS ───────────────────────────────────────────────────
RUN curl -fsSL https://deb.nodesource.com/setup_20.x | bash - \
    && apt-get install -y --no-install-recommends nodejs \
    && rm -rf /var/lib/apt/lists/*

# ── Initialize WINEPREFIX ─────────────────────────────────────────────────────
# Run wineboot in headless Xvfb to initialize the prefix
RUN Xvfb :1 -screen 0 1024x768x16 & \
    sleep 2 && \
    WINEDLLOVERRIDES="mscoree,mshtml=" wine64 wineboot --init && \
    wineserver --wait && \
    kill %1 2>/dev/null; true

# ── Download and install WeChat 3.9.12.17 ────────────────────────────────────
RUN set -e && \
    mkdir -p /opt/wechat && \
    echo "Downloading WeChat ${WECHAT_VERSION}..." && \
    curl -fsSL -o /tmp/WeChatSetup.exe "${WECHAT_URL}" && \
    echo "Verifying SHA256..." && \
    echo "${WECHAT_SHA256}  /tmp/WeChatSetup.exe" | sha256sum -c - && \
    echo "SHA256 OK" && \
    Xvfb :1 -screen 0 1024x768x16 & \
    sleep 2 && \
    wine64 /tmp/WeChatSetup.exe /S && \
    wineserver --wait && \
    kill %1 2>/dev/null; true && \
    rm -f /tmp/WeChatSetup.exe

# ── Download WeChatFerry SDK DLLs from GitHub Release ────────────────────────
# sdk.dll and spy.dll are placed next to WeChat's executable so the injector
# can find spy.dll when WxInitSDK() is called.
RUN set -e && \
    mkdir -p /opt/wcf-sdk && \
    echo "Fetching WeChatFerry SDK release info..." && \
    if [ "${SDK_RELEASE_TAG}" = "latest" ]; then \
        RELEASE_URL="https://api.github.com/repos/Bengerthelorf/docker-wechatferry/releases/latest"; \
    else \
        RELEASE_URL="https://api.github.com/repos/Bengerthelorf/docker-wechatferry/releases/tags/${SDK_RELEASE_TAG}"; \
    fi && \
    SDK_DL=$(curl -fsSL "$RELEASE_URL" | \
        python3 -c "import sys,json; assets=json.load(sys.stdin)['assets']; print(next(a['browser_download_url'] for a in assets if a['name']=='sdk.dll'))") && \
    SPY_DL=$(curl -fsSL "$RELEASE_URL" | \
        python3 -c "import sys,json; assets=json.load(sys.stdin)['assets']; print(next(a['browser_download_url'] for a in assets if a['name']=='spy.dll'))") && \
    CHECKSUM_DL=$(curl -fsSL "$RELEASE_URL" | \
        python3 -c "import sys,json; assets=json.load(sys.stdin)['assets']; print(next(a['browser_download_url'] for a in assets if a['name']=='checksums.sha256'))") && \
    curl -fsSL -o /opt/wcf-sdk/sdk.dll "$SDK_DL" && \
    curl -fsSL -o /opt/wcf-sdk/spy.dll "$SPY_DL" && \
    curl -fsSL -o /opt/wcf-sdk/checksums.sha256 "$CHECKSUM_DL" && \
    echo "Verifying DLL checksums..." && \
    cd /opt/wcf-sdk && sha256sum -c checksums.sha256 && \
    echo "DLL checksums OK"

# ── Copy DLLs to WeChat directory ─────────────────────────────────────────────
# WeChatFerry SDK expects spy.dll in the same directory as sdk.dll at call time.
# We symlink from the WeChat program dir to /opt/wcf-sdk.
RUN WECHAT_DIR="${WINEPREFIX}/drive_c/Program Files (x86)/Tencent/WeChat" && \
    ln -sf /opt/wcf-sdk/sdk.dll "${WECHAT_DIR}/sdk.dll" && \
    ln -sf /opt/wcf-sdk/spy.dll "${WECHAT_DIR}/spy.dll"

# ── Install @wechatferry/core (Node.js SDK) ───────────────────────────────────
WORKDIR /app
COPY package.json package-lock.json* ./
RUN npm ci --omit=dev 2>/dev/null || npm install --omit=dev

# ── Copy application code ─────────────────────────────────────────────────────
COPY app/ ./app/

# ── Copy configuration & startup scripts ─────────────────────────────────────
COPY scripts/ /opt/scripts/
RUN chmod +x /opt/scripts/*.sh

COPY supervisord.conf /etc/supervisor/conf.d/wcf.conf

# ── Ports ─────────────────────────────────────────────────────────────────────
# WCF API — IMPORTANT: bind to 127.0.0.1 only (set WCF_HOST=0.0.0.0 at your own risk)
EXPOSE ${WCF_PORT}
# VNC (raw) — only expose when debugging; use SSH tunnel in production
EXPOSE ${VNC_PORT}
# noVNC (web) — for QR code scan login
EXPOSE ${NOVNC_PORT}

# ── Healthcheck ───────────────────────────────────────────────────────────────
HEALTHCHECK --interval=30s --timeout=10s --start-period=120s --retries=3 \
    CMD curl -sf http://localhost:${WCF_PORT}/health || exit 1

# ── Entrypoint ────────────────────────────────────────────────────────────────
ENTRYPOINT ["/opt/scripts/entrypoint.sh"]
CMD ["supervisord", "-c", "/etc/supervisor/supervisord.conf"]
