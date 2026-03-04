FROM debian:bookworm-slim

RUN apt-get update && apt-get install -y --no-install-recommends \
    wireguard-tools \
    iproute2 \
    && rm -rf /var/lib/apt/lists/*

# Entrypoint waits for /certs/wg0.conf to be present (written by bootstrap),
# then brings up the WireGuard interface using wg-quick.
# NOTE: The build context for this Dockerfile is the parent `device-stack/` directory
# (as declared in docker-compose.yml: `context: .`). The COPY path below is therefore
# relative to device-stack/, not to wireguard-client/.
COPY wireguard-client/wg-client.sh /usr/local/bin/wg-client.sh
RUN chmod +x /usr/local/bin/wg-client.sh

VOLUME ["/certs"]
ENTRYPOINT ["/usr/local/bin/wg-client.sh"]
