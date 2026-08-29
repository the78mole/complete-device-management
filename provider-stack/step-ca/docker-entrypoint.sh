#!/bin/sh
# provider-stack/step-ca/docker-entrypoint.sh
#
# Replaces the smallstep/step-ca base image entrypoint.
#
# On first boot  → authenticates to OpenBao, then runs `step ca init` using the
#                   OpenBao Transit engine for ALL CA private-key operations.
# On every boot  → authenticates to OpenBao (AppRole), exports VAULT_TOKEN, and
#                   starts the step-ca server (key material never leaves OpenBao).
#
# AppRole credentials (Secret Zero bootstrap):
#   step-ca resolves credentials in this order:
#     1. Env vars OPENBAO_STEP_CA_ROLE_ID + OPENBAO_STEP_CA_SECRET_ID (explicit override)
#     2. /openbao-bootstrap/step-ca-approle.json  <- written by OpenBao on first init
#        (openbao-data volume mounted read-only at /openbao-bootstrap in docker-compose)
#   → No manual operator step required for first-boot authentication.
#
# Other required environment variables (injected by docker-compose):
#   VAULT_ADDR                        – OpenBao address (default: http://openbao:8200)
#   OPENBAO_TRANSIT_KEY_NAME          – Root CA transit key (default: step-ca)
#   OPENBAO_TRANSIT_KEY_INT           – Intermediate CA transit key (default: step-ca-int)
#
# CA bootstrap variables (same names as the base image for compatibility):
#   DOCKER_STEPCA_INIT_NAME           – CA name     (default: CDM Root CA)
#   DOCKER_STEPCA_INIT_DNS_NAMES      – DNS SANs    (default: step-ca,localhost)
#   DOCKER_STEPCA_INIT_ADDRESS        – Listen addr (default: :9000)
#   DOCKER_STEPCA_INIT_PROVISIONER_NAME – Admin provisioner (default: cdm-admin@cdm.local)
#   DOCKER_STEPCA_INIT_PASSWORD_FILE  – Password file path
#   DOCKER_STEPCA_INIT_ACME           – Enable ACME provisioner (default: true)
#   DOCKER_STEPCA_INIT_REMOTE_MANAGEMENT – Enable admin API (default: true)
#   DOCKER_STEPCA_INIT_SSH            – Enable SSH CA (default: false)

set -eu

STEPPATH="${STEPPATH:-/home/step}"
STEP_CA_CONFIG="${STEPPATH}/config/ca.json"

log() { echo "[step-ca] $*"; }
die() { log "ERROR: $*"; exit 1; }

# ── Ensure required directories exist ─────────────────────────────────────────
mkdir -p "${STEPPATH}/config" "${STEPPATH}/certs" "${STEPPATH}/secrets" "${STEPPATH}/db"

# ── 1. Resolve AppRole credentials ───────────────────────────────────────────
# Priority:
#   1. Env vars (OPENBAO_STEP_CA_ROLE_ID / OPENBAO_STEP_CA_SECRET_ID) – explicit override
#   2. Shared bootstrap file written by OpenBao on first init – fully automatic
#      (openbao-data volume mounted read-only at /openbao-bootstrap)
VAULT_ADDR="${VAULT_ADDR:-http://openbao:8200}"
export VAULT_ADDR

BOOTSTRAP_CREDS="/openbao-bootstrap/step-ca-approle.json"

if [ -z "${OPENBAO_STEP_CA_ROLE_ID:-}" ] || [ -z "${OPENBAO_STEP_CA_SECRET_ID:-}" ]; then
  if [ -f "${BOOTSTRAP_CREDS}" ]; then
    log "No AppRole env vars set – loading credentials from ${BOOTSTRAP_CREDS}"
    OPENBAO_STEP_CA_ROLE_ID=$(jq -r .role_id   < "${BOOTSTRAP_CREDS}")
    OPENBAO_STEP_CA_SECRET_ID=$(jq -r .secret_id < "${BOOTSTRAP_CREDS}")
  else
    die "AppRole credentials not found.
         Either set OPENBAO_STEP_CA_ROLE_ID + OPENBAO_STEP_CA_SECRET_ID in .env,
         or ensure the openbao-data volume is mounted at /openbao-bootstrap
         (auto-populated by OpenBao on first boot)."
  fi
fi

log "Authenticating to OpenBao (${VAULT_ADDR}) via AppRole..."
VAULT_TOKEN=$(curl -sf \
    --retry 6 --retry-delay 5 \
    -X POST "${VAULT_ADDR}/v1/auth/approle/login" \
    -H "Content-Type: application/json" \
    -d "{\"role_id\":\"${OPENBAO_STEP_CA_ROLE_ID}\",\"secret_id\":\"${OPENBAO_STEP_CA_SECRET_ID}\"}" \
  | jq -r '.auth.client_token') \
  || die "AppRole login failed – is OpenBao healthy and are the credentials correct?"

