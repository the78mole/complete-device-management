#!/usr/bin/env bash
# kc-token.sh – Obtain a short-lived admin token from the master realm.
#
# Usage:
#   TOKEN=$(bash scripts/kc-token.sh)
#   TOKEN=$(bash scripts/kc-token.sh https://my-host-8888.app.github.dev)
#
# Arguments:
#   $1  Base URL of the platform (default: http://localhost:8888)
#
# Requires: curl, python3
# Exit 1 if authentication fails.

set -euo pipefail

BASE_URL="${1:-http://localhost:8888}"
KC_URL="${BASE_URL}/auth"

# Load credentials from .env if available
if [ -f "$(dirname "$0")/../../../cloud-infrastructure/.env" ]; then
  # shellcheck disable=SC1091
  source "$(dirname "$0")/../../../cloud-infrastructure/.env"
fi

KC_ADMIN_USER="${KC_ADMIN_USER:-admin}"
KC_ADMIN_PASSWORD="${KC_ADMIN_PASSWORD:-changeme}"

TOKEN=$(curl -sf \
  -X POST "${KC_URL}/realms/master/protocol/openid-connect/token" \
  -H "Content-Type: application/x-www-form-urlencoded" \
  -d "grant_type=password&client_id=admin-cli" \
  -d "username=${KC_ADMIN_USER}&password=${KC_ADMIN_PASSWORD}" \
  | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('access_token') or (_ for _ in ()).throw(SystemExit('auth failed: '+str(d))))")

echo "$TOKEN"
