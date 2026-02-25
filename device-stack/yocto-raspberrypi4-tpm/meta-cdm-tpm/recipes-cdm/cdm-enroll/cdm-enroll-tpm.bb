# cdm-enroll-tpm.bb – CDM enrollment service recipe (TPM-backed keys)
#
# Installs:
#   /usr/bin/cdm-enroll-tpm.sh        – TPM-backed enrollment script
#   /etc/cdm/enroll.env               – config template
#   /lib/systemd/system/cdm-enroll.service

DESCRIPTION = "CDM TPM-backed device enrollment service"
LICENSE      = "MIT"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/MIT;md5=0835ade698e0bcf8506ecda2f7b4f302"

SRC_URI = " \
    file://cdm-enroll-tpm.sh \
    file://cdm-enroll.service \
    file://cdm-enroll.env \
    file://tpm2-abrmd.service.d-override.conf \
"

inherit systemd

SYSTEMD_SERVICE:${PN} = "cdm-enroll.service"
SYSTEMD_AUTO_ENABLE:${PN} = "enable"

do_install() {
    install -d ${D}${bindir}
    install -m 0755 ${WORKDIR}/cdm-enroll-tpm.sh \
        ${D}${bindir}/cdm-enroll-tpm.sh
    # Symlink so the service unit ExecStart /usr/bin/cdm-enroll.sh works
    ln -sf cdm-enroll-tpm.sh ${D}${bindir}/cdm-enroll.sh

    install -d ${D}/etc/cdm
    install -m 0644 ${WORKDIR}/cdm-enroll.env \
        ${D}/etc/cdm/enroll.env

    install -d ${D}${systemd_system_unitdir}
    install -m 0644 ${WORKDIR}/cdm-enroll.service \
        ${D}${systemd_system_unitdir}/cdm-enroll.service

    # Ensure tpm2-abrmd starts before cdm-enroll
    install -d ${D}${systemd_system_unitdir}/tpm2-abrmd.service.d
    install -m 0644 ${WORKDIR}/tpm2-abrmd.service.d-override.conf \
        ${D}${systemd_system_unitdir}/tpm2-abrmd.service.d/override.conf
}

FILES:${PN} += " \
    /etc/cdm/ \
    ${systemd_system_unitdir}/cdm-enroll.service \
    ${systemd_system_unitdir}/tpm2-abrmd.service.d/ \
"