export VAULT_TOKEN
log "OpenBao token acquired."

# ── 2. First-time initialization ──────────────────────────────────────────────
if [ ! -f "${STEP_CA_CONFIG}" ]; then
  log "First boot – initializing step-ca with OpenBao Transit KMS..."

  TRANSIT_KEY_ROOT="${OPENBAO_TRANSIT_KEY_NAME:-step-ca}"
  TRANSIT_KEY_INT="${OPENBAO_TRANSIT_KEY_INT:-step-ca-int}"
  CA_NAME="${DOCKER_STEPCA_INIT_NAME:-CDM Root CA}"
  CA_DNS="${DOCKER_STEPCA_INIT_DNS_NAMES:-step-ca,localhost}"
  CA_ADDR="${DOCKER_STEPCA_INIT_ADDRESS:-:9000}"
  CA_PROVISIONER="${DOCKER_STEPCA_INIT_PROVISIONER_NAME:-cdm-admin@cdm.local}"
  CA_PASSWORD_FILE="${DOCKER_STEPCA_INIT_PASSWORD_FILE:-/run/secrets/step-ca-password}"

  log "  Root CA key:         hashivault:${TRANSIT_KEY_ROOT}"
  log "  Intermediate CA key: hashivault:${TRANSIT_KEY_INT}"

  # Build optional flags
  EXTRA_FLAGS=""
  [ "${DOCKER_STEPCA_INIT_ACME:-true}" = "true" ]               && EXTRA_FLAGS="${EXTRA_FLAGS} --acme"
  [ "${DOCKER_STEPCA_INIT_REMOTE_MANAGEMENT:-true}" = "true" ]  && EXTRA_FLAGS="${EXTRA_FLAGS} --remote-management"
  [ "${DOCKER_STEPCA_INIT_SSH:-false}" = "true" ]               && EXTRA_FLAGS="${EXTRA_FLAGS} --ssh"

  # step ca init --kms only supports azurekms (v0.29+).
  # For hashivault KMS, --kms-root / --kms-intermediate accept KMS URIs
  # directly (resolved via step-kms-plugin when present on PATH).
  # shellcheck disable=SC2086
  step ca init \
    --name "${CA_NAME}" \
    --dns "${CA_DNS}" \
    --address "${CA_ADDR}" \
    --provisioner "${CA_PROVISIONER}" \
    --password-file "${CA_PASSWORD_FILE}" \
    --kms-root "hashivault:${TRANSIT_KEY_ROOT}?address=${VAULT_ADDR}" \
    --kms-intermediate "hashivault:${TRANSIT_KEY_INT}?address=${VAULT_ADDR}" \
    ${EXTRA_FLAGS}

  log "step-ca initialization complete."
fi

# ── 3. Print Root CA fingerprint ──────────────────────────────────────────────
if [ -f "${STEPPATH}/certs/root_ca.crt" ]; then
  FINGERPRINT=$(step certificate fingerprint "${STEPPATH}/certs/root_ca.crt")
  log "──────────────────────────────────────────────────────────────────────"
  log "Root CA fingerprint: ${FINGERPRINT}"
  log "Set in provider-stack/.env:"
  log "  STEP_CA_FINGERPRINT=${FINGERPRINT}"
  log "──────────────────────────────────────────────────────────────────────"
fi

# ── 4. Start step-ca server (background for provisioner setup) ────────────────
# VAULT_TOKEN is exported – step-kms-plugin inherits it for all signing ops.
# --password-file is required when software keys are used (needed to decrypt
# the intermediate CA key at startup). It is also harmless when the KMS is
# fully Vault-backed (the file will simply not be read in that case).
CA_PASSWORD_FILE="${DOCKER_STEPCA_INIT_PASSWORD_FILE:-/run/secrets/step-ca-password}"
log "Starting step-ca server (background)..."
step-ca "${STEP_CA_CONFIG}" --password-file "${CA_PASSWORD_FILE}" &
STEP_CA_PID=$!

# ── 5. Wait for step-ca to be healthy ─────────────────────────────────────────
log "Waiting for step-ca to be ready..."
i=0
while [ $i -lt 30 ]; do
  if step ca health --ca-url "https://localhost:9000" > /dev/null 2>&1; then
    log "step-ca is ready."
    break
  fi
  sleep 2
  i=$((i + 1))
done

# ── 6. Ensure all JWK provisioners exist (idempotent) ─────────────────────────
log "Running provisioner init script..."
/usr/local/bin/init-provisioners.sh || log "WARNING: init-provisioners.sh failed – check logs above."

# ── 7. Hand off to foreground step-ca process ─────────────────────────────────
log "Provisioner setup complete. Waiting for step-ca (PID ${STEP_CA_PID})..."
wait ${STEP_CA_PID}
