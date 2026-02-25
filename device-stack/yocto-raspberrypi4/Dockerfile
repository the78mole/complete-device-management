# device-stack/yocto-raspberrypi4/Dockerfile
#
# Yocto/BitBake toolchain image for a Raspberry Pi 4 (64-bit) minimal image.
# All Yocto layer sources (poky, meta-openembedded, meta-raspberrypi) are
# cloned into the image layer so runtime builds need no internet access.
#
# ── Build the toolchain image ONCE ──────────────────────────────────────────
#   docker build -t cdm-yocto-rpi4-builder .
#   (takes ~10 min; clones ~500 MB of Yocto layers)
#
# ── Build the RPi 4 image ────────────────────────────────────────────────────
#   docker run --rm \
#     -v "$(pwd):/workspace" \
#     [-v "$HOME/.yocto/downloads:/yocto/downloads"] \
#     [-v "$HOME/.yocto/sstate-cache:/yocto/sstate-cache"] \
#     cdm-yocto-rpi4-builder
#
#   First build: ~1-3 h, ~50 GB disk.
#   Subsequent builds with sstate-cache: ~10-30 min.
#
# Output on the host:
#   device-stack/yocto-raspberrypi4/deploy/
#     cdm-image-rpi4-raspberrypi4-64.rootfs.wic.bz2   (flashable SD-card image)
#     cdm-image-rpi4-raspberrypi4-64.rootfs.manifest
#
# ── Flash to SD card (on host) ───────────────────────────────────────────────
#   bzip2 -dc deploy/cdm-image-rpi4-*.wic.bz2 | sudo dd of=/dev/sdX bs=4M status=progress

ARG YOCTO_BRANCH=scarthgap

FROM ubuntu:24.04

ARG YOCTO_BRANCH

# ── Yocto host dependency list (Yocto 5.0 / Ubuntu 24.04) ────────────────────
# ref: https://docs.yoctoproject.org/5.0/ref-manual/system-requirements.html
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

# ── Create build user (BitBake refuses to run as root) ───────────────────────
RUN useradd -m -s /bin/bash yocto
WORKDIR /yocto

# ── Clone Yocto layers ────────────────────────────────────────────────────────
# All layers go into /yocto/layers/ so they stay separate from the build dir.
RUN git clone --depth 1 -b ${YOCTO_BRANCH} \
        https://git.yoctoproject.org/poky \
        /yocto/layers/poky \
    && git clone --depth 1 -b ${YOCTO_BRANCH} \
        https://git.openembedded.org/meta-openembedded \
        /yocto/layers/meta-openembedded \
    && git clone --depth 1 -b ${YOCTO_BRANCH} \
        https://git.yoctoproject.org/meta-raspberrypi \
        /yocto/layers/meta-raspberrypi \
    && chown -R yocto:yocto /yocto/layers

ENV YOCTO_BRANCH=${YOCTO_BRANCH}

# Persistent cache directories (mount from host for speed)
VOLUME /yocto/downloads
VOLUME /yocto/sstate-cache

# /workspace is the mounted project directory (read-write, host path)
VOLUME /workspace

COPY docker-entrypoint.sh /usr/local/bin/docker-entrypoint.sh
RUN chmod 755 /usr/local/bin/docker-entrypoint.sh

# BitBake must not run as root
USER yocto

ENTRYPOINT ["/usr/local/bin/docker-entrypoint.sh"]
