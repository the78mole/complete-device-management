FROM smallstep/step-ca:latest

# Copy certificate templates used by provisioners
COPY --chown=step:step templates/ /home/step/templates/

# Copy post-init provisioner bootstrap script
COPY --chown=step:step init-provisioners.sh /usr/local/bin/init-provisioners.sh
RUN chmod +x /usr/local/bin/init-provisioners.sh
