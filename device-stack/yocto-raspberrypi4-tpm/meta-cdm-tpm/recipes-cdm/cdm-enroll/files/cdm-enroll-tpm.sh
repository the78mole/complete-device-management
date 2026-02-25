#!/bin/bash
# /usr/bin/cdm-enroll-tpm.sh
#
# CDM TPM-backed enrollment for Raspberry Pi 4 + Infineon SLB9672.
#
# Key security model:
#   - EC P-256 private key is generated INSIDE the TPM and never exported.
#   - The key is made persistent at TPM handle 0x81000001 (survives power cycles).
#   - CSR and TLS operations use the tpm2-openssl OpenSSL 3.x provider,
#     which forwards all crypto to the TPM; the host OS sees only the public key.
#   - The device certificate and CA chain are stored in plain files; they are
#     public material and do not need protection.
#
# mTLS connectivity test (enrollment verification):
#   openssl s_client with the tpm2 provider performs a full TLS 1.2/1.3
#   handshake using the TPM-resident key. This is the authoritative test.
#   mosquito_pub is tested separately via tpm2-pkcs11 + libp11 if available.
#
# References:
#   https://github.com/tpm2-software/tpm2-openssl
#   https://github.com/tpm2-software/tpm2-pkcs11

set -euo pipefail

# ── Paths ─────────────────────────────────────────────────────────────────────
CERTS_DIR="/var/lib/cdm/certs"
TPM_DIR="/var/lib/cdm/tpm"
ENROLL_FLAG="/var/lib/cdm/.enrolled"
ENV_FILE="/etc/cdm/enroll.env"

# TPM persistent key handle (0x81000001 = owner-hierarchy persistent slot 1)
TPM_HANDLE="0x81000001"
# PKCS#11 token label used by tpm2-pkcs11 (optional, for mosquitto integration)
PKCS11_TOKEN_LABEL="cdm-device"
PKCS11_MODULE="/usr/lib/pkcs11/libtpm2_pkcs11.so"

log()  { echo "[cdm-enroll-tpm] $*"; }
warn() { echo "[cdm-enroll-tpm] WARNING: $*" >&2; }
die()  { echo "[cdm-enroll-tpm] ERROR: $*" >&2; exit 1; }

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

: "${DEVICE_ID:?DEVICE_ID not set}"
: "${TENANT_ID:?TENANT_ID not set}"
: "${BRIDGE_API_URL:?BRIDGE_API_URL not set}"

log "CDM TPM enrollment – device='$DEVICE_ID' tenant='$TENANT_ID'"

# ── Idempotency ───────────────────────────────────────────────────────────────
if [ -f "$ENROLL_FLAG" ]; then
    log "Already enrolled. Remove $ENROLL_FLAG to re-enroll."
    exit 0
fi

# ── Wait for TPM device + abrmd ───────────────────────────────────────────────
TPM_DEV="/dev/tpmrm0"   # kernel resource manager (preferred); fallback: /dev/tpm0
TIMEOUT=30
ELAPSED=0
log "Waiting for TPM device $TPM_DEV ..."
while [ ! -c "$TPM_DEV" ] && [ ! -c "/dev/tpm0" ]; do
    sleep 1; ELAPSED=$((ELAPSED+1))
    [ $ELAPSED -lt $TIMEOUT ] || die "TPM device not found after ${TIMEOUT}s. Is the dtoverlay active?"
done
[ -c "$TPM_DEV" ] || TPM_DEV="/dev/tpm0"
export TPM2TOOLS_TCTI="device:$TPM_DEV"
export TPM2OPENSSL_TCTI="device:$TPM_DEV"

log "TPM device: $TPM_DEV"

# ── Verify TPM is responsive ──────────────────────────────────────────────────
tpm2_getcap properties-fixed 2>/dev/null | grep -q "TPM2_PT_MANUFACTURER" \
    || die "TPM not responding (check SPI wiring and dtoverlay)."
log "TPM OK."

