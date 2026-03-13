#!/bin/sh
# provider-stack/openbao/entrypoint.sh
#
# Two supported deployment modes (OPENBAO_MODE):
#
#   OPENBAO_MODE=standalone  (default)
#     Single-node OpenBao server with Raft storage.
#     No TPM or external KMS required – unseal key is derived from software only
#     and stored in /openbao/data/.init.json (volume-backed).
#     Auto-init, auto-unseal, and first-time engine/policy configuration are
#     handled here.  Suitable for development, CI, and single-node production.
#     Alias: "embedded" is accepted for backward compatibility.
#
#   OPENBAO_MODE=agent
#     OpenBao Agent proxy that forwards all requests to an external Hub cluster.
#     Use this in production when the Hub runs on hardened infrastructure
#     (HSM, cloud KMS, HA Raft).  The agent handles AppRole auto-auth locally
#     and exposes a transparent listener on :8200 for other containers.
#     Required env vars:
#       OPENBAO_HUB_ADDR          – Hub URL  e.g. https://openbao.infra:8200
#       OPENBAO_APPROLE_ROLE_ID   – AppRole role-id issued by the Hub
#       OPENBAO_APPROLE_SECRET_ID – AppRole secret-id issued by the Hub
#
# See docs/security/hsm-agent-model.md for the Hub-and-Spoke architecture.

set -e

INIT_FILE="/openbao/data/.init.json"
CONFIGURED_FLAG="/openbao/data/.configured"
BAO_LOCAL="http://127.0.0.1:8200"
MODE="${OPENBAO_MODE:-standalone}"
# Accept legacy name for backward compatibility
[ "$MODE" = "embedded" ] && MODE="standalone"

log() { printf '[openbao-entrypoint] %s\n' "$*"; }

# ═══════════════════════════════════════════════════════════════════════════
# MODE: agent  →  Hub-and-Spoke proxy
# ═══════════════════════════════════════════════════════════════════════════
if [ "$MODE" = "agent" ]; then
  HUB_ADDR="${OPENBAO_HUB_ADDR:?ERROR: OPENBAO_HUB_ADDR must be set for agent mode}"
  ROLE_ID="${OPENBAO_APPROLE_ROLE_ID:?ERROR: OPENBAO_APPROLE_ROLE_ID must be set for agent mode}"
  SECRET_ID="${OPENBAO_APPROLE_SECRET_ID:?ERROR: OPENBAO_APPROLE_SECRET_ID must be set for agent mode}"

  ROLE_ID_FILE="/openbao/data/agent-role-id"
  SECRET_ID_FILE="/openbao/data/agent-secret-id"
  AGENT_TOKEN_SINK="/openbao/data/agent-token"
  AGENT_CONFIG="/tmp/bao-agent.hcl"

  # Write credentials to files (agent auto-auth reads from files)
  printf '%s' "$ROLE_ID"  > "$ROLE_ID_FILE"  && chmod 600 "$ROLE_ID_FILE"
  printf '%s' "$SECRET_ID" > "$SECRET_ID_FILE" && chmod 600 "$SECRET_ID_FILE"

  log "Starting OpenBao Agent (hub: $HUB_ADDR) ..."
  cat > "$AGENT_CONFIG" << EOF
pid_file = "/tmp/bao-agent.pid"
exit_after_auth = false

vault {
  address = "${HUB_ADDR}"
}

auto_auth {
  method "approle" {
    config = {
      role_id_file_path              = "${ROLE_ID_FILE}"
      secret_id_file_path            = "${SECRET_ID_FILE}"
      remove_secret_id_file_after_reading = false
    }
  }
  sink "file" {
    config = {
      path = "${AGENT_TOKEN_SINK}"
      mode = 0600
    }
  }
}

cache {
  use_auto_auth_token = true
}

listener "tcp" {
  address     = "0.0.0.0:8200"
  tls_disable = true
}
EOF

  exec bao agent -config="$AGENT_CONFIG"
  # exec replaces the shell – the container exits when the agent exits
fi

# ═══════════════════════════════════════════════════════════════════════════
# MODE: standalone  →  single-node Raft server, no TPM required (default)
# ═══════════════════════════════════════════════════════════════════════════
log "Starting OpenBao server (standalone, no TPM) ..."
bao server -config=/openbao/config/config.hcl &
SERVER_PID=$!

# ── Wait for the server to respond ─────────────────────────────────────────
log "Waiting for OpenBao to accept connections..."
ATTEMPTS=0
while [ "$ATTEMPTS" -lt 60 ]; do
  HTTP_CODE=$(bao status -address="$BAO_LOCAL" -format=json 2>/dev/null | jq -r .initialized 2>/dev/null || true)
  if [ "$HTTP_CODE" = "true" ] || [ "$HTTP_CODE" = "false" ]; then
    log "OpenBao is responding (attempt $((ATTEMPTS + 1)))."
    break
  fi
  sleep 2
  ATTEMPTS=$((ATTEMPTS + 1))
done

# ── Initialize if not already done ─────────────────────────────────────────
INITIALIZED=$(bao status -address="$BAO_LOCAL" -format=json 2>/dev/null | jq -r .initialized 2>/dev/null || echo "false")

if [ "$INITIALIZED" = "false" ]; then
  log "Initializing OpenBao (1 key share, threshold 1) ..."
  bao operator init \
    -address="$BAO_LOCAL" \
    -key-shares=1 \
    -key-threshold=1 \
    -format=json > "$INIT_FILE"
  chmod 600 "$INIT_FILE"
  log "Initialization complete.  Init bundle saved to $INIT_FILE."
fi

