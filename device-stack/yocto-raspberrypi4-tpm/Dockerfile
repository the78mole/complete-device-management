# device-stack/yocto-raspberrypi4-tpm/Dockerfile
#
# Yocto/BitBake toolchain image for Raspberry Pi 4 + Infineon SLB9672 TPM 2.0.
# Extends the base RPi 4 image with meta-security (tpm2-tools, tpm2-tss,
# tpm2-pkcs11, tpm2-openssl) and a TPM SPI kernel config fragment.
#
# ── Build the toolchain image ONCE ──────────────────────────────────────────
#   docker build -t cdm-yocto-rpi4-tpm-builder .
#
# ── Build the RPi 4 TPM image ────────────────────────────────────────────────
#   docker run --rm \
#     -v "$(pwd):/workspace" \
#     [-v "$HOME/.yocto/downloads:/yocto/downloads"] \
#     [-v "$HOME/.yocto/sstate-cache:/yocto/sstate-cache"] \
#     cdm-yocto-rpi4-tpm-builder
#
# Output on the host:
#   deploy/cdm-image-rpi4-tpm-raspberrypi4-64.rootfs.wic.bz2
#
# ── Hardware wiring (SLB9672 → RPi 4 GPIO header) ────────────────────────────
#   SLB9672 pin  │ RPi4 pin   │ Signal
#   ─────────────┼────────────┼────────
#   VCC  (3.3 V) │ pin  1 (3.3V) │ power
#   GND          │ pin  6 (GND)  │ ground
#   MOSI  (SDI)  │ pin 19 (GPIO10 / SPI0_MOSI)
#   MISO  (SDO)  │ pin 21 (GPIO9  / SPI0_MISO)
#   SCLK         │ pin 23 (GPIO11 / SPI0_SCLK)
#   CS           │ pin 26 (GPIO7  / SPI0_CE1) or pin 24 (SPI0_CE0)
#   RST (opt.)   │ free GPIO
#
# The device tree overlay `tpm-slb9670` covers the SLB967x family incl. SLB9672.

ARG YOCTO_BRANCH=scarthgap

FROM ubuntu:24.04

ARG YOCTO_BRANCH

# Yocto host dependencies (Ubuntu 24.04)
RUN apt-get update && apt-get install -y --no-install-recommends \
        bzip2 \
        ca-certificates \
        chrpath \
        cpio \
        curl \
        debianutils \
        diffstat \
        file \
        g++ \
        gawk \
        gcc \
        git \
        git-lfs \
        iputils-ping \
        libegl1-mesa \
        libglib2.0-dev \
        liblz4-tool \
        libsdl1.2-dev \
        libssl-dev \
        locales \
        lz4 \
        make \
        mesa-common-dev \
        patch \
        python3 \
        python3-git \
        python3-jinja2 \
        python3-pexpect \
        python3-pip \
        python3-subunit \
        socat \
        texinfo \
        unzip \
        wget \
        xterm \
        xz-utils \
        zstd \
    && locale-gen en_US.UTF-8 \
    && rm -rf /var/lib/apt/lists/*

ENV LANG=en_US.UTF-8 \
    LC_ALL=en_US.UTF-8

RUN useradd -m -s /bin/bash yocto
WORKDIR /yocto

# Clone Yocto layers (including meta-security for TPM support)
RUN git clone --depth 1 -b ${YOCTO_BRANCH} \
        https://git.yoctoproject.org/poky \
        /yocto/layers/poky \
    && git clone --depth 1 -b ${YOCTO_BRANCH} \
        https://git.openembedded.org/meta-openembedded \
        /yocto/layers/meta-openembedded \
    && git clone --depth 1 -b ${YOCTO_BRANCH} \
        https://git.yoctoproject.org/meta-raspberrypi \
        /yocto/layers/meta-raspberrypi \
    && git clone --depth 1 -b ${YOCTO_BRANCH} \
        https://git.yoctoproject.org/meta-security \
        /yocto/layers/meta-security \
    && chown -R yocto:yocto /yocto/layers

ENV YOCTO_BRANCH=${YOCTO_BRANCH}

VOLUME /yocto/downloads
VOLUME /yocto/sstate-cache
VOLUME /workspace

COPY docker-entrypoint.sh /usr/local/bin/docker-entrypoint.sh
RUN chmod 755 /usr/local/bin/docker-entrypoint.sh

USER yocto

ENTRYPOINT ["/usr/local/bin/docker-entrypoint.sh"]