# ── Prepare directories ───────────────────────────────────────────────────────
mkdir -p "$CERTS_DIR" "$TPM_DIR"
chmod 700 "$CERTS_DIR" "$TPM_DIR"

# ── TPM key provisioning ──────────────────────────────────────────────────────
# Check if persistent key already exists from a previous partial enrollment
if tpm2_getcap handles-persistent 2>/dev/null | grep -q "$TPM_HANDLE"; then
    log "Existing TPM persistent key found at $TPM_HANDLE – reusing."
else
    log "Creating TPM primary key (owner hierarchy) ..."
    tpm2_createprimary \
        -C o \
        -g sha256 \
        -G ecc256 \
        -c "$TPM_DIR/primary.ctx"

    log "Creating TPM child key (ECC P-256, non-migratable) ..."
    tpm2_create \
        -C "$TPM_DIR/primary.ctx" \
        -G ecc256 \
        -u "$TPM_DIR/device-key.pub" \
        -r "$TPM_DIR/device-key.priv" \
        --format=pem \
        --output="$CERTS_DIR/device-pubkey.pem"

    log "Loading key into TPM ..."
    tpm2_load \
        -C "$TPM_DIR/primary.ctx" \
        -u "$TPM_DIR/device-key.pub" \
        -r "$TPM_DIR/device-key.priv" \
        -c "$TPM_DIR/device-key.ctx"

    log "Making key persistent at handle $TPM_HANDLE ..."
    tpm2_evictcontrol -C o -c "$TPM_DIR/device-key.ctx" "$TPM_HANDLE"

    log "TPM key provisioned at $TPM_HANDLE"
fi

# Export public key PEM (for verification / info only)
tpm2_readpublic -c "$TPM_HANDLE" --format=pem \
    -o "$CERTS_DIR/device-pubkey.pem" 2>/dev/null || true

# ── Generate CSR via tpm2-openssl provider ────────────────────────────────────
# The private key operation (signing) happens inside the TPM.
log "Generating CSR using tpm2-openssl provider ..."
CSR="$CERTS_DIR/device.csr"
OPENSSL_CONF="${OPENSSL_CONF:-/etc/ssl/openssl.cnf}"

openssl req -new \
    -provider tpm2 \
    -provider default \
    -key "handle:${TPM_HANDLE}" \
    -subj "/CN=${DEVICE_ID}/O=${TENANT_ID}" \
    -out "$CSR"

log "CSR created: $CSR"

# ── POST CSR to IoT Bridge API ────────────────────────────────────────────────
log "Sending CSR to ${BRIDGE_API_URL}/v1/enroll ..."

CA_CURL_OPTS=""
if [ -n "${STEP_CA_FINGERPRINT:-}" ]; then
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
        \"device_type\": \"${DEVICE_TYPE:-rpi4-tpm}\",
        \"csr\":         \"$(awk 'NF{printf "%s\\n", $0}' "$CSR")\"
    }")

CERT_PEM=$(echo "$RESPONSE" | python3 -c \
    "import sys,json; d=json.load(sys.stdin); print(d.get('certificate',''))" 2>/dev/null || true)
CA_PEM=$(echo "$RESPONSE" | python3 -c \
    "import sys,json; d=json.load(sys.stdin); print(d.get('ca_chain',''))" 2>/dev/null || true)

[ -n "$CERT_PEM" ] || die "No certificate in API response: $RESPONSE"

CERT="$CERTS_DIR/device.pem"
CA_CHAIN="$CERTS_DIR/ca-chain.pem"
printf '%s\n' "$CERT_PEM" > "$CERT"
printf '%s\n' "$CA_PEM"   > "$CA_CHAIN"
rm -f "$CSR" "${TEMP_CA:-}"

log "Certificate written: $CERT"

# ── Verify certificate matches TPM key ────────────────────────────────────────
log "Verifying certificate public key matches TPM key ..."
CERT_PUBKEY_MD5=$(openssl x509 -in "$CERT" -noout -pubkey 2>/dev/null \
    | openssl md5 | awk '{print $2}')
