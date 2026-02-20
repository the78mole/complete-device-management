FROM alpine:3.20

RUN apk add --no-cache \
    wireguard-tools \
    iproute2

# Entrypoint waits for /certs/wg0.conf to be present (written by bootstrap),
# then brings up the WireGuard interface using wg-quick.
RUN printf '#!/bin/sh\n\
set -eu\n\
echo "[wg-client] Waiting for WireGuard config at /certs/wg0.conf..."\n\
while [ ! -f /certs/wg0.conf ]; do sleep 2; done\n\
echo "[wg-client] Config found – copying to /etc/wireguard/wg0.conf"\n\
mkdir -p /etc/wireguard\n\
cp /certs/wg0.conf /etc/wireguard/wg0.conf\n\
chmod 600 /etc/wireguard/wg0.conf\n\
echo "[wg-client] Bringing up WireGuard tunnel..."\n\
wg-quick up wg0\n\
echo "[wg-client] Tunnel up. Monitoring interface..."\n\
while true; do\n\
    wg show wg0 2>/dev/null || echo "[wg-client] Interface lost – retrying in 10s"\n\
    sleep 30\n\
done\n' > /usr/local/bin/wg-client.sh \
    && chmod +x /usr/local/bin/wg-client.sh

VOLUME ["/certs"]
ENTRYPOINT ["/usr/local/bin/wg-client.sh"]
