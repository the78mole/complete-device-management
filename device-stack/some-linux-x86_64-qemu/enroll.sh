#!/bin/sh
# enroll.sh – CDM device enrollment for minimal Linux (QEMU x86_64)
#
# Implements the same enrollment flow as the docker-based bootstrap container
# but runs natively on a minimal Linux system (BusyBox + OpenSSL).
#
# Tools required (included in the Buildroot image):
#   openssl, curl, sed, grep, awk, tr
#
# Environment variables:
#   DEVICE_ID            – unique device identifier  (default: qemu-device-001)
#   DEVICE_NAME          – human-readable name        (default: QEMU Device 001)
#   DEVICE_TYPE          – device type string          (default: qemu-x86_64)
#   TENANT_ID            – CDM tenant ID               (default: tenant1)
#   BRIDGE_API_URL       – Tenant IoT Bridge API URL   (REQUIRED)
#   STEP_CA_FINGERPRINT  – Tenant Sub-CA fingerprint   (optional, for HTTPS verify)
#   CERTS_DIR            – certificate storage dir     (default: /persist/certs)

set -eu

CERTS_DIR="${CERTS_DIR:-/persist/certs}"
DEVICE_ID="${DEVICE_ID:-qemu-device-001}"
DEVICE_NAME="${DEVICE_NAME:-QEMU Device 001}"
DEVICE_TYPE="${DEVICE_TYPE:-qemu-x86_64}"
TENANT_ID="${TENANT_ID:-tenant1}"
BRIDGE_API_URL="${BRIDGE_API_URL:-}"
STEP_CA_FINGERPRINT="${STEP_CA_FINGERPRINT:-}"

if [ -z "$BRIDGE_API_URL" ]; then
    echo "[enroll] ERROR: BRIDGE_API_URL is not set." >&2
    exit 1
fi

KEY_FILE="$CERTS_DIR/device-key.pem"
CRT_FILE="$CERTS_DIR/device.pem"
CSR_FILE="$CERTS_DIR/device.csr"
CA_FILE="$CERTS_DIR/ca-chain.pem"
ENROLLED_FLAG="$CERTS_DIR/.enrolled"

# ── Idempotency ───────────────────────────────────────────────────────────────
if [ -f "$ENROLLED_FLAG" ]; then
    echo "[enroll] Device '$DEVICE_ID' already enrolled – skipping."
    exit 0
fi

mkdir -p "$CERTS_DIR"
echo "[enroll] Starting enrollment for device: $DEVICE_ID (tenant: $TENANT_ID)"

# ── 1. Trust Tenant Sub-CA (HTTPS only) ───────────────────────────────────────
CURL_CA_OPTS=""
if [ -n "$STEP_CA_FINGERPRINT" ]; then
    # Fetch the CA PEM from the step-ca ACME discovery endpoint and verify
    # by fingerprint before installing into the local trust store.
    STEP_CA_URL="${STEP_CA_URL:-}"
    if [ -n "$STEP_CA_URL" ]; then
        echo "[enroll] Fetching Tenant Sub-CA certificate from $STEP_CA_URL ..."
        curl -sk "${STEP_CA_URL}/1.0/root" -o /tmp/root-resp.json
        # Parse the "ca" field (PEM with \n escapes)
        grep -o '"ca":"[^"]*"' /tmp/root-resp.json \
            | sed 's/"ca":"//;s/"$//' \
            | sed 's/\\n/\n/g' > /tmp/tenant-ca.pem

        ACTUAL_FP=$(openssl x509 -in /tmp/tenant-ca.pem -noout -fingerprint -sha256 2>/dev/null \
                    | sed 's/.*=//;s/://g' | tr '[:upper:]' '[:lower:]')
        EXPECTED_FP=$(echo "$STEP_CA_FINGERPRINT" | tr '[:upper:]' '[:lower:]' | tr -d ':')

        if [ "$ACTUAL_FP" = "$EXPECTED_FP" ]; then
            echo "[enroll] Tenant Sub-CA fingerprint verified."
            cp /tmp/tenant-ca.pem "$CA_FILE"
            CURL_CA_OPTS="--cacert $CA_FILE"
        else
            echo "[enroll] WARNING: fingerprint mismatch – expected $EXPECTED_FP got $ACTUAL_FP" >&2
        fi
        rm -f /tmp/root-resp.json /tmp/tenant-ca.pem
    fi
