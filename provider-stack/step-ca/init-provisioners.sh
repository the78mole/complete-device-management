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

# ── 1. Leaf-certificate provisioner ─────────────────────────────────────────

echo ""
echo ">>> Adding JWK provisioner (leaf certs): $PROVISIONER_NAME ..."
printf '%s' "$PROVISIONER_PASSWORD" > /tmp/provisioner-password.txt
step ca provisioner add "$PROVISIONER_NAME" \
  --type JWK \
  --create \
  --password-file /tmp/provisioner-password.txt \
  --admin-subject step \
  --admin-provisioner "$ADMIN_PROVISIONER" \
  --admin-password-file /run/secrets/step-ca-password

echo ">>> Attaching device-leaf template to $PROVISIONER_NAME ..."
step ca provisioner update "$PROVISIONER_NAME" \
  --x509-template "$DEVICE_TEMPLATE" \
  --admin-subject step \
  --admin-provisioner "$ADMIN_PROVISIONER" \
  --admin-password-file /run/secrets/step-ca-password

# ── 2. Tenant Sub-CA signer provisioner ─────────────────────────────────────

echo ""
echo ">>> Adding JWK provisioner (Sub-CA signer): $SUB_CA_PROVISIONER ..."
printf '%s' "$SUB_CA_PASSWORD" > /tmp/sub-ca-password.txt
step ca provisioner add "$SUB_CA_PROVISIONER" \
  --type JWK \
  --create \
  --password-file /tmp/sub-ca-password.txt \
  --admin-subject step \
  --admin-provisioner "$ADMIN_PROVISIONER" \
  --admin-password-file /run/secrets/step-ca-password

echo ">>> Attaching tenant-sub-ca template to $SUB_CA_PROVISIONER ..."
step ca provisioner update "$SUB_CA_PROVISIONER" \
  --x509-template "$SUB_CA_TEMPLATE" \
  --admin-subject step \
  --admin-provisioner "$ADMIN_PROVISIONER" \
  --admin-password-file /run/secrets/step-ca-password

rm -f /tmp/provisioner-password.txt /tmp/sub-ca-password.txt

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
