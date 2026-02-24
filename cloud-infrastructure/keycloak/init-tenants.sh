#!/usr/bin/env bash
# init-tenants.sh
#
# Post-bootstrap script: grants the provider superadmin (${KC_ADMIN_USER})
# cross-realm administration rights over the tenant realms.
#
# Background
# ──────────
# Keycloak's built-in multi-realm admin model works like this:
#   • The "master" realm contains the global admin account.
#   • For every non-master realm "X", Keycloak auto-creates a master-realm
#     client called "X-realm".  A user in master granted the "realm-admin"
#     role from that client can administer realm X.
#
# This script creates the ${KC_ADMIN_USER} account in the master realm (if it
# does not exist yet) and assigns "realm-admin" on the tenant1-realm and
# tenant2-realm clients.  After this, the provider superadmin can:
#   • Log into /auth/admin/tenant1/console/ with their normal credentials
#   • Log into /auth/admin/tenant2/console/ with their normal credentials
#   • Manage devices, clients, and users of each tenant without sharing the
#     global master-admin password.
#
# Usage
# ──────
#   # From cloud-infrastructure/
#   source .env        # load KC_ADMIN_USER, KC_ADMIN_PASSWORD, EXTERNAL_URL
#   bash keycloak/init-tenants.sh
#
#   # Or override the Keycloak base URL:
#   KEYCLOAK_URL=http://localhost:8888/auth bash keycloak/init-tenants.sh
#
# Requirements: curl, jq

set -euo pipefail

KEYCLOAK_URL="${KEYCLOAK_URL:-http://localhost:8888/auth}"
ADMIN_USER="${KC_ADMIN_USER:-admin}"
ADMIN_PASS="${KC_ADMIN_PASSWORD:-changeme}"
MANAGED_REALMS=("tenant1" "tenant2" "provider")

# ── Helpers ──────────────────────────────────────────────────────────────────

log()  { echo "[init-tenants] $*"; }
die()  { echo "[init-tenants] ERROR: $*" >&2; exit 1; }

wait_for_keycloak() {
    log "Waiting for Keycloak at ${KEYCLOAK_URL} ..."
    local tries=0 max=30
    until curl -sf "${KEYCLOAK_URL}/realms/master" > /dev/null 2>&1; do
        (( tries++ )) || true
        [[ $tries -ge $max ]] && die "Keycloak not reachable after ${max} attempts."
        sleep 3
    done
    log "Keycloak is up."
}

get_admin_token() {
    curl -sf \
        -X POST "${KEYCLOAK_URL}/realms/master/protocol/openid-connect/token" \
        -H "Content-Type: application/x-www-form-urlencoded" \
        -d "grant_type=password" \
        -d "client_id=admin-cli" \
        -d "username=${ADMIN_USER}" \
        -d "password=${ADMIN_PASS}" \
    | jq -r '.access_token'
}

# List all users in master realm with given username
find_master_user() {
    local token="$1" username="$2"
    curl -sf \
        -H "Authorization: Bearer ${token}" \
        "${KEYCLOAK_URL}/admin/realms/master/users?username=${username}&exact=true" \
    | jq -r '.[0].id // empty'
}

# Create user in master realm; return their ID
create_master_user() {
    local token="$1"
    local response
    response=$(curl -sf -w "\n%{http_code}" \
        -X POST "${KEYCLOAK_URL}/admin/realms/master/users" \
        -H "Authorization: Bearer ${token}" \
        -H "Content-Type: application/json" \
        -d "{
            \"username\": \"${ADMIN_USER}\",
            \"email\": \"${ADMIN_USER}@example.com\",
            \"firstName\": \"Platform\",
            \"lastName\": \"Superadmin\",
            \"enabled\": true,
            \"emailVerified\": true,
            \"credentials\": [{
                \"type\": \"password\",
                \"value\": \"${ADMIN_PASS}\",
                \"temporary\": false
            }]
        }")
    local status
    status=$(echo "$response" | tail -1)
    [[ "$status" == "201" ]] || die "Failed to create master user (HTTP $status)"
    find_master_user "$token" "$ADMIN_USER"
}

