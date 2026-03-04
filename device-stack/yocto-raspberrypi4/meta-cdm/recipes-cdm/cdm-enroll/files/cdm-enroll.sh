#!/bin/bash
# /usr/bin/cdm-enroll.sh
#
# CDM device enrollment script for Raspberry Pi 4 (Yocto image).
# Runs once on first boot via cdm-enroll.service.
#
# Configuration is read from:
#   1. /etc/cdm/enroll.env (baked into the image)
#   2. Kernel command line (cdm.KEY=VALUE) — allows per-device config at flash time
#      e.g. append to /boot/cmdline.txt:
#        cdm.device_id=rpi4-001 cdm.tenant_id=tenant1 cdm.bridge_api_url=https://...
#
# Certificates are written to /var/lib/cdm/certs/.
# A flag file /var/lib/cdm/.enrolled is created on success; the systemd
# ConditionPathExists prevents re-running on subsequent boots.

set -euo pipefail

CERTS_DIR="/var/lib/cdm/certs"
ENROLL_FLAG="/var/lib/cdm/.enrolled"
ENV_FILE="/etc/cdm/enroll.env"

log() { echo "[cdm-enroll] $*"; }
die() { echo "[cdm-enroll] ERROR: $*" >&2; exit 1; }

# ── Load static config ────────────────────────────────────────────────────────
[ -f "$ENV_FILE" ] && . "$ENV_FILE"

# ── Override with kernel cmdline (cdm.KEY=VALUE) ──────────────────────────────
for param in $(cat /proc/cmdline); do
    case "$param" in
        cdm.device_id=*)          DEVICE_ID="${param#cdm.device_id=}" ;;
        cdm.device_type=*)        DEVICE_TYPE="${param#cdm.device_type=}" ;;
        cdm.tenant_id=*)          TENANT_ID="${param#cdm.tenant_id=}" ;;
        cdm.bridge_api_url=*)     BRIDGE_API_URL="${param#cdm.bridge_api_url=}" ;;
        cdm.step_ca_fingerprint=*)STEP_CA_FINGERPRINT="${param#cdm.step_ca_fingerprint=}" ;;
    esac
done

# ── Validate required variables ───────────────────────────────────────────────
: "${DEVICE_ID:?DEVICE_ID not set – set it in /etc/cdm/enroll.env or via cmdline}"
: "${TENANT_ID:?TENANT_ID not set}"
: "${BRIDGE_API_URL:?BRIDGE_API_URL not set}"

log "Starting enrollment for device '$DEVICE_ID' (tenant: $TENANT_ID)"

# ── Idempotency check ─────────────────────────────────────────────────────────
if [ -f "$ENROLL_FLAG" ]; then
    log "Already enrolled (remove $ENROLL_FLAG to re-enroll). Skipping."
    exit 0
fi

mkdir -p "$CERTS_DIR"

KEY="$CERTS_DIR/device-key.pem"
CSR="$CERTS_DIR/device.csr"
CERT="$CERTS_DIR/device.pem"
CA_CHAIN="$CERTS_DIR/ca-chain.pem"

# ── Generate EC P-256 key pair ────────────────────────────────────────────────
log "Generating EC P-256 key pair ..."
openssl ecparam -name prime256v1 -genkey -noout -out "$KEY"
chmod 600 "$KEY"

# ── Generate PKCS#10 CSR ──────────────────────────────────────────────────────
log "Generating CSR (CN=$DEVICE_ID) ..."
openssl req -new \
    -key "$KEY" \
    -subj "/CN=${DEVICE_ID}/O=${TENANT_ID}" \
    -out "$CSR"

# ── POST CSR to IoT Bridge API ────────────────────────────────────────────────
log "Sending CSR to $BRIDGE_API_URL/v1/enroll ..."

CA_CURL_OPTS=""
if [ -n "${STEP_CA_FINGERPRINT:-}" ]; then
    # Fetch the CA certificate to allow curl to verify the TLS connection
    TEMP_CA=$(mktemp)
    curl -fsSL \
        --pinnedpubkey "sha256//${STEP_CA_FINGERPRINT}" \
        "${BRIDGE_API_URL%/api}/pki/roots" \
        -o "$TEMP_CA" 2>/dev/null || true
    [ -s "$TEMP_CA" ] && CA_CURL_OPTS="--cacert $TEMP_CA"
fi

RESPONSE=$(curl -fsSL $CA_CURL_OPTS \
    -X POST "${BRIDGE_API_URL%/}/v1/enroll" \
    -H "Content-Type: application/json" \
    -d "{
        \"device_id\":   \"${DEVICE_ID}\",
        \"tenant_id\":   \"${TENANT_ID}\",
        \"device_type\": \"${DEVICE_TYPE:-rpi4}\",
        \"csr\":         \"$(awk 'NF{printf "%s\\n", $0}' "$CSR")\"
    }")

# Parse fields from JSON response (busybox-friendly, no jq)
extract_field() { echo "$RESPONSE" | grep -o "\"$1\":\"[^\"]*\"" | cut -d'"' -f4; }

CERT_PEM=$(echo "$RESPONSE" | python3 -c \
    "import sys,json; d=json.load(sys.stdin); print(d.get('certificate',''))" 2>/dev/null || true)
CA_PEM=$(echo "$RESPONSE" | python3 -c \
    "import sys,json; d=json.load(sys.stdin); print(d.get('ca_chain',''))" 2>/dev/null || true)

[ -n "$CERT_PEM" ] || die "No certificate in API response. Response: $RESPONSE"

printf '%s\n' "$CERT_PEM"  > "$CERT"
printf '%s\n' "$CA_PEM"    > "$CA_CHAIN"
rm -f "$CSR" "${TEMP_CA:-}"

log "Certificate written to $CERT"

# ── Touch enrolled flag ───────────────────────────────────────────────────────
touch "$ENROLL_FLAG"
log "Enrollment complete."

# ── Quick mTLS connectivity test ──────────────────────────────────────────────
TB_HOST="${THINGSBOARD_HOST:-}"
TB_PORT="${THINGSBOARD_MQTT_PORT:-8883}"

if [ -n "$TB_HOST" ]; then
    log "Testing mTLS MQTT connectivity to $TB_HOST:$TB_PORT ..."
    mosquitto_pub \
        --cafile "$CA_CHAIN" \
        --cert   "$CERT" \
        --key    "$KEY" \
        -h "$TB_HOST" -p "$TB_PORT" \
        --tls-version tlsv1.2 \
        -t "v1/devices/me/telemetry" \
        -m "{\"enrolled\":true,\"platform\":\"yocto-rpi4\"}" \
        -q 0 \
        && log "mTLS MQTT publish: OK" \
        || log "WARNING: mTLS MQTT publish failed (check THINGSBOARD_HOST)."
fi
