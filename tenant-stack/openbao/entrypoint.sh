#!/bin/sh
# tenant-stack/openbao/entrypoint.sh
#
# Supports two deployment modes controlled by OPENBAO_MODE:
#
#   OPENBAO_MODE=embedded  (default)
#     Starts an embedded single-node OpenBao server for the code-signing profile.
#     Handles first-time init, auto-unseal, Transit key, KV-v2, and AppRole setup.
#     Suitable for development, single-tenant production, and testing.
#     The unseal key and root token are stored in /openbao/data/.init.json.
#
#   OPENBAO_MODE=agent
#     Runs an OpenBao Agent that proxies code-signing requests to an external Hub.
#     Required env vars:
#       OPENBAO_HUB_ADDR          – URL of the Hub  e.g. https://openbao.infra:8200
#       OPENBAO_APPROLE_ROLE_ID   – AppRole role-id for the code-signing policy on the Hub
#       OPENBAO_APPROLE_SECRET_ID – AppRole secret-id
#     The Hub must have Transit key 'code-signing' and KV-v2 mount 'code-signing/' ready.
#
# See docs/security/hsm-agent-model.md for production Hub-and-Spoke setup.

set -e

INIT_FILE="/openbao/data/.init.json"
CONFIGURED_FLAG="/openbao/data/.configured"
BAO_LOCAL="http://127.0.0.1:8200"
MODE="${OPENBAO_MODE:-embedded}"

log() { printf '[openbao-entrypoint] %s\n' "$*"; }

# ═══════════════════════════════════════════════════════════════════════════
# MODE: agent  →  Hub proxy (production)
# ═══════════════════════════════════════════════════════════════════════════
if [ "$MODE" = "agent" ]; then
  HUB_ADDR="${OPENBAO_HUB_ADDR:?ERROR: OPENBAO_HUB_ADDR must be set for agent mode}"
  ROLE_ID="${OPENBAO_APPROLE_ROLE_ID:?ERROR: OPENBAO_APPROLE_ROLE_ID must be set for agent mode}"
  SECRET_ID="${OPENBAO_APPROLE_SECRET_ID:?ERROR: OPENBAO_APPROLE_SECRET_ID must be set for agent mode}"

  ROLE_ID_FILE="/openbao/data/agent-role-id"
  SECRET_ID_FILE="/openbao/data/agent-secret-id"
  AGENT_TOKEN_SINK="/openbao/data/agent-token"
  AGENT_CONFIG="/tmp/bao-agent.hcl"
  CREDS_DIR="${OPENBAO_CREDS_DIR:-/openbao/creds}"

  printf '%s' "$ROLE_ID"  > "$ROLE_ID_FILE"  && chmod 600 "$ROLE_ID_FILE"
  printf '%s' "$SECRET_ID" > "$SECRET_ID_FILE" && chmod 600 "$SECRET_ID_FILE"

  # In agent mode the cert-init sidecar needs a token it can use for cert-writer.
  # We re-use the agent token sink path as the cert-writer credential so that
  # cert-init can authenticate with the same AppRole.
  mkdir -p "$CREDS_DIR"
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

  log "Starting OpenBao Agent (hub: $HUB_ADDR) ..."
  exec bao agent -config="$AGENT_CONFIG"
fi

# ═══════════════════════════════════════════════════════════════════════════
# MODE: embedded  →  single-node Raft server (default, development)
# ═══════════════════════════════════════════════════════════════════════════
log "Starting OpenBao server (tenant code-signing, mode: embedded)..."
bao server -config=/openbao/config/config.hcl &
SERVER_PID=$!

# ── Wait for the server to respond ─────────────────────────────────────────
log "Waiting for OpenBao to accept connections..."
ATTEMPTS=0
while [ "$ATTEMPTS" -lt 60 ]; do
  STATUS=$(bao status -address="$BAO_LOCAL" -format=json 2>/dev/null | jq -r .initialized 2>/dev/null || true)
  if [ "$STATUS" = "true" ] || [ "$STATUS" = "false" ]; then
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

# ── Export root token ──────────────────────────────────────────────────────
ROOT_TOKEN=$(jq -r '.root_token' < "$INIT_FILE")
export VAULT_TOKEN="$ROOT_TOKEN"

# ── First-time engine / auth / policy configuration ────────────────────────
if [ ! -f "$CONFIGURED_FLAG" ]; then
  log "Running first-time configuration for code-signing ..."

  # Transit secrets engine
  bao secrets enable -address="$BAO_LOCAL" transit \
    || log "transit already enabled"

  # Code-signing Transit key (ECDSA P-384 = strong, RAUC-compatible)
  # exportable=false ensures the private key never leaves OpenBao
  TRANSIT_KEY="${OPENBAO_CODESIGN_KEY_NAME:-code-signing}"
  bao write -address="$BAO_LOCAL" \
    "transit/keys/${TRANSIT_KEY}" \
    type=ecdsa-p384 \
    exportable=false \
    allow_plaintext_backup=false \
    || log "Transit key '${TRANSIT_KEY}' already exists"

  # KV-v2 engine for storing the code-signing certificate issued by step-ca
  KV_PATH="${OPENBAO_KV_PATH:-code-signing}"
  bao secrets enable -address="$BAO_LOCAL" -path="$KV_PATH" kv-v2 \
    || log "kv-v2 at '$KV_PATH' already enabled"

  # AppRole authentication for CI/CD pipelines
  bao auth enable -address="$BAO_LOCAL" approle \
    || log "approle already enabled"

  # Policy: CI/CD pipeline – sign artifacts and read the cert
  bao policy write -address="$BAO_LOCAL" code-signer - << 'POLICY'
