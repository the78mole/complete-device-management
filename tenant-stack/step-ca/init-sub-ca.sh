#!/bin/sh
# init-sub-ca.sh – Tenant Stack step-ca Sub-CA initialisation
#
# This script performs TWO tasks that must run once after the first start:
#
# Task 1 – (Automated) JOIN request to the Provider IoT Bridge API
#   Generates a Sub-CA CSR, submits it to the Provider API (JOIN workflow),
#   and polls until the Provider Admin approves the request.  Once approved the
#   script installs the signed certificate and configures the Tenant step-ca to
#   use the Provider-issued Sub-CA instead of the self-signed one.
#
#   Required env vars:
#     PROVIDER_API_URL  – e.g. https://provider.iot.example.com/api
#     TENANT_ID         – unique slug for this tenant
#     TENANT_DISPLAY_NAME – human-readable name
#
#   Optional:
#     TENANT_KEYCLOAK_URL – external Keycloak URL, passed to the Provider
#                           for Keycloak federation registration
#     JOIN_POLL_INTERVAL  – seconds between status polls (default: 60)
#     JOIN_TIMEOUT        – max seconds to wait for approval (default: 3600)
#
#   If PROVIDER_API_URL is not set, the Sub-CA runs standalone (dev mode).
#
# Task 2 – Add IoT Bridge API JWK provisioner
#   Adds a dedicated JWK provisioner for the iot-bridge-api.
#
# Usage (from the host):
#   docker compose exec ${TENANT_ID:-tenant}-step-ca /usr/local/bin/init-sub-ca.sh

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
TENANT_DISPLAY_NAME="${TENANT_DISPLAY_NAME:-Tenant $TENANT_ID}"
TENANT_KEYCLOAK_URL="${TENANT_KEYCLOAK_URL:-}"

PROVIDER_API_URL="${PROVIDER_API_URL:-}"
JOIN_POLL_INTERVAL="${JOIN_POLL_INTERVAL:-60}"
JOIN_TIMEOUT="${JOIN_TIMEOUT:-3600}"

# Tenant Keycloak admin (used by init-sub-ca.sh to register Provider KC as IdP)
KC_INTERNAL_URL="${KC_INTERNAL_URL:-http://keycloak:8080/auth}"
KC_ADMIN_USER="${KC_ADMIN_USER:-admin}"
KC_ADMIN_PASSWORD="${KC_ADMIN_PASSWORD:-changeme}"

if [ ! -f "$CA_CONFIG" ]; then
  echo "ERROR: $CA_CONFIG not found – run container first to trigger DOCKER_STEPCA_INIT."
  exit 1
fi

echo ">>> Bootstrapping trust against local CA..."
step ca bootstrap \
  --ca-url "$CA_URL" \
  --fingerprint "$(step certificate fingerprint "$ROOT_CERT")" \
  --force

