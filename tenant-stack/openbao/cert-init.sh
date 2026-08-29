#!/bin/sh
# tenant-stack/openbao/cert-init.sh
#
# Requests a code-signing certificate from the Tenant step-ca and stores it
# in OpenBao KV-v2 so that CI/CD pipelines can retrieve it alongside Transit
# signing operations.
#
# Workflow:
#   1. Wait for step-ca to be healthy.
#   2. Bootstrap step-ca trust (download root CA cert).
#   3. Add the code-signing JWK provisioner to step-ca (idempotent).
#   4. Generate an EC P-384 key pair locally.
#   5. Request a code-signing certificate from step-ca using the code-signer provisioner.
#   6. Wait for OpenBao to be unsealed and ready.
#   7. Authenticate to OpenBao using the cert-writer AppRole credentials
#      (written by the OpenBao entrypoint to /openbao/creds/).
#   8. Store the certificate, private key, and CA chain at KV path
#      code-signing/data/cert  (readable by the code-signer policy).
#
# Required environment variables:
#   STEP_CA_URL                    – e.g. https://step-ca:9000
#   STEP_CA_FINGERPRINT            – root CA fingerprint
#   STEP_CA_CODE_SIGNER_PROVISIONER – provisioner name (default: code-signer)
#   STEP_CA_CODE_SIGNER_PASSWORD   – provisioner password
#   OPENBAO_ADDR                   – e.g. http://openbao:8200
#   OPENBAO_KV_PATH                – KV mount path (default: code-signing)
#   TENANT_ID                      – unique tenant slug
#
# Shared volume:  openbao-creds (mounted at /openbao/creds)
#   cert-writer-role-id    – written by OpenBao entrypoint
#   cert-writer-secret-id  – written by OpenBao entrypoint

set -eu

STEP_CA_URL="${STEP_CA_URL:-https://step-ca:9000}"
STEP_CA_FINGERPRINT="${STEP_CA_FINGERPRINT:-}"
PROVISIONER="${STEP_CA_CODE_SIGNER_PROVISIONER:-code-signer}"
PROVISIONER_PASSWORD="${STEP_CA_CODE_SIGNER_PASSWORD:-changeme}"
OPENBAO_ADDR="${OPENBAO_ADDR:-http://openbao:8200}"
KV_PATH="${OPENBAO_KV_PATH:-code-signing}"
TENANT_ID="${TENANT_ID:-tenant}"
CREDS_DIR="${OPENBAO_CREDS_DIR:-/openbao/creds}"
ADMIN_PROVISIONER="${STEP_CA_ADMIN_PROVISIONER:-tenant-admin@cdm.local}"
ADMIN_PASSWORD="${STEP_CA_ADMIN_PASSWORD:-changeme}"
CERT_CN="${TENANT_ID}-code-signing"
CERT_DIR="/tmp/code-signing"
KV_STORED_FLAG="/openbao/creds/.cert-stored"

log() { printf '[openbao-cert-init] %s\n' "$*"; }

# ── 1. Wait for step-ca ────────────────────────────────────────────────────
log "Waiting for step-ca at $STEP_CA_URL ..."
until step ca health --ca-url "$STEP_CA_URL" --root /home/step/certs/root_ca.crt \
  >/dev/null 2>&1; do
  log "  step-ca not ready yet, retrying in 5s ..."
  sleep 5
done
log "step-ca is healthy."

# ── 2. Bootstrap trust ─────────────────────────────────────────────────────
if [ -n "$STEP_CA_FINGERPRINT" ]; then
  step ca bootstrap \
    --ca-url "$STEP_CA_URL" \
    --fingerprint "$STEP_CA_FINGERPRINT" \
    --force
else
  # Fall back to insecure bootstrap (development only)
  step ca bootstrap \
    --ca-url "$STEP_CA_URL" \
    --fingerprint "$(step certificate fingerprint /home/step/certs/root_ca.crt 2>/dev/null || true)" \
    --force || true
fi

# ── 3. Add code-signing provisioner to step-ca (idempotent) ───────────────
log "Checking/adding code-signer provisioner to step-ca ..."
if ! step ca provisioner list --ca-url "$STEP_CA_URL" 2>/dev/null | grep -q "\"${PROVISIONER}\""; then
  printf '%s' "$PROVISIONER_PASSWORD" > /tmp/code-signer-password.txt
  step ca provisioner add "$PROVISIONER" \
    --type JWK \
    --create \
    --password-file /tmp/code-signer-password.txt \
    --admin-subject step \
    --admin-provisioner "$ADMIN_PROVISIONER" \
    --admin-password-file <(printf '%s' "$ADMIN_PASSWORD") \
    || log "WARNING: could not add provisioner (may already exist)"
  # Attach the code-signing template
  step ca provisioner update "$PROVISIONER" \
    --x509-template "/home/step/templates/code-signing.tpl" \
    --x509-max-dur 8760h \
    --admin-subject step \
    --admin-provisioner "$ADMIN_PROVISIONER" \
    --admin-password-file <(printf '%s' "$ADMIN_PASSWORD") \
    || log "WARNING: could not update provisioner template"
  rm -f /tmp/code-signer-password.txt
  log "Provisioner '$PROVISIONER' configured."
else
  log "Provisioner '$PROVISIONER' already exists."
fi