fi

# ── 2. Generate EC P-256 key pair ─────────────────────────────────────────────
echo "[enroll] Generating EC P-256 private key..."
openssl ecparam -name prime256v1 -genkey -noout -out "$KEY_FILE"
chmod 600 "$KEY_FILE"
echo "[enroll] Key written to $KEY_FILE"

# ── 3. Generate PKCS#10 CSR ───────────────────────────────────────────────────
echo "[enroll] Creating CSR for CN=$DEVICE_ID..."
openssl req -new \
    -key "$KEY_FILE" \
    -subj "/CN=$DEVICE_ID/O=CDM/OU=$TENANT_ID" \
    -addext "subjectAltName=DNS:$DEVICE_ID" \
    -out "$CSR_FILE"
echo "[enroll] CSR written to $CSR_FILE"

# ── 4. POST CSR to IoT Bridge API ─────────────────────────────────────────────
ENROLL_URL="${BRIDGE_API_URL}/v1/enroll"
echo "[enroll] POSTing CSR to $ENROLL_URL ..."

# Inline the PEM as a JSON string (escape newlines)
CSR_JSON=$(awk '{printf "%s\\n", $0}' "$CSR_FILE")

HTTP_RESPONSE=$(curl -sf $CURL_CA_OPTS \
    -X POST "$ENROLL_URL" \
    -H "Content-Type: application/json" \
    -d "{\"device_id\":\"$DEVICE_ID\",\"device_type\":\"$DEVICE_TYPE\",\"csr\":\"$CSR_JSON\"}" \
    -w "\n__HTTP_CODE__:%{http_code}" 2>&1)

HTTP_CODE=$(echo "$HTTP_RESPONSE" | grep "__HTTP_CODE__:" | sed 's/.*__HTTP_CODE__://')
BODY=$(echo "$HTTP_RESPONSE" | grep -v "__HTTP_CODE__:")

if [ "$HTTP_CODE" != "200" ]; then
    echo "[enroll] ERROR: HTTP $HTTP_CODE from $ENROLL_URL" >&2
    echo "[enroll] Response: $BODY" >&2
    exit 1
fi

echo "[enroll] Enrollment API returned HTTP 200."

# ── 5. Extract and persist certificate + CA chain ────────────────────────────
# Response JSON: { "certificate": "<PEM>", "ca_chain": "<PEM>" }
parse_pem_field() {
    # Usage: parse_pem_field <json_string> <field_name>
    echo "$1" | grep -o "\"$2\":\"[^\"]*\"" \
              | sed "s/\"$2\"://;s/\"//g" \
              | sed 's/\\n/\n/g'
}

CERT_PEM=$(parse_pem_field "$BODY" "certificate")
CHAIN_PEM=$(parse_pem_field "$BODY" "ca_chain")

if [ -z "$CERT_PEM" ] || [ -z "$CHAIN_PEM" ]; then
    echo "[enroll] ERROR: could not parse certificate or ca_chain from response." >&2
    echo "[enroll] Response body: $BODY" >&2
    exit 1
fi

printf '%s\n' "$CERT_PEM"  > "$CRT_FILE"
printf '%s\n' "$CHAIN_PEM" > "$CA_FILE"
echo "[enroll] Certificate written to $CRT_FILE"
echo "[enroll] CA chain written to    $CA_FILE"

# ── 6. Mark as enrolled ───────────────────────────────────────────────────────
touch "$ENROLLED_FLAG"
echo "[enroll] Enrollment complete."