# Perform signing operations via the Transit engine
path "transit/sign/*" {
  capabilities = ["create", "update"]
}
path "transit/verify/*" {
  capabilities = ["create", "update"]
}
# Read the public key / key metadata
path "transit/keys/*" {
  capabilities = ["read", "list"]
}
# Read the code-signing certificate stored by openbao-cert-init
path "code-signing/data/*" {
  capabilities = ["read"]
}
path "code-signing/metadata/*" {
  capabilities = ["list", "read"]
}
POLICY

  # Policy: cert-init – write the certificate issued by step-ca
  bao policy write -address="$BAO_LOCAL" cert-writer - << 'POLICY'
path "code-signing/data/*" {
  capabilities = ["create", "update"]
}
path "code-signing/metadata/*" {
  capabilities = ["list", "read"]
}
POLICY

  # AppRole for CI/CD pipelines (code signing)
  bao write -address="$BAO_LOCAL" \
    auth/approle/role/code-signer \
    token_policies="code-signer" \
    token_ttl=1h \
    token_max_ttl=8h \
    || log "AppRole 'code-signer' already exists"

  # AppRole for cert-init sidecar (write code-signing cert once)
  bao write -address="$BAO_LOCAL" \
    auth/approle/role/cert-writer \
    token_policies="cert-writer" \
    token_ttl=30m \
    token_max_ttl=1h \
    token_num_uses=5 \
    || log "AppRole 'cert-writer' already exists"

  # Display credentials
  CS_ROLE_ID=$(bao read -address="$BAO_LOCAL" -format=json auth/approle/role/code-signer/role-id | jq -r .data.role_id)
  CS_SECRET_ID=$(bao write -address="$BAO_LOCAL" -f -format=json auth/approle/role/code-signer/secret-id | jq -r .data.secret_id)
  CW_ROLE_ID=$(bao read -address="$BAO_LOCAL" -format=json auth/approle/role/cert-writer/role-id | jq -r .data.role_id)
  CW_SECRET_ID=$(bao write -address="$BAO_LOCAL" -f -format=json auth/approle/role/cert-writer/secret-id | jq -r .data.secret_id)

  # Write cert-writer credentials to a shared volume so cert-init can use them
  CREDS_DIR="${OPENBAO_CREDS_DIR:-/openbao/creds}"
  mkdir -p "$CREDS_DIR"
  printf '%s' "$CW_ROLE_ID"   > "$CREDS_DIR/cert-writer-role-id"
  printf '%s' "$CW_SECRET_ID" > "$CREDS_DIR/cert-writer-secret-id"
  chmod 600 "$CREDS_DIR/cert-writer-role-id" "$CREDS_DIR/cert-writer-secret-id"

  log "─────────────────────────────────────────────────────────"
  log "AppRole credentials for CI/CD code-signer:"
  log "  OPENBAO_CODESIGN_ROLE_ID=${CS_ROLE_ID}"
  log "  OPENBAO_CODESIGN_SECRET_ID=${CS_SECRET_ID}"
  log "Root token (first login only): ${ROOT_TOKEN}"
  log "─────────────────────────────────────────────────────────"

  touch "$CONFIGURED_FLAG"
  log "First-time configuration complete."
else
  log "OpenBao already configured (flag: $CONFIGURED_FLAG)."

  # Always refresh the cert-writer credentials so the cert-init sidecar can run
  # after a restart with a fresh secret-id (single-use tokens expire).
  CREDS_DIR="${OPENBAO_CREDS_DIR:-/openbao/creds}"
  mkdir -p "$CREDS_DIR"
  if bao list -address="$BAO_LOCAL" auth/approle/role 2>/dev/null | grep -q cert-writer; then
    CW_ROLE_ID=$(bao read -address="$BAO_LOCAL" -format=json auth/approle/role/cert-writer/role-id | jq -r .data.role_id)
    CW_SECRET_ID=$(bao write -address="$BAO_LOCAL" -f -format=json auth/approle/role/cert-writer/secret-id | jq -r .data.secret_id)
    printf '%s' "$CW_ROLE_ID"   > "$CREDS_DIR/cert-writer-role-id"
    printf '%s' "$CW_SECRET_ID" > "$CREDS_DIR/cert-writer-secret-id"
    chmod 600 "$CREDS_DIR/cert-writer-role-id" "$CREDS_DIR/cert-writer-secret-id"
    log "Refreshed cert-writer credentials in $CREDS_DIR."
  fi
fi

log "OpenBao (code-signing) ready at $BAO_LOCAL"

# ── Wait for the server process ─────────────────────────────────────────────
wait "$SERVER_PID"
