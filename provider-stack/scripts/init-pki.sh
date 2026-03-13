#!/usr/bin/env bash
# provider-stack/init-pki.sh
#
# Runs init-provisioners.sh inside the running step-ca container and writes
# the printed environment variables (STEP_CA_FINGERPRINT, etc.) back into the
# local .env file.
#
# Usage (from provider-stack/):
#   ./init-pki.sh [--env <path>]        # default: .env in same directory
#
# Requires:
#   - Docker (docker exec)
#   - provider-step-ca container running and healthy
#   - bash 4+ and sed (both available in the devcontainer)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="${SCRIPT_DIR}/.env"
CONTAINER="provider-step-ca"
INIT_SCRIPT="/usr/local/bin/init-provisioners.sh"

# ── Parse arguments ──────────────────────────────────────────────────────────
while [[ $# -gt 0 ]]; do
  case "$1" in
    --env) ENV_FILE="$2"; shift 2 ;;
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

echo ">>> Running init-provisioners.sh in $CONTAINER ..."
echo ""

# ── Run the init script and capture & display output simultaneously ──────────
OUTPUT=$(docker exec "$CONTAINER" "$INIT_SCRIPT" 2>&1) || {
  echo "$OUTPUT"
  echo ""
  echo "ERROR: init-provisioners.sh exited with a non-zero status."
  echo "       Check the output above for details."
  exit 1
}

echo "$OUTPUT"
echo ""

# ── Extract KEY=VALUE lines from the summary block ───────────────────────────
# The summary section prints lines like:
#   STEP_CA_FINGERPRINT=<hex>
#   STEP_CA_PROVISIONER_NAME=iot-bridge
#   ...
declare -A PARSED_VARS
while IFS= read -r line; do
  # Match lines of the form "  KEY=VALUE" (leading whitespace allowed)
  if [[ "$line" =~ ^[[:space:]]*(STEP_CA_[A-Z_]+)=(.+)$ ]]; then
    key="${BASH_REMATCH[1]}"
    value="${BASH_REMATCH[2]}"
    PARSED_VARS["$key"]="$value"
  fi
done <<< "$OUTPUT"

if [[ ${#PARSED_VARS[@]} -eq 0 ]]; then
  echo "WARNING: No STEP_CA_* variables found in the script output."
  echo "         The .env file was not modified."
  exit 0
fi

# ── Update .env ──────────────────────────────────────────────────────────────
echo ">>> Updating $ENV_FILE ..."
echo ""

for key in "${!PARSED_VARS[@]}"; do
  value="${PARSED_VARS[$key]}"

  if grep -qE "^${key}=" "$ENV_FILE"; then
    # Replace existing line (handles optional inline comments after the value)
    sed -i "s|^${key}=.*|${key}=${value}|" "$ENV_FILE"
    echo "  Updated : ${key}=${value}"
  else
    # Append new line at end of file
    echo "${key}=${value}" >> "$ENV_FILE"
    echo "  Added   : ${key}=${value}"
  fi
done

echo ""
echo ">>> .env updated successfully."
