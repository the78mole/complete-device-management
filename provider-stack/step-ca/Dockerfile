FROM smallstep/step-ca:latest

# Build context: repo root (set in docker-compose.yml)
# Copy shared leaf templates from cloud-infrastructure, then provider-specific templates on top
COPY --chown=step:step cloud-infrastructure/step-ca/templates/ /home/step/templates/
COPY --chown=step:step provider-stack/step-ca/templates/ /home/step/templates/

# Copy consolidated init script that adds both leaf-cert AND sub-CA provisioners
COPY --chown=step:step provider-stack/step-ca/init-provisioners.sh /usr/local/bin/init-provisioners.sh
RUN chmod +x /usr/local/bin/init-provisioners.sh
