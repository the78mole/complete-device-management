FROM smallstep/step-ca:latest

# Copy certificate templates for IoT device leaf certs and service certs
COPY --chown=step:step templates/ /home/step/templates/

# Copy the provisioner-init script (run once after first start)
COPY --chown=step:step init-sub-ca.sh /usr/local/bin/init-sub-ca.sh
RUN chmod +x /usr/local/bin/init-sub-ca.sh
