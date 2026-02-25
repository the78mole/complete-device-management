FROM smallstep/step-ca:latest

# Build context: repo root (set in docker-compose.yml)
# Copy all step-ca certificate templates (leaf certs + sub-CA signer template)
COPY --chown=step:step provider-stack/step-ca/templates/ /home/step/templates/

# Copy consolidated init script that adds both leaf-cert AND sub-CA provisioners
COPY --chown=step:step provider-stack/step-ca/init-provisioners.sh /usr/local/bin/init-provisioners.sh
RUN chmod +x /usr/local/bin/init-provisioners.sh
