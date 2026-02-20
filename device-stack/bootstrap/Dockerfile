FROM debian:bookworm-slim

# Install wireguard-tools (for wg genkey/pubkey), curl, jq, ca-certificates via apt.
# wireguard-tools: generates WireGuard key pair (wg genkey / wg pubkey)
# curl + jq: calls iot-bridge-api and parses the JSON response
RUN apt-get update && apt-get install -y --no-install-recommends \
    curl \
    jq \
    ca-certificates \
    wireguard-tools \
    && rm -rf /var/lib/apt/lists/*

# Copy the step CLI binary from the official image instead of downloading from GitHub.
# The step binary shipped in smallstep/step-cli is statically compiled and works
# on both Alpine (musl) and Debian (glibc) hosts.
COPY --from=smallstep/step-cli:latest /usr/local/bin/step /usr/local/bin/step

COPY bootstrap/enroll.sh /usr/local/bin/enroll.sh
RUN chmod +x /usr/local/bin/enroll.sh

VOLUME ["/certs"]
ENTRYPOINT ["/usr/local/bin/enroll.sh"]
