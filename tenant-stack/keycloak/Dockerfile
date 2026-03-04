FROM quay.io/keycloak/keycloak:26.5 AS builder

# Build with custom providers if needed in the future
RUN /opt/keycloak/bin/kc.sh build

FROM quay.io/keycloak/keycloak:26.5
COPY --from=builder /opt/keycloak/ /opt/keycloak/

# Store all realm templates in a staging location.
# The entrypoint script substitutes ${VAR} placeholders from the environment
# and writes ready-to-import JSON files before Keycloak starts with --import-realm.
# Add new realms by placing additional *.json.tpl files in keycloak/realms/ and
# rebuilding the image.
COPY realms/ /opt/keycloak/data/import-template/
COPY docker-entrypoint.sh /opt/keycloak/docker-entrypoint.sh

USER root
RUN chmod +x /opt/keycloak/docker-entrypoint.sh
USER keycloak

ENTRYPOINT ["/opt/keycloak/docker-entrypoint.sh"]
CMD ["start-dev", "--import-realm"]
