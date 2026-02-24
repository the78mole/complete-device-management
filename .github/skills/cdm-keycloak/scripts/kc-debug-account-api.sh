#!/usr/bin/env bash
# kc-debug-account-api.sh
#
# Diagnoses Account REST API (Keycloak Account Console back end) access for a
# specified user. Verifies:
#   1. The user exists in the realm
#   2. A token can be obtained (temporarily enables directAccessGrants if needed)
#   3. The token contains the `account` audience
#   4. GET /account/?userProfileMetadata=true returns HTTP 200
#
# The script restores the client's directAccessGrants setting when done.
#
# Usage:
#   bash scripts/kc-debug-account-api.sh REALM USERNAME PASSWORD [BASE_URL]
#
# Examples:
#   bash scripts/kc-debug-account-api.sh cdm cdm-admin <CDM_ADMIN_PASSWORD>
#   bash scripts/kc-debug-account-api.sh provider provider-operator <password> http://localhost:8888
#   # Tenant-Stack:
#   bash scripts/kc-debug-account-api.sh <tenant-realm> <username> <password> http://<tenant-host>:8888
#
# Note: PASSWORD is the user's own password, not the admin password.

set -euo pipefail

REALM="${1:?Usage: $0 REALM USERNAME PASSWORD [BASE_URL]}"
USERNAME="${2:?missing USERNAME}"
USER_PASSWORD="${3:?missing PASSWORD}"
BASE_URL="${4:-http://localhost:8888}"

ADMIN_TOKEN=$(bash "$(dirname "$0")/kc-token.sh" "$BASE_URL")

echo "=== Step 1: Verify user exists in realm '${REALM}' ==="
USER_JSON=$(curl -sf \
  "${BASE_URL}/auth/admin/realms/${REALM}/users?username=${USERNAME}&exact=true" \
  -H "Authorization: Bearer $ADMIN_TOKEN")
USER_ID=$(echo "$USER_JSON" \
  | python3 -c "import sys,json; u=json.load(sys.stdin); print(u[0]['id']) if u else (print('NOT FOUND'); exit(1))")
echo "  User ID: $USER_ID  ✓"

echo ""
echo "=== Step 2: Check/enable directAccessGrants on 'account-console' client ==="
AC_UUID=$(curl -sf \
  "${BASE_URL}/auth/admin/realms/${REALM}/clients?clientId=account-console&search=false" \
  -H "Authorization: Bearer $ADMIN_TOKEN" \
  | python3 -c "import sys,json; c=json.load(sys.stdin); print(c[0]['id'])") \
  || { echo "  account-console client not found (may be a provider-only realm)"; exit 0; }

ORIG_DAG=$(curl -sf \
  "${BASE_URL}/auth/admin/realms/${REALM}/clients/${AC_UUID}" \
  -H "Authorization: Bearer $ADMIN_TOKEN" \
  | python3 -c "import sys,json; print(json.load(sys.stdin).get('directAccessGrantsEnabled', False))")
echo "  directAccessGrantsEnabled was: $ORIG_DAG"

if [[ "$ORIG_DAG" == "False" ]]; then
  curl -sf -o /dev/null -X PUT \
    "${BASE_URL}/auth/admin/realms/${REALM}/clients/${AC_UUID}" \
    -H "Authorization: Bearer $ADMIN_TOKEN" \
    -H "Content-Type: application/json" \
    -d '{"directAccessGrantsEnabled": true}'
  echo "  Temporarily enabled directAccessGrants  ✓"
fi

restore_dag() {
  if [[ "$ORIG_DAG" == "False" ]]; then
    curl -sf -o /dev/null -X PUT \
      "${BASE_URL}/auth/admin/realms/${REALM}/clients/${AC_UUID}" \
      -H "Authorization: Bearer $ADMIN_TOKEN" \
      -H "Content-Type: application/json" \
      -d '{"directAccessGrantsEnabled": false}'
    echo ""
    echo "  Restored directAccessGrantsEnabled=false"
  fi
}
trap restore_dag EXIT

echo ""
echo "=== Step 3: Obtain user token via account-console client ==="
TOKEN_RESP=$(curl -sf \
  "${BASE_URL}/auth/realms/${REALM}/protocol/openid-connect/token" \
  -d "grant_type=password" \
  -d "client_id=account-console" \
  -d "username=${USERNAME}" \
  -d "password=${USER_PASSWORD}")
USER_TOKEN=$(echo "$TOKEN_RESP" | python3 -c "import sys,json; print(json.load(sys.stdin)['access_token'])")
echo "  Token obtained  ✓"

echo ""
echo "=== Step 4: Decode token audience and realm roles ==="
echo "$USER_TOKEN" | python3 -c "
import sys, json, base64
tok = sys.stdin.read().strip()
payload = tok.split('.')[1]
payload += '=' * (4 - len(payload) % 4)
claims = json.loads(base64.urlsafe_b64decode(payload))
aud = claims.get('aud', [])
roles = claims.get('realm_access', {}).get('roles', [])
client_roles = claims.get('resource_access', {}).get('account', {}).get('roles', [])
print(f'  aud            : {aud}')
print(f'  realm_roles    : {roles}')
print(f'  account roles  : {client_roles}')
print()
has_audience = 'account' in (aud if isinstance(aud, list) else [aud])
has_role = any(r in client_roles for r in ['manage-account', 'view-profile'])
print(f'  aud=account     : {\"✓\" if has_audience else \"✗  MISSING → add account-audience mapper\"}')
print(f'  account role    : {\"✓\" if has_role else \"✗  MISSING → run kc-apply-account-roles.sh\"}')
"

echo ""
echo "=== Step 5: Call Account REST API ==="
HTTP=$(curl -s -o /tmp/kc-debug-account-response.json -w "%{http_code}" \
  "${BASE_URL}/auth/realms/${REALM}/account/?userProfileMetadata=true" \
  -H "Authorization: Bearer $USER_TOKEN")
echo "  HTTP status: $HTTP"
if [[ "$HTTP" == "200" ]]; then
  echo "  ✓ Account API accessible"
else
  echo "  ✗ Unexpected status – response body:"
  cat /tmp/kc-debug-account-response.json
fi
