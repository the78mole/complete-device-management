# cdm-image-rpi4-tpm.bb – CDM minimal image for Raspberry Pi 4 with TPM 2.0

require recipes-core/images/core-image-minimal.bb

DESCRIPTION = "CDM minimal image for Raspberry Pi 4 + Infineon SLB9672 TPM 2.0"

IMAGE_INSTALL += " \
    openssl \
    curl \
    mosquitto-clients \
    bash \
    coreutils \
    tpm2-tools \
    tpm2-tss \
    tpm2-abrmd \
    tpm2-openssl \
    tpm2-pkcs11 \
    libp11 \
    cdm-enroll-tpm \
"

IMAGE_FEATURES += "ssh-server-openssh"
