#!/bin/sh
# docker-entrypoint.sh – tenant-stack Keycloak
#
# Processes ALL *.json.tpl files from the template directory:
# substitutes environment variables and writes ready-to-import JSON files
# into /opt/keycloak/data/import/ before starting Keycloak with --import-realm.
#
# Tenant-stack manages one realm:
#   realm-tenant.json.tpl  – tenant device users, all OIDC clients for tenant services
#
# Environment variables consumed by the template:
#   TENANT_ID                  – Keycloak realm name (e.g. "tenant1")
#   TENANT_DISPLAY_NAME        – Human-readable tenant name
#   TENANT_ADMIN_EMAIL         – Admin user e-mail
#   TENANT_ADMIN_PASSWORD      – Admin user password (temporary)
#   TENANT_OPERATOR_EMAIL      – Operator user e-mail
#   TENANT_OPERATOR_PASSWORD   – Operator user password (temporary)
#   TENANT_VIEWER_EMAIL        – Viewer user e-mail
#   TENANT_VIEWER_PASSWORD     – Viewer user password (temporary)
#   GRAFANA_OIDC_SECRET        – Grafana OIDC client secret
#   TB_OIDC_SECRET             – ThingsBoard OIDC client secret
#   HB_OIDC_SECRET             – hawkBit OIDC client secret
#   BRIDGE_OIDC_SECRET         – IoT Bridge API OIDC client secret
#   PORTAL_OIDC_SECRET         – Portal OIDC client secret
#   INFLUX_PROXY_OIDC_SECRET   – InfluxDB proxy OIDC client secret
#   EXTERNAL_URL               – Browser-facing base URL (e.g. http://localhost:8888)
#   TB_EXTERNAL_URL            – ThingsBoard direct URL (e.g. http://localhost:9090)
#
# Adding a new client:
#   1. Add the client block to realms/realm-tenant.json.tpl
#   2. Add a -e substitution line for any new secret placeholder below
#   3. Rebuild:  docker compose build keycloak

set -eu

TEMPLATE_DIR="/opt/keycloak/data/import-template"
IMPORT_DIR="/opt/keycloak/data/import"

mkdir -p "$IMPORT_DIR"

