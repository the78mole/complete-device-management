#!/usr/bin/env bash
# kc-force-logout.sh
#
# Invalidates ALL active Keycloak sessions for one or more users.
# Useful after changing protocol mappers or client roles – the changes only
# take effect when the user obtains a new token (i.e. after re-login).
#
# Usage:
#   bash scripts/kc-force-logout.sh REALM USERNAME [USERNAME …] [-- BASE_URL]
#
# Examples:
#   bash scripts/kc-force-logout.sh tenant1 alice
#   bash scripts/kc-force-logout.sh tenant1 alice bob carol
#   bash scripts/kc-force-logout.sh cdm cdm-admin -- https://host-8888.app.github.dev
#
# Arguments:
#   $1          Realm name
#   $2 … $N    Usernames to log out
#   -- BASE_URL Optional base URL (default: http://localhost:8888)

set -euo pipefail

REALM="${1:?Usage: $0 REALM USERNAME [USERNAME …] [-- BASE_URL]}"
shift

# Parse trailing -- BASE_URL
BASE_URL="http://localhost:8888"
USERNAMES=()
while [[ $# -gt 0 ]]; do
  if [[ "$1" == "--" ]]; then
    shift; BASE_URL="${1:?missing BASE_URL after --}"; shift
  else
    USERNAMES+=("$1"); shift
  fi
done

if [[ ${#USERNAMES[@]} -eq 0 ]]; then
  echo "Error: no usernames provided" >&2; exit 1
fi

TOKEN=$(bash "$(dirname "$0")/kc-token.sh" "$BASE_URL")

for UNAME in "${USERNAMES[@]}"; do
  USER_ID=$(curl -sf \
    "${BASE_URL}/auth/admin/realms/${REALM}/users?username=${UNAME}&exact=true" \
    -H "Authorization: Bearer $TOKEN" \
    | python3 -c "import sys,json; u=json.load(sys.stdin); print(u[0]['id']) if u else exit(1)" \
    2>/dev/null) || { echo "$REALM/$UNAME: user not found"; continue; }

  HTTP=$(curl -s -o /dev/null -w "%{http_code}" \
    -X POST "${BASE_URL}/auth/admin/realms/${REALM}/users/${USER_ID}/logout" \
    -H "Authorization: Bearer $TOKEN")

  echo "$REALM/$UNAME ($USER_ID): logout HTTP $HTTP"
done
