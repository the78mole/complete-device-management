#!/bin/sh
# enroll.sh – Device PKI bootstrap entrypoint
#
# Runs once as a Docker one-shot container.  Generates device credentials,
# enrolls with the Tenant IoT Bridge API, and persists the results to /certs.
#
# Environment variables (set via docker-compose.yml / .env):
#   DEVICE_ID            – unique device identifier (e.g. sim-device-001)
#   DEVICE_NAME          – human-readable device name
#   DEVICE_TYPE          – device type / model identifier
#   TENANT_ID            – CDM Tenant ID (must match tenant-stack TENANT_ID)
#   BRIDGE_API_URL       – base URL of the Tenant IoT Bridge API
#                          (e.g. http://tenant-host:8888/api)
#   STEP_CA_FINGERPRINT  – Tenant Sub-CA fingerprint for TLS trust bootstrap.
#                          Retrieve: docker compose exec ${TENANT_ID}-step-ca step ca fingerprint
#   STEP_CA_URL          – Tenant step-ca URL for TLS trust bootstrap (optional).
#                          Only needed when BRIDGE_API_URL uses HTTPS.
#                          (e.g. https://tenant-host:8888/pki)

set -eu

CERTS_DIR="${CERTS_DIR:-/certs}"
DEVICE_ID="${DEVICE_ID:-sim-device-001}"
DEVICE_NAME="${DEVICE_NAME:-Simulated Device 001}"
DEVICE_TYPE="${DEVICE_TYPE:-simulator}"
TENANT_ID="${TENANT_ID:-tenant1}"
BRIDGE_API_URL="${BRIDGE_API_URL:-http://host.docker.internal:8888/api}"
STEP_CA_FINGERPRINT="${STEP_CA_FINGERPRINT:-}"
STEP_CA_URL="${STEP_CA_URL:-}"

# Paths inside the shared /certs volume
TLS_KEY="$CERTS_DIR/device-key.pem"
TLS_CERT="$CERTS_DIR/device.pem"
TLS_CSR="$CERTS_DIR/device.csr"
CA_CHAIN="$CERTS_DIR/ca-chain.pem"
WG_PRIVKEY="$CERTS_DIR/wg-private.key"
WG_PUBKEY="$CERTS_DIR/wg-public.key"
WG_CONFIG="$CERTS_DIR/wg0.conf"
ENROLLED_FLAG="$CERTS_DIR/.enrolled"

# ── Idempotency check ─────────────────────────────────────────────────────────
if [ -f "$ENROLLED_FLAG" ]; then
    echo "[enroll] Device '$DEVICE_ID' is already enrolled – skipping."
    exit 0
fi

mkdir -p "$CERTS_DIR"
echo "[enroll] Starting enrollment for device: $DEVICE_ID (tenant: $TENANT_ID)"

# ── 1. Bootstrap Tenant Sub-CA TLS trust (HTTPS only) ────────────────────────
# If STEP_CA_URL and STEP_CA_FINGERPRINT are both set, fetch the Tenant Sub-CA
# root certificate and install it so that subsequent curl calls to the Tenant
# Caddy (HTTPS) can verify its TLS certificate (issued by the Sub-CA via ACME).
if [ -n "$STEP_CA_FINGERPRINT" ] && [ -n "$STEP_CA_URL" ]; then
    echo "[enroll] Bootstrapping TLS trust from Tenant Sub-CA at ${STEP_CA_URL}…"
    step ca bootstrap \
        --ca-url "$STEP_CA_URL" \
        --fingerprint "$STEP_CA_FINGERPRINT" \
        --install \
        --force \
        2>&1 && echo "[enroll] Tenant Sub-CA trusted." \
            || echo "[enroll] WARNING: CA bootstrap failed – proceeding with system trust store."
elif [ -n "$STEP_CA_FINGERPRINT" ] && [ -z "$STEP_CA_URL" ]; then
    echo "[enroll] STEP_CA_FINGERPRINT set but STEP_CA_URL not set – skipping TLS bootstrap."
    echo "[enroll] (Set STEP_CA_URL if BRIDGE_API_URL uses HTTPS)"
fi

# ── 2. Generate TLS EC P-256 key pair ─────────────────────────────────────────
echo "[enroll] Generating EC P-256 private key…"
step crypto keypair \
    --no-password --insecure \
    --kty EC --curve P-256 \
    "${TLS_CERT}.pub" "$TLS_KEY"

# ── 3. Generate PKCS#10 CSR ───────────────────────────────────────────────────
echo "[enroll] Creating CSR for CN=${DEVICE_ID}…"
step certificate create \
    --csr \
    --key "$TLS_KEY" \
    --san "$DEVICE_ID" \
    --no-password --insecure \
    "$DEVICE_ID" "$TLS_CSR"

# ── 4. Generate WireGuard key pair ────────────────────────────────────────────
echo "[enroll] Generating WireGuard key pair…"
wg genkey | tee "$WG_PRIVKEY" | wg pubkey > "$WG_PUBKEY"
chmod 600 "$WG_PRIVKEY"
WG_PUB=$(cat "$WG_PUBKEY")

# ── 5. Submit CSR to Tenant IoT Bridge API ────────────────────────────────────
echo "[enroll] Submitting CSR to ${BRIDGE_API_URL}/devices/${DEVICE_ID}/enroll…"

CSR_PEM=$(cat "$TLS_CSR")
PAYLOAD=$(jq -n \
    --arg csr "$CSR_PEM" \
    --arg name "$DEVICE_NAME" \
    --arg type "$DEVICE_TYPE" \
    --arg wgpub "$WG_PUB" \
    '{csr: $csr, device_name: $name, device_type: $type, wg_public_key: $wgpub}')

# Use the installed CA trust store for HTTPS verification if bootstrapped above.
RESPONSE=$(curl -sf \
    --retry 10 --retry-delay 5 --retry-connrefused \
    -X POST \
    "${BRIDGE_API_URL}/devices/${DEVICE_ID}/enroll" \
    -H "Content-Type: application/json" \
    -d "$PAYLOAD")

if [ -z "$RESPONSE" ]; then
    echo "[enroll] ERROR: Empty response from Tenant IoT Bridge API" >&2
    exit 1
fi

# ── 6. Save certificate, CA chain, and WireGuard config ───────────────────────
echo "[enroll] Parsing enrollment response…"

echo "$RESPONSE" | jq -r '.certificate'    > "$TLS_CERT"
echo "$RESPONSE" | jq -r '.ca_chain'       > "$CA_CHAIN"
WG_IP=$(echo "$RESPONSE" | jq -r '.wireguard_ip')

# Build the final WireGuard config with the real private key
WG_PRIV=$(cat "$WG_PRIVKEY")
echo "$RESPONSE" | jq -r '.wireguard_config' \
    | sed "s|<REPLACE_WITH_DEVICE_PRIVATE_KEY>|${WG_PRIV}|g" \
    > "$WG_CONFIG"

chmod 600 "$WG_CONFIG" "$WG_PRIVKEY"

echo "[enroll] TLS certificate saved  : $TLS_CERT"
echo "[enroll] CA chain saved         : $CA_CHAIN"
echo "[enroll] WireGuard IP assigned  : $WG_IP"
echo "[enroll] WireGuard config saved : $WG_CONFIG"

# ── 7. Mark enrollment complete ───────────────────────────────────────────────
echo "$WG_IP" > "$ENROLLED_FLAG"
echo "[enroll] Device '${DEVICE_ID}' enrolled successfully (tenant: ${TENANT_ID})."
