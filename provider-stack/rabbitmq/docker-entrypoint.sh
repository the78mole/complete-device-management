#!/bin/sh
# docker-entrypoint.sh – CDM provider-stack RabbitMQ wrapper
#
# Generates /etc/rabbitmq/advanced.config from the mounted template by
# substituting the two runtime secrets, then hands off to the official
# RabbitMQ docker-entrypoint.sh.
#
# Placeholders (set via docker-compose environment:):
#   RABBITMQ_MANAGEMENT_OIDC_SECRET  – OAuth2 client secret for Keycloak
#   EXTERNAL_URL                     – Browser-facing base URL (for auth redirect)
#   RABBITMQ_ADMIN_USER              – Admin username
#   RABBITMQ_ADMIN_PASSWORD          – Admin plaintext password (hashed by RabbitMQ on import)

set -e

TPL="/etc/rabbitmq/advanced.config.tpl"
OUT="/etc/rabbitmq/advanced.config"

if [ -f "$TPL" ]; then
    sed \
        -e "s|RABBITMQ_MANAGEMENT_OIDC_SECRET_PLACEHOLDER|${RABBITMQ_MANAGEMENT_OIDC_SECRET:-changeme}|g" \
        -e "s|EXTERNAL_URL_PLACEHOLDER|${EXTERNAL_URL:-http://localhost:8888}|g" \
        "$TPL" > "$OUT"
    echo "[cdm-entrypoint] advanced.config written (oauth2 client configured)"
else
    echo "[cdm-entrypoint] WARNING: $TPL not found – skipping advanced.config generation"
fi

DEF_TPL="/etc/rabbitmq/definitions.json.tpl"
DEF_OUT="/etc/rabbitmq/definitions.json"

if [ -f "$DEF_TPL" ]; then
    sed \
        -e "s|RABBITMQ_ADMIN_USER_PLACEHOLDER|${RABBITMQ_DEFAULT_USER:-admin}|g" \
        -e "s|RABBITMQ_ADMIN_PASSWORD_PLACEHOLDER|${RABBITMQ_DEFAULT_PASS:-changeme}|g" \
        "$DEF_TPL" > "$DEF_OUT"
    echo "[cdm-entrypoint] definitions.json written (admin user: ${RABBITMQ_DEFAULT_USER:-admin})"
else
    echo "[cdm-entrypoint] WARNING: $DEF_TPL not found – skipping definitions.json generation"
fi

# Delegate to the official RabbitMQ entrypoint (handles node name, cookie, etc.)
exec /usr/local/bin/docker-entrypoint.sh "$@"
