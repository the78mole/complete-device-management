#!/bin/sh
# init-sub-ca.sh – Tenant Stack step-ca Sub-CA initialisation
#
# This script performs TWO tasks that must run once after the first start:
#
# Task 1 – (Optional) Request Sub-CA certificate signing from Provider Root CA
#   If STEP_CA_PROVIDER_URL and STEP_CA_PROVIDER_FINGERPRINT are set the script
#   contacts the Provider step-ca, requests a signing of the Tenant Issuing CA
#   certificate and replaces the self-signed root with the Provider-signed chain.
#   This step finalises the JOIN workflow and establishes a chain of trust from
#   Provider Root CA → Tenant Sub-CA → Device Leaf Cert.
#
#   If the Provider vars are not set the Sub-CA continues as a standalone CA
#   (useful for local dev / testing before integration with a Provider-Stack).
#
# Task 2 – Add IoT Bridge API JWK provisioner
#   Adds a dedicated JWK provisioner for the iot-bridge-api service so that
#   service can sign device leaf certificates without sharing the admin password.
#   Attaches the device-leaf certificate template to the provisioner.
#
# Usage (from the host):
#   docker compose exec ${TENANT_ID:-tenant}-step-ca /usr/local/bin/init-sub-ca.sh
#
# Prerequisites:
#   - Container running, DOCKER_STEPCA_INIT_* has already generated ca.json
#   - For Sub-CA signing: STEP_CA_PROVIDER_URL, STEP_CA_PROVIDER_FINGERPRINT,
#     STEP_CA_PROVIDER_ADMIN_PASSWORD must be set in the environment
#   - step-ca-password secret must be mounted at /run/secrets/step-ca-password

set -eu

CA_CONFIG="/home/step/config/ca.json"
CA_URL="https://localhost:9000"
ROOT_CERT="/home/step/certs/root_ca.crt"
INTERMEDIATE_CERT="/home/step/certs/intermediate_ca.crt"
CA_KEY="/home/step/secrets/intermediate_ca_key"

PROVISIONER_NAME="${STEP_CA_PROVISIONER_NAME:-iot-bridge}"
PROVISIONER_PASSWORD="${STEP_CA_PROVISIONER_PASSWORD:-changeme}"
DEVICE_TEMPLATE="/home/step/templates/device-leaf.tpl"
ADMIN_PROVISIONER="${DOCKER_STEPCA_INIT_PROVISIONER_NAME:-tenant-admin@cdm.local}"
TENANT_ID="${TENANT_ID:-tenant}"

if [ ! -f "$CA_CONFIG" ]; then
  echo "ERROR: $CA_CONFIG not found – run container first to trigger DOCKER_STEPCA_INIT."
  exit 1
fi

echo ">>> Bootstrapping trust against local CA..."
step ca bootstrap \
  --ca-url "$CA_URL" \
  --fingerprint "$(step certificate fingerprint "$ROOT_CERT")" \
  --force

# ── Task 1: Request Sub-CA signing from Provider Root CA ────────────────────
if [ -n "${STEP_CA_PROVIDER_URL:-}" ] && [ -n "${STEP_CA_PROVIDER_FINGERPRINT:-}" ]; then
  echo ""
  echo ">>> Connecting to Provider Root CA at $STEP_CA_PROVIDER_URL ..."
  echo "    (fingerprint: $STEP_CA_PROVIDER_FINGERPRINT)"

  # Bootstrap trust against the Provider CA
  step ca bootstrap \
    --ca-url "$STEP_CA_PROVIDER_URL" \
    --fingerprint "$STEP_CA_PROVIDER_FINGERPRINT" \
    --force \
    --install

  # Create a CSR from the current Tenant Intermediate key
  CSR_FILE="/tmp/tenant-sub-ca.csr"
  echo ">>> Creating CSR for Tenant Sub-CA: $TENANT_ID ..."
  step certificate create \
    "$TENANT_ID Issuing CA" \
    "$CSR_FILE" \
    /tmp/tenant-sub-ca.key \
    --kty EC \
    --curve P-256 \
    --csr \
    --no-password \
    --insecure

  # Submit the CSR to the Provider Root CA for signing
  SIGNED_CERT="/tmp/tenant-sub-ca-signed.crt"
  echo ">>> Requesting signing from Provider Root CA..."
  step ca sign \
    --ca-url "$STEP_CA_PROVIDER_URL" \
    --root "$(step path)/certs/root_ca.crt" \
    --profile intermediate-ca \
    --not-after 8760h \
    --admin-provisioner "${STEP_CA_PROVIDER_ADMIN_PROVISIONER:-cdm-admin@cdm.local}" \
    --admin-password-file <(printf '%s' "${STEP_CA_PROVIDER_ADMIN_PASSWORD:-}") \
    "$CSR_FILE" \
    "$SIGNED_CERT"

  echo ">>> Installing signed Sub-CA certificate..."
  # Replace the self-signed intermediate cert with the Provider-signed one
  cp "$SIGNED_CERT" "$INTERMEDIATE_CERT"
  cp /tmp/tenant-sub-ca.key "$CA_KEY"

  echo ">>> Sub-CA certificate signed by Provider Root CA: OK"
  echo "    Chain: Provider Root CA → Tenant ($TENANT_ID) Issuing Sub-CA"
else
  echo ""
  echo "INFO: STEP_CA_PROVIDER_URL / STEP_CA_PROVIDER_FINGERPRINT not set."
  echo "      Running as standalone CA (no Sub-CA signing performed)."
  echo "      Set these variables and re-run this script to complete the JOIN workflow."
fi

# ── Task 2: Add IoT Bridge API JWK provisioner ──────────────────────────────
echo ""
echo ">>> Adding JWK provisioner: $PROVISIONER_NAME ..."
echo "$PROVISIONER_PASSWORD" | step ca provisioner add "$PROVISIONER_NAME" \
  --type JWK \
  --create \
  --password-file /dev/stdin \
  --admin-provisioner "$ADMIN_PROVISIONER" \
  --admin-password-file /run/secrets/step-ca-password

echo ">>> Attaching device-leaf template to provisioner $PROVISIONER_NAME ..."
step ca provisioner update "$PROVISIONER_NAME" \
  --x509-template "$DEVICE_TEMPLATE" \
  --admin-provisioner "$ADMIN_PROVISIONER" \
  --admin-password-file /run/secrets/step-ca-password

# ── Summary ──────────────────────────────────────────────────────────────────
echo ""
echo "=== Tenant Sub-CA setup complete ==="
echo ""
echo "Sub-CA fingerprint (needed for STEP_CA_FINGERPRINT in .env):"
step certificate fingerprint "$ROOT_CERT"
echo ""
echo "Add the following to tenant-stack/.env:"
echo "  STEP_CA_FINGERPRINT=$(step certificate fingerprint "$ROOT_CERT")"
echo "  STEP_CA_PROVISIONER_NAME=$PROVISIONER_NAME"
echo "  STEP_CA_PROVISIONER_PASSWORD=$PROVISIONER_PASSWORD"
echo ""