# ── Process every template ───────────────────────────────────────────────────
for tpl in "$TEMPLATE_DIR"/*.json.tpl; do
    [ -f "$tpl" ] || continue

    dest="$IMPORT_DIR/$(basename "${tpl%.tpl}")"

    sed \
      -e "s|\${TENANT_ID}|${TENANT_ID:-tenant}|g" \
      -e "s|\${TENANT_DISPLAY_NAME}|${TENANT_DISPLAY_NAME:-My Tenant}|g" \
      -e "s|\${TENANT_ADMIN_EMAIL}|${TENANT_ADMIN_EMAIL:-admin@tenant.example.com}|g" \
      -e "s|\${TENANT_ADMIN_PASSWORD}|${TENANT_ADMIN_PASSWORD:-changeme}|g" \
      -e "s|\${TENANT_OPERATOR_EMAIL}|${TENANT_OPERATOR_EMAIL:-operator@tenant.example.com}|g" \
      -e "s|\${TENANT_OPERATOR_PASSWORD}|${TENANT_OPERATOR_PASSWORD:-changeme}|g" \
      -e "s|\${TENANT_VIEWER_EMAIL}|${TENANT_VIEWER_EMAIL:-viewer@tenant.example.com}|g" \
      -e "s|\${TENANT_VIEWER_PASSWORD}|${TENANT_VIEWER_PASSWORD:-changeme}|g" \
      -e "s|\${GRAFANA_OIDC_SECRET}|${GRAFANA_OIDC_SECRET:-changeme}|g" \
      -e "s|\${TB_OIDC_SECRET}|${TB_OIDC_SECRET:-changeme}|g" \
      -e "s|\${HB_OIDC_SECRET}|${HB_OIDC_SECRET:-changeme}|g" \
      -e "s|\${BRIDGE_OIDC_SECRET}|${BRIDGE_OIDC_SECRET:-changeme}|g" \
      -e "s|\${PORTAL_OIDC_SECRET}|${PORTAL_OIDC_SECRET:-changeme}|g" \
      -e "s|\${INFLUX_PROXY_OIDC_SECRET}|${INFLUX_PROXY_OIDC_SECRET:-changeme}|g" \
      -e "s|\${EXTERNAL_URL}|${EXTERNAL_URL:-http://localhost:8888}|g" \
      -e "s|\${TB_EXTERNAL_URL}|${TB_EXTERNAL_URL:-http://localhost:9090}|g" \
      "$tpl" > "$dest"

    echo "[entrypoint] prepared realm import: $(basename "$dest")"
done

# ── Post-start patch: add account-audience mapper to tenant realm ─────────────
# Runs as a background process so it doesn't block Keycloak startup.
(
  set +eu

  KCADM="/opt/keycloak/bin/kcadm.sh"
  KCFG="/tmp/kcadm-patch.config"
  KC_USER="${KC_ADMIN_USER:-admin}"
  KC_PASS="${KC_ADMIN_PASSWORD:-changeme}"
  REALM="${TENANT_ID:-tenant}"
  MAPPER_JSON='{"name":"account-audience","protocol":"openid-connect","protocolMapper":"oidc-audience-mapper","consentRequired":false,"config":{"included.client.audience":"account","id.token.claim":"false","access.token.claim":"true"}}'

  # Wait up to 5 minutes for Keycloak Admin API to be ready
  READY=0
  for i in $(seq 1 60); do
    sleep 5
    "$KCADM" config credentials \
      --config "$KCFG" \
      --server http://localhost:8080/auth \
      --realm master \
      --user "$KC_USER" \
      --password "$KC_PASS" >/dev/null 2>&1 && READY=1 && break
  done

  if [ "$READY" != "1" ]; then
    echo "[entrypoint] WARNING: kcadm auth failed – account-audience mapper not applied"
    exit 0
  fi

  for R in master "$REALM"; do
    AC_ID=$("$KCADM" get clients --config "$KCFG" -r "$R" \
      -q clientId=account-console --fields id 2>/dev/null \
      | grep '"id"' | sed 's/.*"id" : "\([^"]*\)".*/\1/')
    [ -z "$AC_ID" ] && continue
    "$KCADM" create "clients/$AC_ID/protocol-mappers/models" \
      --config "$KCFG" -r "$R" -b "$MAPPER_JSON" >/dev/null 2>&1
    echo "[entrypoint] account-audience mapper: realm=$R OK"

    ACCOUNT_CLIENT_ID=$("$KCADM" get clients --config "$KCFG" -r "$R" \
      -q clientId=account --fields id 2>/dev/null \
      | grep '"id"' | sed 's/.*"id" : "\([^"]*\)".*/\1/')
    [ -z "$ACCOUNT_CLIENT_ID" ] && continue

    DEFAULT_ROLE_ID=$("$KCADM" get roles --config "$KCFG" -r "$R" 2>/dev/null \
      | python3 -c "
import sys,json
try:
  roles=json.load(sys.stdin)
  dr=[r for r in roles if r.get('name','').startswith('default-roles-')]
  print(dr[0]['id'] if dr else '')
except: print('')
")
    [ -z "$DEFAULT_ROLE_ID" ] && continue

    for ROLE_NAME in manage-account view-profile; do
      ROLE_JSON=$("$KCADM" get "clients/$ACCOUNT_CLIENT_ID/roles/$ROLE_NAME" \
        --config "$KCFG" -r "$R" 2>/dev/null)
      [ -z "$ROLE_JSON" ] && continue
      "$KCADM" add-roles --config "$KCFG" -r "$R" \
        --rname "default-roles-${R}" \
        --cclientid account \
        --rolename "$ROLE_NAME" >/dev/null 2>&1
    done
    echo "[entrypoint] account default roles: realm=$R OK"
  done
  rm -f "$KCFG"
) &

exec /opt/keycloak/bin/kc.sh "$@"
