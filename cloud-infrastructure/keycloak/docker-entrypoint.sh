#!/bin/sh
# docker-entrypoint.sh
#
# Processes ALL *.json.tpl files from the template directory:
# substitutes environment variables and writes ready-to-import JSON files
# into /opt/keycloak/data/import/ before starting Keycloak with --import-realm.
#
# Template files are baked into the image from:
#   keycloak/realms/*.json.tpl  →  /opt/keycloak/data/import-template/
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
      -e "s|\${TB_OIDC_SECRET}|${TB_OIDC_SECRET:-changeme}|g" \
      -e "s|\${GRAFANA_OIDC_SECRET}|${GRAFANA_OIDC_SECRET:-changeme}|g" \
      -e "s|\${HB_OIDC_SECRET}|${HB_OIDC_SECRET:-changeme}|g" \
      -e "s|\${BRIDGE_OIDC_SECRET}|${BRIDGE_OIDC_SECRET:-}|g" \
      -e "s|\${PROVIDER_OPERATOR_PASSWORD}|${PROVIDER_OPERATOR_PASSWORD:-changeme}|g" \
      -e "s|\${TENANT1_ADMIN_PASSWORD}|${TENANT1_ADMIN_PASSWORD:-changeme}|g" \
      -e "s|\${TENANT1_OPERATOR_PASSWORD}|${TENANT1_OPERATOR_PASSWORD:-changeme}|g" \
      -e "s|\${TENANT1_VIEWER_PASSWORD}|${TENANT1_VIEWER_PASSWORD:-changeme}|g" \
      -e "s|\${TENANT2_ADMIN_PASSWORD}|${TENANT2_ADMIN_PASSWORD:-changeme}|g" \
      -e "s|\${TENANT2_OPERATOR_PASSWORD}|${TENANT2_OPERATOR_PASSWORD:-changeme}|g" \
      -e "s|\${TENANT2_VIEWER_PASSWORD}|${TENANT2_VIEWER_PASSWORD:-changeme}|g" \
      "$tpl" > "$dest"

    echo "[entrypoint] prepared realm import: $(basename "$dest")"
done

exec /opt/keycloak/bin/kc.sh "$@"
