#!/usr/bin/env bash
# provider-stack/init-openbao.sh
#
# Reads the OpenBao AppRole credentials from the running openbao container and
# writes OPENBAO_STEP_CA_ROLE_ID and OPENBAO_STEP_CA_SECRET_ID into the local
# .env file.
#
# Optionally also writes OPENBAO_ROOT_TOKEN (only needed for manual vault
# operations / initial debugging — not required by any service).
#
# Usage (from provider-stack/):
#   ./init-openbao.sh [--env <path>] [--with-root-token]
#
# Source of credentials (tried in order):
#   1. /openbao/data/step-ca-approle.json  (always present after first start)
#   2. Docker logs (grep for OPENBAO_STEP_CA lines as fallback)
#
# Requires:
#   - Docker + jq
#   - provider-openbao container running and healthy

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="${SCRIPT_DIR}/.env"
CONTAINER="provider-openbao"
APPROLE_FILE="/openbao/data/step-ca-approle.json"
INIT_FILE="/openbao/data/.init.json"
WITH_ROOT_TOKEN=false

# ── Parse arguments ──────────────────────────────────────────────────────────
while [[ $# -gt 0 ]]; do
  case "$1" in
    --env)              ENV_FILE="$2"; shift 2 ;;
    --with-root-token)  WITH_ROOT_TOKEN=true; shift ;;
    *) echo "Unknown argument: $1"; exit 1 ;;
  esac
done

# ── Sanity checks ────────────────────────────────────────────────────────────
if ! docker inspect "$CONTAINER" > /dev/null 2>&1; then
  echo "ERROR: Container '$CONTAINER' not found. Is the stack running?"
  exit 1
fi

if [[ ! -f "$ENV_FILE" ]]; then
  echo "ERROR: .env file not found at: $ENV_FILE"
  echo "       Run 'cp .env.example .env' first."
  exit 1
fi

if ! docker exec "$CONTAINER" which jq > /dev/null 2>&1; then
  echo "ERROR: 'jq' not found inside $CONTAINER."
  exit 1
fi

# ── Read AppRole credentials ─────────────────────────────────────────────────
echo ">>> Reading OpenBao AppRole credentials from $CONTAINER ..."

if docker exec "$CONTAINER" test -f "$APPROLE_FILE" 2>/dev/null; then
  ROLE_ID=$(docker exec "$CONTAINER" jq -r '.role_id' "$APPROLE_FILE")
  SECRET_ID=$(docker exec "$CONTAINER" jq -r '.secret_id' "$APPROLE_FILE")
  echo "    Source: $APPROLE_FILE"
else
  echo "    $APPROLE_FILE not found — falling back to Docker logs ..."
  LOGS=$(docker logs "$CONTAINER" 2>&1)
  ROLE_ID=$(echo "$LOGS" | grep 'OPENBAO_STEP_CA_ROLE_ID' | tail -1 | grep -oE '[0-9a-f-]{36}' | head -1)
  SECRET_ID=$(echo "$LOGS" | grep 'OPENBAO_STEP_CA_SECRET_ID' | tail -1 | grep -oE '[0-9a-f-]{36}' | head -1)
  echo "    Source: container logs"
fi

if [[ -z "$ROLE_ID" || -z "$SECRET_ID" ]]; then
  echo "ERROR: Could not extract AppRole credentials."
  echo "       Ensure OpenBao has completed first-time initialization."
  echo "       Check: docker compose logs openbao | grep 'OPENBAO_STEP_CA'"
  exit 1
fi

echo "    OPENBAO_STEP_CA_ROLE_ID=$ROLE_ID"
echo "    OPENBAO_STEP_CA_SECRET_ID=$SECRET_ID"

# ── Optionally read root token ───────────────────────────────────────────────
ROOT_TOKEN=""
if [[ "$WITH_ROOT_TOKEN" == true ]]; then
  if docker exec "$CONTAINER" test -f "$INIT_FILE" 2>/dev/null; then
    ROOT_TOKEN=$(docker exec "$CONTAINER" jq -r '.root_token' "$INIT_FILE")
    echo "    OPENBAO_ROOT_TOKEN=$ROOT_TOKEN"
  else
    echo "WARNING: $INIT_FILE not found — skipping root token."
  fi
fi

# ── Helper: upsert a key=value in .env ──────────────────────────────────────
upsert_env() {
  local key="$1" value="$2"
  if grep -qE "^${key}=" "$ENV_FILE"; then
    sed -i "s|^${key}=.*|${key}=${value}|" "$ENV_FILE"
    echo "  Updated : ${key}=${value}"
  else
    echo "${key}=${value}" >> "$ENV_FILE"
    echo "  Added   : ${key}=${value}"
  fi
}

# ── Write to .env ─────────────────────────────────────────────────────────────
echo ""
echo ">>> Updating $ENV_FILE ..."
echo ""

upsert_env "OPENBAO_STEP_CA_ROLE_ID"   "$ROLE_ID"
upsert_env "OPENBAO_STEP_CA_SECRET_ID" "$SECRET_ID"

if [[ -n "$ROOT_TOKEN" ]]; then
  upsert_env "OPENBAO_ROOT_TOKEN" "$ROOT_TOKEN"
fi

echo ""
echo ">>> .env updated successfully."
