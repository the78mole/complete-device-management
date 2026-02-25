# linux-raspberrypi_%.bbappend – applies the CDM TPM kernel config fragment

FILESEXTRAPATHS:prepend := "${THISDIR}/files:"

SRC_URI:append = " file://tpm-spi.cfg"
