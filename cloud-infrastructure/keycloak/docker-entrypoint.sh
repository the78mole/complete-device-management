#!/bin/sh
# docker-entrypoint.sh – run envsubst on the realm template so that OIDC
# client secrets injected via Docker environment variables are substituted
# before Keycloak imports the realm on first boot.

set -eu

TEMPLATE="/opt/keycloak/data/import-template/realm-export.json.tpl"
DEST="/opt/keycloak/data/import/realm-export.json"

mkdir -p "$(dirname "$DEST")"

# Substitute only the variables we expect in the template; leave any other
# dollar-sign expressions untouched.
envsubst '${TB_OIDC_SECRET} ${GRAFANA_OIDC_SECRET} ${HB_OIDC_SECRET} ${BRIDGE_OIDC_SECRET}' \
  < "$TEMPLATE" > "$DEST"

exec /opt/keycloak/bin/kc.sh "$@"