# ── Task 1: JOIN workflow via Provider IoT Bridge API ───────────────────────
if [ -n "$PROVIDER_API_URL" ]; then
  PROVIDER_API="${PROVIDER_API_URL%/}"
  CSR_FILE="/tmp/tenant-sub-ca.csr"
  KEY_FILE="/tmp/tenant-sub-ca.key"
  MQTT_CSR_FILE="/tmp/mqtt-bridge.csr"
  MQTT_KEY_FILE="/tmp/mqtt-bridge.key"
  MQTT_BRIDGE_DIR="/home/step/mqtt-bridge"
  STATE_FILE="/tmp/join_status"

  echo ""
  echo ">>> Generating Sub-CA key pair and CSR for tenant: $TENANT_ID ..."
  step certificate create \
    "$TENANT_DISPLAY_NAME Issuing CA" \
    "$CSR_FILE" \
    "$KEY_FILE" \
    --kty EC \
    --curve P-256 \
    --csr \
    --no-password \
    --insecure

  echo ">>> Generating MQTT bridge client key pair and CSR ..."
  mkdir -p "$MQTT_BRIDGE_DIR"
  step certificate create \
    "${TENANT_ID}-mqtt-bridge" \
    "$MQTT_CSR_FILE" \
    "$MQTT_KEY_FILE" \
    --kty EC \
    --curve P-256 \
    --csr \
    --no-password \
    --insecure

  # Read WireGuard public key if wg0 exists, else send placeholder
  WG_PUBKEY=""
  if command -v wg >/dev/null 2>&1; then
    WG_PUBKEY="$(wg pubkey < /etc/wireguard/priv_key 2>/dev/null || true)"
  fi
  if [ -f /etc/wireguard/pub_key ]; then
    WG_PUBKEY="$(cat /etc/wireguard/pub_key)"
  fi
  WG_PUBKEY="${WG_PUBKEY:-not-available}"

  CSR_PEM="$(cat "$CSR_FILE")"
  MQTT_CSR_PEM="$(cat "$MQTT_CSR_FILE")"

  echo ">>> Submitting JOIN request to $PROVIDER_API ..."
  # Embed PEM blocks in JSON: escape backslashes, double-quotes, then fold newlines to \n
  _json_pem() { printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g' | awk '{printf "%s\\n", $0}' | sed '$ s/\\n$//'; }

  # Build JSON payload
  PAYLOAD=$(printf '{"display_name":"%s","sub_ca_csr":"%s","wg_pubkey":"%s","keycloak_url":"%s","mqtt_bridge_csr":"%s"}' \
    "$TENANT_DISPLAY_NAME" \
    "$(_json_pem "$CSR_PEM")" \
    "$WG_PUBKEY" \
    "$TENANT_KEYCLOAK_URL" \
    "$(_json_pem "$MQTT_CSR_PEM")")

  HTTP_CODE=$(curl -sf -o /dev/null -w "%{http_code}" \
    -X POST \
    -H "Content-Type: application/json" \
    -d "$PAYLOAD" \
    "$PROVIDER_API/portal/admin/join-request/$TENANT_ID" \
    2>&1) || true

  if [ "$HTTP_CODE" != "202" ] && [ "$HTTP_CODE" != "409" ]; then
    echo "WARNING: JOIN request returned HTTP $HTTP_CODE. Will poll status anyway."
  else
    echo "    JOIN request submitted (HTTP $HTTP_CODE). Waiting for Provider Admin approval..."
  fi

  # ── Poll for approval ────────────────────────────────────────────────────
  ELAPSED=0
  while [ "$ELAPSED" -lt "$JOIN_TIMEOUT" ]; do
    echo ">>> Polling JOIN status … (${ELAPSED}s elapsed)"
    STATUS_JSON=$(curl -sf \
      "$PROVIDER_API/portal/admin/tenants/$TENANT_ID/join-status" 2>/dev/null || echo '{}')

    STATUS=$(printf '%s' "$STATUS_JSON" | grep -o '"status":"[^"]*"' | head -1 | cut -d'"' -f4)

    if [ "$STATUS" = "approved" ]; then
      echo ">>> JOIN approved! Installing signed Sub-CA certificate..."

      # Extract signed certificate from JSON response
      SIGNED_CERT=$(printf '%s' "$STATUS_JSON" \
        | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('signed_cert',''))" 2>/dev/null || true)
      ROOT_CA_DATA=$(printf '%s' "$STATUS_JSON" \
        | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('root_ca_cert',''))" 2>/dev/null || true)

      if [ -n "$SIGNED_CERT" ]; then
        printf '%s\n' "$SIGNED_CERT" > "$INTERMEDIATE_CERT"
        echo "    Installed signed intermediate certificate."
      fi
      if [ -n "$ROOT_CA_DATA" ]; then
        printf '%s\n' "$ROOT_CA_DATA" > "$ROOT_CERT"
        echo "    Installed Provider Root CA certificate."
      fi

      # Install the Sub-CA key we generated
      if [ -f "$KEY_FILE" ]; then
        cp "$KEY_FILE" "$CA_KEY"
        chmod 600 "$CA_KEY"
        echo "    Installed Sub-CA private key."
      fi

      # Install MQTT bridge client certificate and key
      MQTT_CERT=$(printf '%s' "$STATUS_JSON" \
        | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('mqtt_bridge_cert',''))" 2>/dev/null || true)
      if [ -n "$MQTT_CERT" ]; then
        mkdir -p "$MQTT_BRIDGE_DIR"
        printf '%s\n' "$MQTT_CERT" > "$MQTT_BRIDGE_DIR/client.crt"
        cp "$MQTT_KEY_FILE" "$MQTT_BRIDGE_DIR/client.key"
        chmod 600 "$MQTT_BRIDGE_DIR/client.key"
        [ -n "$ROOT_CA_DATA" ] && printf '%s\n' "$ROOT_CA_DATA" > "$MQTT_BRIDGE_DIR/ca.crt"
        echo "    MQTT bridge certificates installed in $MQTT_BRIDGE_DIR"
      fi

      # Write MQTT connection info (mTLS, no password) to a well-known location
      RMQ_URL=$(printf '%s' "$STATUS_JSON" \
        | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('rabbitmq_url',''))" 2>/dev/null || true)
      RMQ_VHOST=$(printf '%s' "$STATUS_JSON" \
        | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('rabbitmq_vhost',''))" 2>/dev/null || true)
      RMQ_USER=$(printf '%s' "$STATUS_JSON" \
        | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('rabbitmq_user',''))" 2>/dev/null || true)

      if [ -n "$RMQ_URL" ]; then
        mkdir -p /home/step/join-bundle
        # Derive the MQTTS host from the management API URL
        MQTTS_HOST=$(printf '%s' "$RMQ_URL" | sed 's|http://||; s|https://||; s|:.*||')
        printf 'RABBITMQ_MQTTS_URL=mqtts://%s:8883\nRABBITMQ_VHOST=%s\nRABBITMQ_USER=%s\nRABBITMQ_TLS_CERT=%s/client.crt\nRABBITMQ_TLS_KEY=%s/client.key\nRABBITMQ_TLS_CA=%s/ca.crt\n' \
          "$MQTTS_HOST" "$RMQ_VHOST" "$RMQ_USER" \
          "$MQTT_BRIDGE_DIR" "$MQTT_BRIDGE_DIR" "$MQTT_BRIDGE_DIR" \
          > /home/step/join-bundle/rabbitmq.env
        echo "    MQTT connection config written to /home/step/join-bundle/rabbitmq.env"
      fi

      # Register Provider Keycloak as Identity Provider in Tenant Keycloak
      # CDM Admins can then log into Tenant services (ThingsBoard, Grafana) via Provider KC SSO.
      CDM_IDP_CLIENT_ID=$(printf '%s' "$STATUS_JSON" \
        | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('cdm_idp_client_id',''))" 2>/dev/null || true)
      CDM_IDP_SECRET=$(printf '%s' "$STATUS_JSON" \
        | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('cdm_idp_client_secret',''))" 2>/dev/null || true)
      CDM_DISC_URL=$(printf '%s' "$STATUS_JSON" \
        | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('cdm_discovery_url',''))" 2>/dev/null || true)

      # Always write federation credentials for later manual setup / reference
      mkdir -p /home/step/join-bundle
      printf 'CDM_IDP_CLIENT_ID=%s\nCDM_IDP_CLIENT_SECRET=%s\nCDM_DISCOVERY_URL=%s\nKC_IDP_ALIAS=cdm-provider\n' \
        "$CDM_IDP_CLIENT_ID" "$CDM_IDP_SECRET" "$CDM_DISC_URL" \
        > /home/step/join-bundle/keycloak-federation.env
      echo "    Keycloak federation credentials written to /home/step/join-bundle/keycloak-federation.env"

      if [ -n "$CDM_IDP_CLIENT_ID" ] && [ -n "$KC_INTERNAL_URL" ]; then
        echo ">>> Registering Provider Keycloak as Identity Provider in Tenant KC realm '${TENANT_ID}' ..."
        KC_BASE="${KC_INTERNAL_URL%/}"

        # Build the IdP payload (pass values as argv to avoid shell-injection)
        python3 -c "
import json, sys
print(json.dumps({
  'alias': 'cdm-provider',
  'displayName': 'CDM Platform (Provider)',
  'providerId': 'oidc',
  'enabled': True,
  'trustEmail': True,
  'storeToken': False,
  'addReadTokenRoleOnCreate': False,
  'config': {
    'clientId': sys.argv[1],
    'clientSecret': sys.argv[2],
    'metadataDescriptorUrl': sys.argv[3],
    'useJwksUrl': 'true',
    'syncMode': 'FORCE',
    'defaultScope': 'openid profile email roles',
  }
}))
" "$CDM_IDP_CLIENT_ID" "$CDM_IDP_SECRET" "$CDM_DISC_URL" > /tmp/kc-idp-payload.json 2>/dev/null || true

        # Get Tenant KC admin token
        KC_TOKEN=$(curl -sf -X POST \
          "${KC_BASE}/realms/master/protocol/openid-connect/token" \
          -d 'grant_type=password&client_id=admin-cli' \
          --data-urlencode "username=${KC_ADMIN_USER}" \
          --data-urlencode "password=${KC_ADMIN_PASSWORD}" \
          | python3 -c "import sys,json; print(json.load(sys.stdin).get('access_token',''))" 2>/dev/null || true)

        if [ -n "$KC_TOKEN" ] && [ -s /tmp/kc-idp-payload.json ]; then
          IDP_HTTP=$(curl -sf -o /dev/null -w "%{http_code}" -X POST \
            "${KC_BASE}/admin/realms/${TENANT_ID}/identity-provider/instances" \
            -H "Authorization: Bearer ${KC_TOKEN}" \
            -H "Content-Type: application/json" \
            -d @/tmp/kc-idp-payload.json 2>/dev/null || echo "000")
          if [ "$IDP_HTTP" = "201" ] || [ "$IDP_HTTP" = "409" ]; then
            echo "    IdP 'cdm-provider' registered in Tenant KC (HTTP ${IDP_HTTP})."
            echo "    CDM Admins can now log into Tenant services via Provider Keycloak SSO."
          else
            echo "    WARNING: IdP registration returned HTTP ${IDP_HTTP}."
            echo "    Configure manually: Tenant KC Admin → Realm '${TENANT_ID}' → Identity Providers."
            echo "    Use credentials from /home/step/join-bundle/keycloak-federation.env"
          fi
          rm -f /tmp/kc-idp-payload.json
        else
          echo "    WARNING: Could not reach Tenant KC or get admin token. Skipping IdP auto-registration."
          echo "    Configure manually using /home/step/join-bundle/keycloak-federation.env"
        fi
      fi

      echo ""
      echo ">>> JOIN workflow complete."
      echo "    Chain: Provider Root CA → Tenant ($TENANT_ID) Sub-CA → Device Leaf Certs"
      printf '%s' "$STATUS" > "$STATE_FILE"
      break
    elif [ "$STATUS" = "rejected" ]; then
      REASON=$(printf '%s' "$STATUS_JSON" \
        | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('rejected_reason',''))" 2>/dev/null || true)
      echo "ERROR: JOIN request rejected by Provider Admin: $REASON"
      printf 'rejected' > "$STATE_FILE"
      # Don't exit – fall through to add provisioner (standalone mode)
      break
    fi

    sleep "$JOIN_POLL_INTERVAL"
    ELAPSED=$((ELAPSED + JOIN_POLL_INTERVAL))
  done

  if [ ! -f "$STATE_FILE" ]; then
    echo "WARNING: JOIN request timed out after ${JOIN_TIMEOUT}s. Continuing in standalone mode."
  fi
else
  echo ""
  echo "INFO: PROVIDER_API_URL not set – running in standalone mode."
  echo "      Set PROVIDER_API_URL and TENANT_ID and rerun to complete the JOIN workflow."
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
