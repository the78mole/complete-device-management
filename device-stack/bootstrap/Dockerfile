FROM alpine:3.20

# step-cli: generates EC key pair + PKCS#10 CSR
# wireguard-tools: generates WireGuard key pair (wg genkey / wg pubkey)
# curl + jq: calls iot-bridge-api and parses the JSON response
ARG STEP_CLI_VERSION=0.26.1
RUN apk add --no-cache \
    curl \
    jq \
    wireguard-tools-wg \
    ca-certificates \
    && curl -fsSL \
    "https://github.com/smallstep/cli/releases/download/v${STEP_CLI_VERSION}/step_linux_${STEP_CLI_VERSION}_amd64.tar.gz" \
    | tar -xz -C /usr/local/bin \
         --strip-components=2 \
         "step_${STEP_CLI_VERSION}/bin/step"

COPY bootstrap/enroll.sh /usr/local/bin/enroll.sh
RUN chmod +x /usr/local/bin/enroll.sh

VOLUME ["/certs"]
ENTRYPOINT ["/usr/local/bin/enroll.sh"]
