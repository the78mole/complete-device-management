#!/bin/sh
# enroll.sh – Device PKI bootstrap entrypoint
#
# Runs once as a Docker one-shot container.  Generates device credentials,
# enrolls with the cloud iot-bridge-api, and persists the results to /certs.
#
# Environment variables (set via docker-compose.yml / .env):
#   DEVICE_ID        – unique device identifier (e.g. sim-device-001)
#   DEVICE_NAME      – human-readable device name
#   DEVICE_TYPE      – device type / model identifier
#   BRIDGE_API_URL   – base URL of the cloud iot-bridge-api
#   STEP_CA_FINGERPRINT – root CA fingerprint for TLS verification (optional)

set -eu

CERTS_DIR="${CERTS_DIR:-/certs}"
DEVICE_ID="${DEVICE_ID:-sim-device-001}"
DEVICE_NAME="${DEVICE_NAME:-Simulated Device 001}"
DEVICE_TYPE="${DEVICE_TYPE:-simulator}"
BRIDGE_API_URL="${BRIDGE_API_URL:-http://host.docker.internal:8000}"
STEP_CA_FINGERPRINT="${STEP_CA_FINGERPRINT:-}"

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
echo "[enroll] Starting enrollment for device: $DEVICE_ID"

# ── 1. Generate TLS EC P-256 key pair ─────────────────────────────────────────
echo "[enroll] Generating EC P-256 private key…"
step crypto keypair \
    --no-password --insecure \
    --kty EC --curve P-256 \
    "${TLS_CERT}.pub" "$TLS_KEY"

# ── 2. Generate PKCS#10 CSR ───────────────────────────────────────────────────
echo "[enroll] Creating CSR for CN=${DEVICE_ID}…"
step certificate create \
    --csr \
    --key "$TLS_KEY" \
    --san "$DEVICE_ID" \
    --no-password --insecure \
    "$DEVICE_ID" "$TLS_CSR"

# ── 3. Generate WireGuard key pair ────────────────────────────────────────────
echo "[enroll] Generating WireGuard key pair…"
wg genkey | tee "$WG_PRIVKEY" | wg pubkey > "$WG_PUBKEY"
chmod 600 "$WG_PRIVKEY"
WG_PUB=$(cat "$WG_PUBKEY")

# ── 4. Submit CSR to iot-bridge-api ───────────────────────────────────────────
echo "[enroll] Submitting CSR to ${BRIDGE_API_URL}/devices/${DEVICE_ID}/enroll…"

CSR_PEM=$(cat "$TLS_CSR")
PAYLOAD=$(jq -n \
    --arg csr "$CSR_PEM" \
    --arg name "$DEVICE_NAME" \
    --arg type "$DEVICE_TYPE" \
    --arg wgpub "$WG_PUB" \
    '{csr: $csr, device_name: $name, device_type: $type, wg_public_key: $wgpub}')

RESPONSE=$(curl -sf \
    --retry 10 --retry-delay 5 --retry-connrefused \
    -X POST \
    "${BRIDGE_API_URL}/devices/${DEVICE_ID}/enroll" \
    -H "Content-Type: application/json" \
    -d "$PAYLOAD")

if [ -z "$RESPONSE" ]; then
    echo "[enroll] ERROR: Empty response from iot-bridge-api" >&2
    exit 1
fi

# ── 5. Save certificate, CA chain, and WireGuard config ───────────────────────
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

# ── 6. Mark enrollment complete ───────────────────────────────────────────────
echo "$WG_IP" > "$ENROLLED_FLAG"
echo "[enroll] Device '${DEVICE_ID}' enrolled successfully."