# ── Unseal if sealed ────────────────────────────────────────────────────────
SEALED=$(bao status -address="$BAO_LOCAL" -format=json 2>/dev/null | jq -r .sealed 2>/dev/null || echo "true")
if [ "$SEALED" = "true" ]; then
  if [ -f "$INIT_FILE" ]; then
    log "Unsealing OpenBao ..."
    UNSEAL_KEY=$(jq -r '.unseal_keys_b64[0]' < "$INIT_FILE")
    bao operator unseal -address="$BAO_LOCAL" "$UNSEAL_KEY"
    log "Unsealed."
  else
    log "ERROR: OpenBao is sealed but $INIT_FILE is missing. Manual unseal required."
  fi
fi

# ── Export root token for subsequent configuration steps ───────────────────
ROOT_TOKEN=$(jq -r '.root_token' < "$INIT_FILE")
export VAULT_TOKEN="$ROOT_TOKEN"

# ── First-time engine / auth / policy configuration ────────────────────────
if [ ! -f "$CONFIGURED_FLAG" ]; then
  log "Running first-time configuration ..."

  # Transit secrets engine – for key operations (signing, wrapping, HMAC)
  bao secrets enable -address="$BAO_LOCAL" transit \
    || log "transit secrets engine already enabled"

  # Create Transit keys for step-ca PKI (both keys pre-created so step-ca can
  # reference them by name in 'step ca init --root ... --key ...')
  # Root CA key – signs the Intermediate CA cert only (rare operation)
  TRANSIT_KEY="${OPENBAO_TRANSIT_KEY_NAME:-step-ca}"
  bao write -address="$BAO_LOCAL" \
    "transit/keys/${TRANSIT_KEY}" \
    type=ecdsa-p256 \
    exportable=false \
    allow_plaintext_backup=false \
    || log "Transit key '${TRANSIT_KEY}' already exists"

  # Intermediate CA key – signs ALL leaf certs (device, service, Sub-CA)
  TRANSIT_KEY_INT="${OPENBAO_TRANSIT_KEY_INT:-step-ca-int}"
  bao write -address="$BAO_LOCAL" \
    "transit/keys/${TRANSIT_KEY_INT}" \
    type=ecdsa-p256 \
    exportable=false \
    allow_plaintext_backup=false \
    || log "Transit key '${TRANSIT_KEY_INT}' already exists"

  # KV-v2 secrets engine – platform secrets storage
  KV_PATH="${OPENBAO_KV_PATH:-cdm}"
  bao secrets enable -address="$BAO_LOCAL" -path="$KV_PATH" kv-v2 \
    || log "kv-v2 at '$KV_PATH' already enabled"

  # AppRole authentication for machine-to-machine access
  bao auth enable -address="$BAO_LOCAL" approle \
    || log "approle auth already enabled"

  # Policy: step-ca key operations
  bao policy write -address="$BAO_LOCAL" step-ca - << 'POLICY'
# step-ca: use Transit engine for signing / verification operations
path "transit/sign/*" {
  capabilities = ["create", "update"]
}
path "transit/verify/*" {
  capabilities = ["create", "update"]
}
path "transit/keys/*" {
  capabilities = ["create", "read", "update", "list"]
}
# Read / write CDM platform secrets
path "cdm/data/*" {
  capabilities = ["create", "read", "update", "delete"]
}
path "cdm/metadata/*" {
  capabilities = ["list", "read"]
}
POLICY

  # Policy: read-only viewer (for auditing / monitoring)
  bao policy write -address="$BAO_LOCAL" cdm-read-only - << 'POLICY'
path "transit/keys/*" {
  capabilities = ["read", "list"]
}
path "cdm/data/*" {
  capabilities = ["read"]
}
path "cdm/metadata/*" {
  capabilities = ["list", "read"]
}
POLICY

  # AppRole for step-ca service
  bao write -address="$BAO_LOCAL" \
    auth/approle/role/step-ca \
    token_policies="step-ca" \
    token_ttl=87600h \
    token_max_ttl=0 \
    || log "AppRole 'step-ca' already exists"

  # Persist AppRole credentials for step-ca so it can authenticate automatically
  # on first boot without operator intervention ("secret zero" bootstrap).
  # step-ca mounts /openbao/data read-only and reads this file if env vars are unset.
  ROLE_ID=$(bao read -address="$BAO_LOCAL" -format=json auth/approle/role/step-ca/role-id | jq -r .data.role_id)
  SECRET_ID=$(bao write -address="$BAO_LOCAL" -f -format=json auth/approle/role/step-ca/secret-id | jq -r .data.secret_id)

  CREDS_FILE="/openbao/data/step-ca-approle.json"
  printf '{"role_id":"%s","secret_id":"%s"}\n' "$ROLE_ID" "$SECRET_ID" > "$CREDS_FILE"
  chmod 600 "$CREDS_FILE"
  log "AppRole credentials written to ${CREDS_FILE} (auto-read by step-ca on first boot)"

  log "─────────────────────────────────────────────────────────"
  log "AppRole credentials for step-ca (optional override in .env):"
  log "  OPENBAO_STEP_CA_ROLE_ID=${ROLE_ID}"
  log "  OPENBAO_STEP_CA_SECRET_ID=${SECRET_ID}"
  log "Root token (first login only): ${ROOT_TOKEN}"
  log "─────────────────────────────────────────────────────────"

  touch "$CONFIGURED_FLAG"
  log "First-time configuration complete."
else
  log "OpenBao already configured (flag: $CONFIGURED_FLAG)."
fi

log "OpenBao ready at $BAO_LOCAL"
log "Root token stored in $INIT_FILE (first 8 chars: $(jq -r .root_token < "$INIT_FILE" | cut -c1-8)...)"

# ── Wait for the server process ─────────────────────────────────────────────
wait "$SERVER_PID"
