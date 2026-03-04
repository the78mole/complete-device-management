#!/usr/bin/env bash
# kc-show-client-mappers.sh
#
# Lists all protocol mappers registered on a specific Keycloak client.
# Helpful for verifying that expected mappers (e.g. account-audience,
# realm-roles) are present and correctly configured.
#
# Usage:
#   bash scripts/kc-show-client-mappers.sh REALM CLIENT_ID [BASE_URL]
#
# Examples:
#   bash scripts/kc-show-client-mappers.sh cdm grafana
#   bash scripts/kc-show-client-mappers.sh provider account-console http://localhost:8888
#   # Tenant-Stack:
#   bash scripts/kc-show-client-mappers.sh <tenant-realm> account-console http://<tenant-host>:8888

set -euo pipefail

REALM="${1:?Usage: $0 REALM CLIENT_ID [BASE_URL]}"
CLIENT_ID="${2:?missing CLIENT_ID}"
BASE_URL="${3:-http://localhost:8888}"

TOKEN=$(bash "$(dirname "$0")/kc-token.sh" "$BASE_URL")

# Resolve the opaque UUID from the human-readable clientId
CLIENT_UUID=$(curl -sf \
  "${BASE_URL}/auth/admin/realms/${REALM}/clients?clientId=${CLIENT_ID}&search=false" \
  -H "Authorization: Bearer $TOKEN" \
  | python3 -c "import sys,json; c=json.load(sys.stdin); print(c[0]['id']) if c else exit(1)") \
  || { echo "Error: client '${CLIENT_ID}' not found in realm '${REALM}'" >&2; exit 1; }

echo "=== Protocol mappers for ${REALM}/${CLIENT_ID} (UUID: ${CLIENT_UUID}) ==="
curl -sf \
  "${BASE_URL}/auth/admin/realms/${REALM}/clients/${CLIENT_UUID}/protocol-mappers/models" \
  -H "Authorization: Bearer $TOKEN" \
  | python3 -c "
import sys, json
mappers = json.load(sys.stdin)
mappers.sort(key=lambda m: m.get('name',''))
for m in mappers:
    print(f\"  {m['name']:<35} {m['protocolMapper']}\")
    cfg = m.get('config', {})
    for k, v in sorted(cfg.items()):
        print(f\"    {k}: {v}\")
"
