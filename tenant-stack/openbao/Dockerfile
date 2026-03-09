FROM openbao/openbao:latest

# jq is required by the entrypoint for JSON parsing of init data
USER root
RUN apk add --no-cache jq \
 && mkdir -p /openbao/data \
 && chown openbao:openbao /openbao/data

# Auto-init / auto-unseal / code-signing configuration entrypoint
COPY --chmod=0755 entrypoint.sh /entrypoint.sh

USER openbao

ENTRYPOINT ["/entrypoint.sh"]
CMD ["server", "-config=/openbao/config/config.hcl"]
