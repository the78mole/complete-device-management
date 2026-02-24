#!/bin/sh
# setup.sh – ttyd installation and configuration reference for Yocto devices
#
# This script documents how ttyd is set up on actual edge hardware.
# In the Docker simulation, the `tsl0922/ttyd:alpine` image is used directly.
#
# Usage (on a Yocto / Debian / Alpine device):
#   chmod +x setup.sh && sudo ./setup.sh
#
# ttyd exposes a terminal over WebSocket.  The cloud terminal-proxy routes
# authenticated connections through WireGuard to this port.

set -eu

TTYD_PORT="${TTYD_PORT:-7681}"
TTYD_CREDENTIAL="${TTYD_CREDENTIAL:-}"  # set to "user:password" to require login

log() { echo "$(date '+%T') [ttyd-setup] $*"; }

# ── Install ttyd ──────────────────────────────────────────────────────────────
if command -v ttyd > /dev/null 2>&1; then
    log "ttyd already installed: $(ttyd --version 2>&1 | head -1)"
else
    log "Installing ttyd…"
    if command -v apk > /dev/null 2>&1; then
        apk add --no-cache ttyd
    elif command -v apt-get > /dev/null 2>&1; then
        apt-get update -qq && apt-get install -y --no-install-recommends ttyd
    else
        log "ERROR: unsupported package manager – please install ttyd manually"
        exit 1
    fi
fi

# ── Create systemd unit ────────────────────────────────────────────────────────
CREDENTIAL_ARG=""
if [ -n "$TTYD_CREDENTIAL" ]; then
    CREDENTIAL_ARG="--credential ${TTYD_CREDENTIAL}"
fi

UNIT_FILE="/etc/systemd/system/cdm-ttyd.service"

if [ -f "$UNIT_FILE" ]; then
    log "Systemd unit already exists at $UNIT_FILE – skipping creation."
else
    cat > "$UNIT_FILE" <<EOF
[Unit]
Description=CDM Web Terminal (ttyd)
Documentation=https://github.com/tsl0922/ttyd
After=network.target
ConditionPathExists=/dev/pts/0

[Service]
Type=simple
# ttyd binds only to the WireGuard VPN interface IP so it is NOT
# reachable from the public network – only through the VPN tunnel.
ExecStart=ttyd \
    --port ${TTYD_PORT} \
    --writable \
    --interface wg0 \
    ${CREDENTIAL_ARG} \
    bash
Restart=on-failure
RestartSec=5s
# Run as a dedicated non-root user in production
# User=ttyd
# Group=ttyd

[Install]
WantedBy=multi-user.target
EOF
    log "Systemd unit written to $UNIT_FILE"
fi

# ── Enable and start ────────────────────────────────────────────────────────
if command -v systemctl > /dev/null 2>&1; then
    systemctl daemon-reload
    systemctl enable cdm-ttyd.service
    systemctl restart cdm-ttyd.service
    log "ttyd service enabled and started (port ${TTYD_PORT})."
else
    log "systemd not available – start ttyd manually:"
    log "  ttyd --port ${TTYD_PORT} --writable --interface wg0 bash"
fi

log "Setup complete."
log "The terminal-proxy will route connections to this device at:"
log "  ws://<vpn-ip>:${TTYD_PORT}"
