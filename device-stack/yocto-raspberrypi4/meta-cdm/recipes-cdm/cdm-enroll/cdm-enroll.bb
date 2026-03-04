# cdm-enroll.bb – CDM enrollment service recipe
#
# Installs:
#   /usr/bin/cdm-enroll.sh        – enrollment script (openssl + curl)
#   /etc/cdm/enroll.env           – environment variable template (MACHINE= persisted here)
#   /lib/systemd/system/cdm-enroll.service – oneshot service, runs once on first boot

DESCRIPTION = "CDM device enrollment service"
LICENSE      = "MIT"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/MIT;md5=0835ade698e0bcf8506ecda2f7b4f302"

SRC_URI = " \
    file://cdm-enroll.sh \
    file://cdm-enroll.service \
    file://cdm-enroll.env \
"

inherit systemd

SYSTEMD_SERVICE:${PN} = "cdm-enroll.service"
SYSTEMD_AUTO_ENABLE:${PN} = "enable"

do_install() {
    install -d ${D}${bindir}
    install -m 0755 ${WORKDIR}/cdm-enroll.sh ${D}${bindir}/cdm-enroll.sh

    install -d ${D}/etc/cdm
    install -m 0644 ${WORKDIR}/cdm-enroll.env ${D}/etc/cdm/enroll.env

    install -d ${D}${systemd_system_unitdir}
    install -m 0644 ${WORKDIR}/cdm-enroll.service \
        ${D}${systemd_system_unitdir}/cdm-enroll.service
}

FILES:${PN} += " \
    /etc/cdm/enroll.env \
    ${systemd_system_unitdir}/cdm-enroll.service \
"
