FROM quay.io/keycloak/keycloak:26.5 AS builder

# Build with custom providers if needed in the future
RUN /opt/keycloak/bin/kc.sh build

FROM quay.io/keycloak/keycloak:26.5
COPY --from=builder /opt/keycloak/ /opt/keycloak/

# Store the realm template in a staging location; the entrypoint script will
# run envsubst to substitute OIDC client secrets before Keycloak imports it.
COPY realm-export.json /opt/keycloak/data/import-template/realm-export.json.tpl
COPY docker-entrypoint.sh /opt/keycloak/docker-entrypoint.sh

USER root
RUN chmod +x /opt/keycloak/docker-entrypoint.sh
USER keycloak

ENTRYPOINT ["/opt/keycloak/docker-entrypoint.sh"]
CMD ["start-dev", "--import-realm"]