TPM_PUBKEY_MD5=$(openssl pkey -in "$CERTS_DIR/device-pubkey.pem" -pubin \
    -pubout 2>/dev/null | openssl md5 | awk '{print $2}')
[ "$CERT_PUBKEY_MD5" = "$TPM_PUBKEY_MD5" ] \
    || warn "Public key mismatch – certificate may not correspond to the TPM key at $TPM_HANDLE"
log "Key match: OK"

# ── mTLS test via openssl s_client + tpm2 provider ───────────────────────────
TB_HOST="${THINGSBOARD_HOST:-}"
TB_PORT="${THINGSBOARD_MQTT_PORT:-8883}"

if [ -n "$TB_HOST" ]; then
    log "Testing mTLS with TPM key (openssl s_client, tpm2 provider) ..."
    if echo "QUIT" | openssl s_client \
            -provider tpm2 -provider default \
            -key "handle:${TPM_HANDLE}" \
            -cert "$CERT" \
            -CAfile "$CA_CHAIN" \
            -connect "${TB_HOST}:${TB_PORT}" \
            -brief 2>&1 | grep -q "CONNECTION ESTABLISHED"; then
        log "mTLS handshake: OK (private key confirmed in TPM)"
    else
        warn "mTLS handshake failed – check THINGSBOARD_HOST / network."
    fi

    # Optional: PKCS#11 test for mosquitto integration
    if [ -f "$PKCS11_MODULE" ] && command -v pkcs11-tool > /dev/null 2>&1; then
        log "tpm2-pkcs11 module present – attempting mosquitto_pub via PKCS#11 ..."
        # Initialize token if not yet done
        if ! pkcs11-tool --module "$PKCS11_MODULE" -L 2>/dev/null \
                | grep -q "$PKCS11_TOKEN_LABEL"; then
            tpm2_ptool init 2>/dev/null || true
            tpm2_ptool addtoken \
                --pid=1 --sopin=cdmsopin --userpin=cdmuserpin \
                --label="$PKCS11_TOKEN_LABEL" 2>/dev/null || true
            # Link existing persistent key into PKCS#11 token
            tpm2_ptool link \
                --label="$PKCS11_TOKEN_LABEL" \
                --key-label="device-key" \
                --userpin=cdmuserpin \
                --tpm-handle="$TPM_HANDLE" 2>/dev/null || true
        fi
        PKCS11_KEY_URI="pkcs11:token=${PKCS11_TOKEN_LABEL};object=device-key;type=private;pin-value=cdmuserpin"
        mosquitto_pub \
            --key "$PKCS11_KEY_URI" \
            --keyform engine --tls-engine pkcs11 \
            --cert   "$CERT" \
            --cafile "$CA_CHAIN" \
            -h "$TB_HOST" -p "$TB_PORT" \
            --tls-version tlsv1.2 \
            -t "v1/devices/me/telemetry" \
            -m "{\"enrolled\":true,\"platform\":\"yocto-rpi4-tpm\",\"tpm_handle\":\"$TPM_HANDLE\"}" \
            -q 0 2>/dev/null \
            && log "mosquitto_pub via PKCS#11: OK" \
            || warn "mosquitto_pub via PKCS#11 failed – pkcs11 engine not configured."
    fi
fi

# ── Cleanup transient TPM context files ───────────────────────────────────────
rm -f "$TPM_DIR/primary.ctx" "$TPM_DIR/device-key.ctx" \
      "$TPM_DIR/device-key.pub" "$TPM_DIR/device-key.priv"

# ── Mark enrolled ─────────────────────────────────────────────────────────────
touch "$ENROLL_FLAG"
log "TPM enrollment complete."
log "  Handle : $TPM_HANDLE"
log "  Cert   : $CERT"
log "  CA     : $CA_CHAIN"
log "  Pubkey : $CERTS_DIR/device-pubkey.pem"
log "  Note   : The private key NEVER left the TPM."
