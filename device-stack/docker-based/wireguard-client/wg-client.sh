#!/bin/sh
# wg-client.sh – WireGuard VPN client entrypoint
# Waits for the bootstrap container to write /certs/wg0.conf,
# then brings up the tunnel using wg-quick.
set -eu

echo "[wg-client] Waiting for WireGuard config at /certs/wg0.conf..."
while [ ! -f /certs/wg0.conf ]; do sleep 2; done

echo "[wg-client] Config found – copying to /etc/wireguard/wg0.conf"
mkdir -p /etc/wireguard
cp /certs/wg0.conf /etc/wireguard/wg0.conf
chmod 600 /etc/wireguard/wg0.conf

echo "[wg-client] Bringing up WireGuard tunnel..."
wg-quick up wg0

echo "[wg-client] Tunnel up. Monitoring interface..."
while true; do
    sleep 30
    if ! wg show wg0 > /dev/null 2>&1; then
        echo "[wg-client] Interface lost – attempting wg-quick up again..."
        wg-quick up wg0 2>/dev/null || echo "[wg-client] Re-up failed, will retry in 30s"
    fi
done
