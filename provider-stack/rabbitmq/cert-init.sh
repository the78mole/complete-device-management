#!/bin/sh
# cert-init.sh – one-shot RabbitMQ server certificate provisioner
#
# Runs as a Docker Compose init-service (restart: "no") using the
# smallstep/step-cli image.  Fetches a TLS server certificate from the
# Provider step-ca and writes it to the shared `rabbitmq-tls` volume so
# that RabbitMQ can start with TLS+MQTT on port 8883.
#
# Required environment variables:
#   STEP_CA_URL                  – e.g. https://step-ca:9000
#   STEP_CA_FINGERPRINT          – SHA-256 fingerprint of the Root CA cert
#   STEP_CA_PROVISIONER_NAME     – JWK provisioner name (default: iot-bridge)
#   STEP_CA_PROVISIONER_PASSWORD – JWK provisioner password
#
# Output:
#   /etc/rabbitmq/tls/ca.crt     – Provider Root CA certificate
#   /etc/rabbitmq/tls/server.crt – RabbitMQ server certificate (PEM)
#   /etc/rabbitmq/tls/server.key – RabbitMQ server private key (PEM, 0600)

set -eu

TLS_DIR="/etc/rabbitmq/tls"
CA_CERT="$TLS_DIR/ca.crt"
SERVER_CERT="$TLS_DIR/server.crt"
SERVER_KEY="$TLS_DIR/server.key"

STEP_CA_URL="${STEP_CA_URL:-https://step-ca:9000}"
STEP_CA_FINGERPRINT="${STEP_CA_FINGERPRINT:-}"
STEP_CA_PROVISIONER_NAME="${STEP_CA_PROVISIONER_NAME:-iot-bridge}"
STEP_CA_PROVISIONER_PASSWORD="${STEP_CA_PROVISIONER_PASSWORD:-changeme}"

mkdir -p "$TLS_DIR"

# ── Idempotency check: skip if a valid cert already exists ───────────────────
if [ -f "$SERVER_CERT" ] && [ -f "$SERVER_KEY" ]; then
  echo ">>> RabbitMQ TLS cert already exists – checking expiry..."
  if step certificate inspect "$SERVER_CERT" --format json 2>/dev/null \
      | grep -q '"NotAfter"'; then
    # Check that the cert is not expiring within 24 h
    if step certificate verify "$SERVER_CERT" --roots "$CA_CERT" 2>/dev/null; then
      NOT_AFTER=$(step certificate inspect "$SERVER_CERT" --format json \
        | grep '"NotAfter"' | head -1 | grep -oE '[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9:]+Z')
      echo "    Cert valid. NotAfter: $NOT_AFTER. Skipping re-issue."
      exit 0
    fi
  fi
  echo "    Cert invalid or expiring soon – re-issuing."
fi

# ── Bootstrap trust against Provider step-ca ─────────────────────────────────
if [ -z "$STEP_CA_FINGERPRINT" ]; then
  echo "ERROR: STEP_CA_FINGERPRINT is not set. Cannot bootstrap trust."
  exit 1
fi

echo ">>> Bootstrapping trust against $STEP_CA_URL ..."
step ca bootstrap \
  --ca-url "$STEP_CA_URL" \
  --fingerprint "$STEP_CA_FINGERPRINT" \
  --force

# Copy the root CA cert to the TLS dir for RabbitMQ's cacertfile
cp "$(step path)/certs/root_ca.crt" "$CA_CERT"
echo "    Root CA written to $CA_CERT"

# ── Issue the RabbitMQ server certificate ────────────────────────────────────
echo ">>> Requesting RabbitMQ server certificate from step-ca..."
printf '%s\n' "$STEP_CA_PROVISIONER_PASSWORD" > /tmp/provisioner-password.txt

step ca certificate "rabbitmq" \
  "$SERVER_CERT" \
  "$SERVER_KEY" \
  --san "rabbitmq" \
  --san "localhost" \
  --san "provider-rabbitmq" \
  --kty EC \
  --curve P-256 \
  --provisioner "$STEP_CA_PROVISIONER_NAME" \
  --provisioner-password-file /tmp/provisioner-password.txt \
  --not-after 8760h \
  --no-password \
  --insecure \
  --force

rm -f /tmp/provisioner-password.txt

chmod 600 "$SERVER_KEY"
chmod 644 "$SERVER_CERT" "$CA_CERT"

echo ">>> RabbitMQ TLS certificates written:"
echo "    CA:  $CA_CERT"
echo "    Cert: $SERVER_CERT"
echo "    Key:  $SERVER_KEY"
echo ">>> cert-init complete."
