#!/usr/bin/env bash
# kc-apply-account-audience-mapper.sh
#
# Adds the 'account-audience' protocol mapper to the 'account-console' client
# in one or more Keycloak realms.  This mapper injects 'account' into the
# access-token 'aud' claim, which the Account REST API requires (KC 26+).
#
# Without this mapper, every call to
#   /auth/realms/<realm>/account/?userProfileMetadata=true
# returns HTTP 403 regardless of user roles.
#
# Usage:
#   bash scripts/kc-apply-account-audience-mapper.sh [BASE_URL] [REALM …]
#
# Examples:
#   bash scripts/kc-apply-account-audience-mapper.sh
#   bash scripts/kc-apply-account-audience-mapper.sh http://localhost:8888 cdm provider
#   bash scripts/kc-apply-account-audience-mapper.sh https://host-8888.app.github.dev cdm
#   # Tenant-Stack (provide its base URL and realm name explicitly):
#   bash scripts/kc-apply-account-audience-mapper.sh http://<tenant-host>:8888 <tenant-realm>
#
# Arguments:
#   $1          Base URL (default: http://localhost:8888)
#   $2 … $N    Realm names (default: master cdm provider)
#
# Exit codes: 0 = all OK (409 Conflict = already exists, treated as OK)

set -euo pipefail

BASE_URL="${1:-http://localhost:8888}"
shift || true
# Provider-stack manages only 'cdm' and 'provider'.
# Tenant realms live in per-tenant tenant-stack instances (Phase 2).
REALMS="${*:-master cdm provider}"

TOKEN=$(bash "$(dirname "$0")/kc-token.sh" "$BASE_URL")

MAPPER_JSON='{
  "name": "account-audience",
  "protocol": "openid-connect",
  "protocolMapper": "oidc-audience-mapper",
  "consentRequired": false,
  "config": {
    "included.client.audience": "account",
    "id.token.claim": "false",
    "access.token.claim": "true"
  }
}'

for REALM in $REALMS; do
  AC_ID=$(curl -sf \
    "${BASE_URL}/auth/admin/realms/${REALM}/clients?clientId=account-console" \
    -H "Authorization: Bearer $TOKEN" \
    | python3 -c "import sys,json; c=json.load(sys.stdin); print(c[0]['id']) if c else exit(1)" \
    2>/dev/null) || { echo "  $REALM: account-console client not found – skipping"; continue; }

  HTTP=$(curl -s -o /dev/null -w "%{http_code}" \
    -X POST "${BASE_URL}/auth/admin/realms/${REALM}/clients/${AC_ID}/protocol-mappers/models" \
    -H "Authorization: Bearer $TOKEN" \
    -H "Content-Type: application/json" \
    -d "$MAPPER_JSON")

  case "$HTTP" in
    201) echo "$REALM: account-audience mapper added (HTTP 201)" ;;
    409) echo "$REALM: account-audience mapper already exists (HTTP 409)" ;;
    *)   echo "$REALM: unexpected HTTP $HTTP" ;;
  esac
done
