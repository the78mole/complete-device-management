#!/bin/sh
# docker-entrypoint.sh – provider-stack Keycloak
#
# Processes ALL *.json.tpl files from the template directory:
# substitutes environment variables and writes ready-to-import JSON files
# into /opt/keycloak/data/import/ before starting Keycloak with --import-realm.
#
# Provider-stack manages two realms only:
#   realm-cdm.json.tpl      – platform users, Grafana/IoT-Bridge/Portal/influxdb-proxy clients
#   realm-provider.json.tpl – platform operations staff (platform-admin, platform-operator)
#
# Adding a new realm:
#   1. Place realm-<name>.json.tpl into keycloak/realms/ (host side)
#   2. Use ${VAR_NAME} placeholders for any secret that must come from env
#   3. Add the matching sed line below
#   4. Rebuild the image  (docker compose build keycloak)

set -eu

TEMPLATE_DIR="/opt/keycloak/data/import-template"
IMPORT_DIR="/opt/keycloak/data/import"

mkdir -p "$IMPORT_DIR"

# ── Process every template ───────────────────────────────────────────────────
for tpl in "$TEMPLATE_DIR"/*.json.tpl; do
    [ -f "$tpl" ] || continue

    dest="$IMPORT_DIR/$(basename "${tpl%.tpl}")"

    # Substitute all known environment variables.
    # Add new -e lines here whenever a new ${VAR} placeholder is introduced.
    sed \
      -e "s|\${KC_ADMIN_USER}|${KC_ADMIN_USER:-admin}|g" \
      -e "s|\${KC_ADMIN_PASSWORD}|${KC_ADMIN_PASSWORD:-changeme}|g" \
      -e "s|\${GRAFANA_OIDC_SECRET}|${GRAFANA_OIDC_SECRET:-changeme}|g" \
      -e "s|\${GRAFANA_BROKER_SECRET}|${GRAFANA_BROKER_SECRET:-changeme}|g" \
      -e "s|\${BRIDGE_OIDC_SECRET}|${BRIDGE_OIDC_SECRET:-}|g" \
      -e "s|\${PORTAL_OIDC_SECRET}|${PORTAL_OIDC_SECRET:-changeme}|g" \
      -e "s|\${INFLUX_PROXY_OIDC_SECRET}|${INFLUX_PROXY_OIDC_SECRET:-changeme}|g" \
      -e "s|\${PROVIDER_OPERATOR_PASSWORD}|${PROVIDER_OPERATOR_PASSWORD:-changeme}|g" \
      -e "s|\${EXTERNAL_URL}|${EXTERNAL_URL:-http://localhost:8888}|g" \
      "$tpl" > "$dest"

    echo "[entrypoint] prepared realm import: $(basename "$dest")"
done

# ── Post-start patch: add account-audience mapper to every realm ─────────────
# Runs as a background process so it doesn't block Keycloak startup.
# The mapper is not injectable via import JSON (system clients cause duplicate-
# key errors), so we apply it via kcadm.sh once KC is ready.
(
  set +eu  # reset inherited errexit/nounset – failures in the retry loop are expected

  KCADM="/opt/keycloak/bin/kcadm.sh"
  KCFG="/tmp/kcadm-patch.config"
  KC_USER="${KC_ADMIN_USER:-admin}"
  KC_PASS="${KC_ADMIN_PASSWORD:-changeme}"
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

  for REALM in master cdm provider; do
    AC_ID=$("$KCADM" get clients --config "$KCFG" -r "$REALM" \
      -q clientId=account-console --fields id 2>/dev/null \
      | grep '"id"' | sed 's/.*"id" : "\([^"]*\)".*/\1/')
    [ -z "$AC_ID" ] && continue
    "$KCADM" create "clients/$AC_ID/protocol-mappers/models" \
      --config "$KCFG" -r "$REALM" -b "$MAPPER_JSON" >/dev/null 2>&1
    echo "[entrypoint] account-audience mapper: realm=$REALM OK"

    # Add manage-account + view-profile to default-roles-{realm} composite
    ACCOUNT_CLIENT_ID=$("$KCADM" get clients --config "$KCFG" -r "$REALM" \
      -q clientId=account --fields id 2>/dev/null \
      | grep '"id"' | sed 's/.*"id" : "\([^"]*\)".*/\1/')
    [ -z "$ACCOUNT_CLIENT_ID" ] && continue

    DEFAULT_ROLE_ID=$("$KCADM" get roles --config "$KCFG" -r "$REALM" 2>/dev/null \
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
        --config "$KCFG" -r "$REALM" 2>/dev/null)
      [ -z "$ROLE_JSON" ] && continue
      "$KCADM" add-roles --config "$KCFG" -r "$REALM" \
        --rname "default-roles-${REALM}" \
        --cclientid account \
        --rolename "$ROLE_NAME" >/dev/null 2>&1
    done
    echo "[entrypoint] account default roles: realm=$REALM OK"
  done
  rm -f "$KCFG"
) &

exec /opt/keycloak/bin/kc.sh "$@"
