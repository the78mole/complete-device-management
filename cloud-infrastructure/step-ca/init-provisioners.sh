#!/bin/sh
# init-provisioners.sh
#
# Run this script ONCE after the step-ca container has completed its first-time
# initialization (i.e. after DOCKER_STEPCA_INIT_* has generated ca.json).
#
# It adds a dedicated JWK provisioner for the iot-bridge-api so that service
# can sign device leaf certificates without sharing the primary admin password,
# and attaches the device-leaf certificate template to that provisioner.
#
# Usage (from the host):
#   docker exec -it cdm-step-ca /usr/local/bin/init-provisioners.sh
#
# Prerequisites:
#   - The container must be running and ca.json must exist.
#   - STEP_CA_PROVISIONER_NAME and STEP_CA_PROVISIONER_PASSWORD env vars must
#     be set (or passed inline).

set -eu

CA_CONFIG="/home/step/config/ca.json"
PROVISIONER_NAME="${STEP_CA_PROVISIONER_NAME:-iot-bridge}"
PROVISIONER_PASSWORD="${STEP_CA_PROVISIONER_PASSWORD:-changeme}"
DEVICE_TEMPLATE="/home/step/templates/device-leaf.tpl"
SERVICE_TEMPLATE="/home/step/templates/service-leaf.tpl"
CA_URL="https://localhost:9000"
ADMIN_PROVISIONER="${DOCKER_STEPCA_INIT_PROVISIONER_NAME:-cdm-admin@cdm.local}"

if [ ! -f "$CA_CONFIG" ]; then
  echo "ERROR: $CA_CONFIG not found – run container first to trigger DOCKER_STEPCA_INIT."
  exit 1
fi

echo ">>> Bootstrapping trust against local CA..."
step ca bootstrap --ca-url "$CA_URL" --fingerprint "$(step certificate fingerprint /home/step/certs/root_ca.crt)" --force

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

echo ""
echo "=== Setup complete ==="
echo ""
echo "Root CA fingerprint (needed for STEP_CA_FINGERPRINT in .env):"
step certificate fingerprint /home/step/certs/root_ca.crt
echo ""
echo "Add the following to cloud-infrastructure/.env:"
echo "  STEP_CA_FINGERPRINT=$(step certificate fingerprint /home/step/certs/root_ca.crt)"
echo "  STEP_CA_PROVISIONER_NAME=$PROVISIONER_NAME"
echo "  STEP_CA_PROVISIONER_PASSWORD=$PROVISIONER_PASSWORD"
