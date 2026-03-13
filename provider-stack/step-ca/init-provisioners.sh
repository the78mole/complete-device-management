#!/bin/sh
# provider-stack/step-ca/init-provisioners.sh
#
# Run ONCE after the step-ca container has completed first-time initialization.
# Adds two JWK provisioners:
#   1. iot-bridge          – signs leaf device/service certificates
#   2. tenant-sub-ca-signer – signs Tenant Sub-CA CSRs (isCA=true, maxPathLen=0)
#
# Usage (from repo root):
#   docker exec -it provider-step-ca /usr/local/bin/init-provisioners.sh
#
# Required env vars (set in docker-compose environment or .env):
#   STEP_CA_PROVISIONER_NAME      – leaf provisioner name     (default: iot-bridge)
#   STEP_CA_PROVISIONER_PASSWORD  – leaf provisioner password  (default: changeme)
#   STEP_CA_SUB_CA_PROVISIONER    – sub-CA provisioner name    (default: tenant-sub-ca-signer)
#   STEP_CA_SUB_CA_PASSWORD       – sub-CA provisioner password (default: changeme)

set -eu

CA_CONFIG="/home/step/config/ca.json"
PROVISIONER_NAME="${STEP_CA_PROVISIONER_NAME:-iot-bridge}"
PROVISIONER_PASSWORD="${STEP_CA_PROVISIONER_PASSWORD:-changeme}"
SUB_CA_PROVISIONER="${STEP_CA_SUB_CA_PROVISIONER:-tenant-sub-ca-signer}"
SUB_CA_PASSWORD="${STEP_CA_SUB_CA_PASSWORD:-changeme}"
DEVICE_TEMPLATE="/home/step/templates/device-leaf.tpl"
SERVICE_TEMPLATE="/home/step/templates/service-leaf.tpl"
SUB_CA_TEMPLATE="/home/step/templates/tenant-sub-ca.tpl"
CA_URL="https://localhost:9000"
ADMIN_PROVISIONER="${DOCKER_STEPCA_INIT_PROVISIONER_NAME:-cdm-admin@cdm.local}"

if [ ! -f "$CA_CONFIG" ]; then
  echo "ERROR: $CA_CONFIG not found – run container first to trigger DOCKER_STEPCA_INIT."
  exit 1
fi

echo ">>> Bootstrapping trust against local CA..."
step ca bootstrap \
  --ca-url "$CA_URL" \
  --fingerprint "$(step certificate fingerprint /home/step/certs/root_ca.crt)" \
  --force

# Helper: add a JWK provisioner if it does not already exist.
# Treats "already exists" as success (idempotent).
add_jwk_provisioner() {
  local name="$1" password="$2"
  printf '%s' "$password" > /tmp/jwk-prov-pw.txt
  ADD_OUTPUT=$(step ca provisioner add "$name" \
    --type JWK \
    --create \
    --password-file /tmp/jwk-prov-pw.txt \
    --admin-subject step \
    --admin-provisioner "$ADMIN_PROVISIONER" \
    --admin-password-file /run/secrets/step-ca-password 2>&1) && \
    echo "  '$name' added." || \
    { echo "$ADD_OUTPUT" | grep -q "already exists" && echo "  '$name' already exists – skipping add." || \
      { echo "$ADD_OUTPUT"; rm -f /tmp/jwk-prov-pw.txt; return 1; }; }
  rm -f /tmp/jwk-prov-pw.txt
}

# ── 1. Leaf-certificate provisioner ─────────────────────────────────────────

echo ""
echo ">>> Provisioner (leaf certs): $PROVISIONER_NAME ..."
add_jwk_provisioner "$PROVISIONER_NAME" "$PROVISIONER_PASSWORD"

echo ">>> Attaching service-leaf template and setting max cert duration for $PROVISIONER_NAME ..."
step ca provisioner update "$PROVISIONER_NAME" \
  --x509-template "$SERVICE_TEMPLATE" \
  --x509-max-dur 8760h \
  --admin-subject step \
  --admin-provisioner "$ADMIN_PROVISIONER" \
  --admin-password-file /run/secrets/step-ca-password

# ── 2. Tenant Sub-CA signer provisioner ─────────────────────────────────────

echo ""
echo ">>> Provisioner (Sub-CA signer): $SUB_CA_PROVISIONER ..."
add_jwk_provisioner "$SUB_CA_PROVISIONER" "$SUB_CA_PASSWORD"

echo ">>> Attaching tenant-sub-ca template to $SUB_CA_PROVISIONER ..."
step ca provisioner update "$SUB_CA_PROVISIONER" \
  --x509-template "$SUB_CA_TEMPLATE" \
  --admin-subject step \
  --admin-provisioner "$ADMIN_PROVISIONER" \
  --admin-password-file /run/secrets/step-ca-password

# ── Summary ──────────────────────────────────────────────────────────────────

echo ""
echo "=== Provider step-ca provisioner setup complete ==="
echo ""
echo "Root CA fingerprint (add to provider-stack/.env as STEP_CA_FINGERPRINT):"
step certificate fingerprint /home/step/certs/root_ca.crt
echo ""
echo "Environment variables for provider-stack/.env:"
echo "  STEP_CA_FINGERPRINT=$(step certificate fingerprint /home/step/certs/root_ca.crt)"
echo "  STEP_CA_PROVISIONER_NAME=$PROVISIONER_NAME"
echo "  STEP_CA_PROVISIONER_PASSWORD=$PROVISIONER_PASSWORD"
echo "  STEP_CA_SUB_CA_PROVISIONER=$SUB_CA_PROVISIONER"
echo "  STEP_CA_SUB_CA_PASSWORD=$SUB_CA_PASSWORD"
