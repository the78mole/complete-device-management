#!/usr/bin/env bash
# kc-apply-account-roles.sh
#
# Grants 'manage-account' and 'view-profile' (account-client roles) to every
# user in one or more realms, and adds them to the 'default-roles-<realm>'
# composite so all FUTURE users automatically have these roles.
#
# Background:
#   Keycloak 26's Account REST API (/auth/realms/<realm>/account/) enforces
#   that the requesting user holds 'manage-account' OR 'view-profile' as a
#   client-role on the built-in 'account' client.  Minimal realm templates
#   created without explicit clientRoles will lack these roles → HTTP 403.
#
# Usage:
#   bash scripts/kc-apply-account-roles.sh [BASE_URL] [REALM …]
#
# Examples:
#   bash scripts/kc-apply-account-roles.sh
#   bash scripts/kc-apply-account-roles.sh http://localhost:8888 cdm provider
#   bash scripts/kc-apply-account-roles.sh https://host-8888.app.github.dev
#   # Tenant-Stack (provide its base URL and realm name explicitly):
#   bash scripts/kc-apply-account-roles.sh http://<tenant-host>:8888 <tenant-realm>
#
# Arguments:
#   $1         Base URL (default: http://localhost:8888)
#   $2 … $N   Realm names (default: master cdm provider)

set -euo pipefail

BASE_URL="${1:-http://localhost:8888}"
shift || true
# Provider-stack manages only 'cdm' and 'provider'.
# Tenant realms live in per-tenant tenant-stack instances (Phase 2).
REALMS="${*:-master cdm provider}"

TOKEN=$(bash "$(dirname "$0")/kc-token.sh" "$BASE_URL")

for REALM in $REALMS; do
  echo "=== $REALM ==="

  # Resolve the built-in 'account' client UUID
  ACC_ID=$(curl -sf \
    "${BASE_URL}/auth/admin/realms/${REALM}/clients?clientId=account" \
    -H "Authorization: Bearer $TOKEN" \
    | python3 -c "import sys,json; c=json.load(sys.stdin); print(c[0]['id']) if c else exit(1)" \
    2>/dev/null) || { echo "  account client not found – skipping"; continue; }

  # Build the JSON array of the two target roles
  ROLES_JSON=$(curl -sf \
    "${BASE_URL}/auth/admin/realms/${REALM}/clients/${ACC_ID}/roles" \
    -H "Authorization: Bearer $TOKEN" \
    | python3 -c "
import sys,json
wanted = ('manage-account','view-profile')
roles = [r for r in json.load(sys.stdin) if r['name'] in wanted]
print(json.dumps(roles))
")

  # 1. Add to default-roles-<realm> composite (new users)
  DR_ID=$(curl -sf "${BASE_URL}/auth/admin/realms/${REALM}/roles" \
    -H "Authorization: Bearer $TOKEN" \
    | python3 -c "
import sys,json
roles=json.load(sys.stdin)
dr=[r for r in roles if r.get('name','').startswith('default-roles-')]
print(dr[0]['id'] if dr else '')
")
  if [ -n "$DR_ID" ]; then
    HTTP=$(curl -s -o /dev/null -w "%{http_code}" \
      -X POST "${BASE_URL}/auth/admin/realms/${REALM}/roles-by-id/${DR_ID}/composites" \
      -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" \
      -d "$ROLES_JSON")
    echo "  default-roles composite: HTTP $HTTP"
  else
    echo "  default-roles not found – skipping composite"
  fi

  # 2. Assign directly to every existing user (immediate effect)
  USER_LIST=$(curl -sf "${BASE_URL}/auth/admin/realms/${REALM}/users?max=500" \
    -H "Authorization: Bearer $TOKEN" \
    | python3 -c "import sys,json; print('\n'.join(u['id']+' '+u['username'] for u in json.load(sys.stdin)))")

  while IFS=' ' read -r USERID UNAME; do
    [ -z "$USERID" ] && continue
    HTTP=$(curl -s -o /dev/null -w "%{http_code}" \
      -X POST "${BASE_URL}/auth/admin/realms/${REALM}/users/${USERID}/role-mappings/clients/${ACC_ID}" \
      -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" \
      -d "$ROLES_JSON")
    echo "  user $UNAME: HTTP $HTTP"
  done <<< "$USER_LIST"
done
