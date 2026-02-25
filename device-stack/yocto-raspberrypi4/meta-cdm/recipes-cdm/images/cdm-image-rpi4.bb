# cdm-image-rpi4.bb – CDM minimal image for Raspberry Pi 4
#
# Extends core-image-minimal with CDM enrollment and mTLS MQTT packages.

require recipes-core/images/core-image-minimal.bb

DESCRIPTION = "CDM minimal image for Raspberry Pi 4 – enrollment + mTLS MQTT"

IMAGE_INSTALL += " \
    openssl \
    curl \
    mosquitto-clients \
    bash \
    coreutils \
    cdm-enroll \
"

IMAGE_FEATURES += "ssh-server-openssh"
