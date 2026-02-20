#!/bin/sh
# provision.sh
#
# Bootstrap ThingsBoard for the CDM IoT Platform:
#   1. Wait for ThingsBoard to be ready.
#   2. Import the CDM Device Provisioning rule chain.
#   3. Create an X.509 certificate-based device profile that uses the rule chain.
#
# Prerequisites:
#   - All containers in cloud-infrastructure/docker-compose.yml are running.
#   - This script is run from the cloud-infrastructure/ directory.
#
# Usage:
#   cd cloud-infrastructure
#   ./thingsboard/scripts/provision.sh
#
# Environment variables (override via export or inline):
#   TB_URL          – ThingsBoard base URL  (default: http://localhost:9090)
#   TB_SYSADMIN     – system admin email    (default: sysadmin@thingsboard.org)
#   TB_SYSADMIN_PASS– system admin password (default: sysadmin)

set -eu

TB_URL="${TB_URL:-http://localhost:9090}"
TB_SYSADMIN="${TB_SYSADMIN:-sysadmin@thingsboard.org}"
TB_SYSADMIN_PASS="${TB_SYSADMIN_PASS:-sysadmin}"
CHAIN_FILE="$(dirname "$0")/../rule-chains/device-provisioning-chain.json"

# ── Helpers ────────────────────────────────────────────────────────────────

log()  { echo "$(date '+%T') [provision] $*"; }
fail() { echo "$(date '+%T') [provision] ERROR: $*" >&2; exit 1; }

require_cmd() {
  command -v "$1" > /dev/null 2>&1 || fail "'$1' is required but not installed."
}

require_cmd curl
require_cmd jq

# ── Wait for ThingsBoard to accept requests ────────────────────────────────

log "Waiting for ThingsBoard at $TB_URL …"
READY=0
for i in $(seq 1 60); do
  STATUS=$(curl -s -o /dev/null -w "%{http_code}" "$TB_URL/api/noauth/activate" 2>/dev/null || echo "000")
  if [ "$STATUS" != "000" ]; then
    log "ThingsBoard is up (HTTP $STATUS after ${i}s check)."
    READY=1
    break
  fi
  sleep 5
done
if [ "$READY" -eq 0 ]; then
  fail "ThingsBoard did not become ready after 60 attempts (~5 minutes)."
fi

# ── Authenticate ────────────────────────────────────────────────────────────

log "Authenticating as sysadmin ($TB_SYSADMIN) …"
AUTH_RESP=$(curl -s -X POST \
  "${TB_URL}/api/auth/login" \
  -H "Content-Type: application/json" \
  -d "{\"username\":\"${TB_SYSADMIN}\",\"password\":\"${TB_SYSADMIN_PASS}\"}")

TOKEN=$(echo "$AUTH_RESP" | jq -r '.token // empty')
if [ -z "$TOKEN" ]; then
  fail "Login failed – response: $AUTH_RESP"
fi
log "Authenticated successfully."
AUTH="Authorization: Bearer $TOKEN"

# ── Import rule chain ───────────────────────────────────────────────────────

log "Importing CDM Device Provisioning rule chain …"
IMPORT_RESP=$(curl -s -w '\n%{http_code}' -X POST \
  "${TB_URL}/api/ruleChains/import?overwrite=true" \
  -H "$AUTH" \
  -H "Content-Type: application/json" \
  -d @"$CHAIN_FILE")

HTTP_CODE=$(echo "$IMPORT_RESP" | tail -1)
BODY=$(echo "$IMPORT_RESP" | head -n -1)

if [ "$HTTP_CODE" = "200" ] || [ "$HTTP_CODE" = "201" ]; then
  CHAIN_ID=$(echo "$BODY" | jq -r '.ruleChain.id.id // empty')
  log "Rule chain imported: id=$CHAIN_ID"
else
  fail "Rule chain import failed (HTTP $HTTP_CODE): $BODY"
fi

# ── Retrieve or create the X.509 device profile ────────────────────────────

log "Checking for existing 'CDM X.509 Devices' device profile …"
PROFILES_RESP=$(curl -s \
  "${TB_URL}/api/deviceProfiles?pageSize=20&page=0&textSearch=CDM+X.509" \
  -H "$AUTH")
EXISTING_ID=$(echo "$PROFILES_RESP" | jq -r '.data[0].id.id // empty')

if [ -n "$EXISTING_ID" ]; then
  log "Device profile already exists (id=$EXISTING_ID) – skipping creation."
else
  log "Creating 'CDM X.509 Devices' device profile …"
  PROFILE_PAYLOAD=$(cat <<EOF
{
  "name": "CDM X.509 Devices",
  "type": "DEFAULT",
  "transportType": "MQTT",
  "provisionType": "ALLOW_CREATE_NEW_DEVICES",
  "profileData": {
    "configuration": {
      "type": "DEFAULT"
    },
    "transportConfiguration": {
      "type": "MQTT",
      "deviceTelemetryTopic": "v1/devices/me/telemetry",
      "deviceAttributesTopic": "v1/devices/me/attributes",
      "sparkplug": false,
      "sendAckOnValidationException": false
    },
    "alarmRules": [],
    "provisionConfiguration": {
      "type": "ALLOW_CREATE_NEW_DEVICES",
      "provisionDeviceSecret": null
    }
  },
  "defaultRuleChainId": {
    "entityType": "RULE_CHAIN",
    "id": "${CHAIN_ID}"
  },
  "description": "Device profile for CDM-managed IoT devices authenticating via X.509 client certificates issued by step-ca."
}
EOF
)
  CREATE_RESP=$(curl -s -w '\n%{http_code}' -X POST \
    "${TB_URL}/api/deviceProfile" \
    -H "$AUTH" \
    -H "Content-Type: application/json" \
    -d "$PROFILE_PAYLOAD")

  HTTP_CODE=$(echo "$CREATE_RESP" | tail -1)
  BODY=$(echo "$CREATE_RESP" | head -n -1)

  if [ "$HTTP_CODE" = "200" ] || [ "$HTTP_CODE" = "201" ]; then
    PROFILE_ID=$(echo "$BODY" | jq -r '.id.id // empty')
    log "Device profile created: id=$PROFILE_ID"
  else
    fail "Device profile creation failed (HTTP $HTTP_CODE): $BODY"
  fi
fi

# ── Summary ─────────────────────────────────────────────────────────────────

log ""
log "=== ThingsBoard provisioning complete ==="
log ""
log "Rule chain:     id=$CHAIN_ID"
log "Device profile: 'CDM X.509 Devices'"
log ""
log "Next steps:"
log "  1. In ThingsBoard, set the Root CA for MQTT TLS under:"
log "     Security → Certificate authorities → Upload /step-ca-certs/certs/root_ca.crt"
log "  2. Upload the MQTT server certificate (see docker-compose.yml env vars)."
log "  3. Enroll a device: POST http://localhost:8000/devices/<id>/enroll"
log "  4. The device uses its signed cert + MQTT TLS to connect to port 8883."
log "  5. The CDM Device Provisioning rule chain:"
log "     – auto-provisions the device in hawkBit on first connect"
log "     – forwards device telemetry to iot-bridge-api which writes to"
log "       InfluxDB with tenant_id + device_id tags (Mandanten-Isolation)"
log "  6. The cloud-side Telegraf service collects hawkBit OTA status metrics"
log "     per tenant and writes them to InfluxDB (bucket: iot-metrics)."
