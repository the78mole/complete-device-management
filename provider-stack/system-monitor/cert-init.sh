#!/bin/sh
# cert-init.sh – one-shot MQTT client certificate provisioner
#
# Runs as a Docker Compose init-service (restart: "no") using the
# smallstep/step-cli image.  Fetches client certificates for the
# system-monitor and telegraf services from the Provider step-ca and
# writes them to the shared `mqtt-client-tls` volume.
#
# RabbitMQ uses EXTERNAL auth (mqtt.ssl_cert_login = true) which maps
# the client certificate CN to the RabbitMQ username – so no passwords
# are involved in broker authentication.
#
# Required environment variables:
#   STEP_CA_URL                  – e.g. https://step-ca:9000
#   STEP_CA_FINGERPRINT          – SHA-256 fingerprint of the Root CA cert
#   STEP_CA_PROVISIONER_NAME     – JWK provisioner name (default: iot-bridge)
#   STEP_CA_PROVISIONER_PASSWORD – JWK provisioner password
#
# Output (written to CERTS_DIR, default: /etc/mqtt-certs):
#   ca.crt               – Provider Root CA (for TLS server verification)
#   system-monitor.crt   – Client cert CN=system-monitor
#   system-monitor.key
#   telegraf.crt         – Client cert CN=telegraf
#   telegraf.key

set -eu

CERTS_DIR="${CERTS_DIR:-/etc/mqtt-certs}"

STEP_CA_URL="${STEP_CA_URL:-https://step-ca:9000}"
STEP_CA_FINGERPRINT="${STEP_CA_FINGERPRINT:-}"
STEP_CA_PROVISIONER_NAME="${STEP_CA_PROVISIONER_NAME:-iot-bridge}"
STEP_CA_PROVISIONER_PASSWORD="${STEP_CA_PROVISIONER_PASSWORD:-changeme}"

# ── Helper: issue_cert <cn> ───────────────────────────────────────────────────
# Issues (or re-issues) a client cert for the given Common Name.
# Idempotency: skips re-issue if an existing cert is still valid.
issue_cert() {
  CN="$1"
  CERT="$CERTS_DIR/$CN.crt"
  KEY="$CERTS_DIR/$CN.key"

  if [ -f "$CERT" ] && [ -f "$KEY" ]; then
    if step certificate verify "$CERT" --roots "$CERTS_DIR/ca.crt" 2>/dev/null; then
      NOT_AFTER=$(step certificate inspect "$CERT" --format json \
        | grep '"NotAfter"' | head -1 | grep -oE '[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9:]+Z' || true)
      echo "    CN=$CN: cert already valid (NotAfter: $NOT_AFTER). Skipping."
      return
    fi
    echo "    CN=$CN: cert invalid or expiring – re-issuing."
  fi

  echo ">>> Requesting client certificate CN=$CN ..."
  step ca certificate "$CN" \
    "$CERT" \
    "$KEY" \
    --kty EC \
    --curve P-256 \
    --provisioner "$STEP_CA_PROVISIONER_NAME" \
    --provisioner-password-file /tmp/provisioner-password.txt \
    --not-after 8760h \
    --force

  # Keys in a Docker-internal volume – world-readable so non-root containers
  # (system-monitor uid 10001, telegraf) can access them without CAP_DAC_OVERRIDE.
  chmod 644 "$KEY"
  chmod 644 "$CERT"
  echo "    $CERT"
  echo "    $KEY"
}

# ── Bootstrap ─────────────────────────────────────────────────────────────────
mkdir -p "$CERTS_DIR"

if [ -z "$STEP_CA_FINGERPRINT" ]; then
  echo "ERROR: STEP_CA_FINGERPRINT is not set. Cannot bootstrap trust."
  exit 1
fi

echo ">>> Bootstrapping trust against $STEP_CA_URL ..."
step ca bootstrap \
  --ca-url "$STEP_CA_URL" \
  --fingerprint "$STEP_CA_FINGERPRINT" \
  --force

cp "$(step path)/certs/root_ca.crt" "$CERTS_DIR/ca.crt"
chmod 644 "$CERTS_DIR/ca.crt"
echo "    Root CA written to $CERTS_DIR/ca.crt"

# Store provisioner password once for both cert issuances
printf '%s\n' "$STEP_CA_PROVISIONER_PASSWORD" > /tmp/provisioner-password.txt

# ── Issue client certificates ─────────────────────────────────────────────────
echo ""
echo ">>> Issuing MQTT client certificates..."
issue_cert "system-monitor"
issue_cert "telegraf"

rm -f /tmp/provisioner-password.txt

echo ""
echo ">>> mqtt-certs-init complete. Contents of $CERTS_DIR:"
ls -la "$CERTS_DIR"