# ── 4. Generate key pair (skip if cert already stored in OpenBao) ──────────
if [ -f "$KV_STORED_FLAG" ]; then
  log "Code-signing certificate already stored in OpenBao (flag: $KV_STORED_FLAG). Exiting."
  exit 0
fi

mkdir -p "$CERT_DIR"
log "Generating ECDSA P-384 key pair for code signing ..."
step crypto keypair \
  "${CERT_DIR}/code-signing.pub" \
  "${CERT_DIR}/code-signing.key" \
  --kty EC --curve P-384 \
  --no-password --insecure

# ── 5. Request code-signing certificate from step-ca ──────────────────────
log "Requesting code-signing certificate (CN=${CERT_CN}) from step-ca ..."
printf '%s' "$PROVISIONER_PASSWORD" > /tmp/code-signer-sign-password.txt
step ca certificate "$CERT_CN" \
  "${CERT_DIR}/code-signing.crt" \
  "${CERT_DIR}/code-signing.key" \
  --ca-url "$STEP_CA_URL" \
  --provisioner "$PROVISIONER" \
  --password-file /tmp/code-signer-sign-password.txt \
  --san "${CERT_CN}" \
  --not-after 8760h \
  --force
rm -f /tmp/code-signer-sign-password.txt
log "Certificate issued."

# ── 6. Wait for OpenBao to be unsealed ─────────────────────────────────────
log "Waiting for OpenBao at $OPENBAO_ADDR to be unsealed ..."
ATTEMPTS=0
while [ "$ATTEMPTS" -lt 60 ]; do
  HTTP_STATUS=$(curl -s -o /dev/null -w '%{http_code}' "${OPENBAO_ADDR}/v1/sys/health" || echo "000")
  # 200 = initialized + unsealed + active
  if [ "$HTTP_STATUS" = "200" ]; then
    log "OpenBao is unsealed and active."
    break
  fi
  sleep 3
  ATTEMPTS=$((ATTEMPTS + 1))
done
if [ "$ATTEMPTS" -ge 60 ]; then
  log "ERROR: OpenBao did not become unsealed within the timeout."
  exit 1
fi

# ── 7. Authenticate with cert-writer AppRole ───────────────────────────────
log "Authenticating to OpenBao with cert-writer AppRole ..."
WAIT_CREDS=0
until [ -f "${CREDS_DIR}/cert-writer-role-id" ] && [ -f "${CREDS_DIR}/cert-writer-secret-id" ]; do
  WAIT_CREDS=$((WAIT_CREDS + 1))
  if [ "$WAIT_CREDS" -gt 30 ]; then
    log "ERROR: AppRole credentials not found in $CREDS_DIR after retries."
    exit 1
  fi
  log "  Waiting for AppRole credentials in $CREDS_DIR ..."
  sleep 3
done

ROLE_ID=$(cat "${CREDS_DIR}/cert-writer-role-id")
SECRET_ID=$(cat "${CREDS_DIR}/cert-writer-secret-id")

TOKEN_RESPONSE=$(curl -sf \
  --request POST \
  --data "{\"role_id\":\"${ROLE_ID}\",\"secret_id\":\"${SECRET_ID}\"}" \
  "${OPENBAO_ADDR}/v1/auth/approle/login")

VAULT_TOKEN=$(printf '%s' "$TOKEN_RESPONSE" | grep -o '"client_token":"[^"]*"' | cut -d'"' -f4)
if [ -z "$VAULT_TOKEN" ]; then
  log "ERROR: Failed to obtain AppRole token from OpenBao."
  exit 1
fi
log "AppRole authentication successful."

# ── 8. Store cert + key in OpenBao KV-v2 ──────────────────────────────────
CERT_PEM=$(cat "${CERT_DIR}/code-signing.crt")
KEY_PEM=$(cat "${CERT_DIR}/code-signing.key")
CA_PEM=$(cat "$(step path)/certs/root_ca.crt" 2>/dev/null || cat /home/step/certs/root_ca.crt)

# Escape PEM blocks for JSON (replace newlines with \n)
_to_json_str() { printf '%s' "$1" | awk '{printf "%s\\n", $0}' | sed '$ s/\\n$//'; }

PAYLOAD=$(printf '{"data":{"cert":"%s","key":"%s","ca_chain":"%s","cn":"%s","tenant_id":"%s"}}' \
  "$(_to_json_str "$CERT_PEM")" \
  "$(_to_json_str "$KEY_PEM")" \
  "$(_to_json_str "$CA_PEM")" \
  "$CERT_CN" \
  "$TENANT_ID")

HTTP_STATUS=$(curl -sf \
  -o /dev/null -w '%{http_code}' \
  --request POST \
  --header "X-Vault-Token: ${VAULT_TOKEN}" \
  --header "Content-Type: application/json" \
  --data "$PAYLOAD" \
  "${OPENBAO_ADDR}/v1/${KV_PATH}/data/cert")

if [ "$HTTP_STATUS" = "200" ] || [ "$HTTP_STATUS" = "204" ]; then
  log "Code-signing certificate stored at OpenBao KV path: ${KV_PATH}/data/cert"
  # Mark as done so the container is idempotent across restarts
  touch "$KV_STORED_FLAG"
else
  log "ERROR: Failed to store certificate in OpenBao KV (HTTP $HTTP_STATUS)."
  exit 1
fi

# ── Cleanup ────────────────────────────────────────────────────────────────
rm -f "${CERT_DIR}/code-signing.key"
log "cert-init complete. Private key removed from disk."