# Grant a named client role to a user in master realm
grant_client_role() {
    local token="$1" user_id="$2" client_id_str="$3" role_name="$4"

    # Look up internal client UUID
    local client_uuid
    client_uuid=$(curl -sf \
        -H "Authorization: Bearer ${token}" \
        "${KEYCLOAK_URL}/admin/realms/master/clients?clientId=${client_id_str}" \
    | jq -r '.[0].id // empty')
    [[ -n "$client_uuid" ]] || { log "  SKIP: client '${client_id_str}' not found in master"; return; }

    # Look up role representation
    local role_repr
    role_repr=$(curl -sf \
        -H "Authorization: Bearer ${token}" \
        "${KEYCLOAK_URL}/admin/realms/master/clients/${client_uuid}/roles/${role_name}" \
    | jq -c '{ id: .id, name: .name }')
    [[ -n "$role_repr" ]] || { log "  SKIP: role '${role_name}' not found on client '${client_id_str}'"; return; }

    # Assign role
    local status
    status=$(curl -sf -o /dev/null -w "%{http_code}" \
        -X POST \
        "${KEYCLOAK_URL}/admin/realms/master/users/${user_id}/role-mappings/clients/${client_uuid}" \
        -H "Authorization: Bearer ${token}" \
        -H "Content-Type: application/json" \
        -d "[${role_repr}]")

    if [[ "$status" == "204" || "$status" == "409" ]]; then
        log "  ✓ role '${role_name}' on '${client_id_str}' → ${ADMIN_USER}"
    else
        log "  WARN: unexpected HTTP ${status} when granting role '${role_name}' on '${client_id_str}'"
    fi
}

# ── Main ─────────────────────────────────────────────────────────────────────

wait_for_keycloak

log "Obtaining admin token ..."
TOKEN=$(get_admin_token)
[[ -n "$TOKEN" && "$TOKEN" != "null" ]] || die "Could not obtain admin token. Check KC_ADMIN_USER / KC_ADMIN_PASSWORD."

# ── Verify all managed realms are present ────────────────────────────────────
log "Verifying realm imports ..."
for realm in "cdm" "${MANAGED_REALMS[@]}"; do
    status=$(curl -sf -o /dev/null -w "%{http_code}" \
        -H "Authorization: Bearer ${TOKEN}" \
        "${KEYCLOAK_URL}/admin/realms/${realm}" || echo "000")
    if [[ "$status" == "200" ]]; then
        log "  ✓ realm '${realm}' present"
    else
        log "  WARN: realm '${realm}' not found (HTTP ${status}) – it may not have been imported yet"
    fi
done

# ── Ensure ${KC_ADMIN_USER} exists in master realm ───────────────────────────
log "Checking for '${ADMIN_USER}' in master realm ..."

# Refresh token (they expire quickly during long operations)
TOKEN=$(get_admin_token)

MANAGE_USER_ID=$(find_master_user "$TOKEN" "$ADMIN_USER")

if [[ -z "$MANAGE_USER_ID" ]]; then
    log "  Creating '${ADMIN_USER}' in master realm ..."
    MANAGE_USER_ID=$(create_master_user "$TOKEN")
    log "  Created with id: ${MANAGE_USER_ID}"
else
    log "  Already exists with id: ${MANAGE_USER_ID}"
fi

# ── Grant realm-admin on each managed realm ──────────────────────────────────
TOKEN=$(get_admin_token)
log "Granting realm-admin rights to '${ADMIN_USER}' for managed realms ..."
for realm in "${MANAGED_REALMS[@]}"; do
    log "  Processing realm '${realm}' ..."
    grant_client_role "$TOKEN" "$MANAGE_USER_ID" "${realm}-realm" "realm-admin"
done

log ""
log "Done.  '${ADMIN_USER}' can now administer the following realms:"
for realm in "${MANAGED_REALMS[@]}"; do
    log "  ${KEYCLOAK_URL}/admin/${realm}/console/"
done
log ""
log "Note: the master-realm '${ADMIN_USER}' credentials are the same as KC_ADMIN_PASSWORD."
