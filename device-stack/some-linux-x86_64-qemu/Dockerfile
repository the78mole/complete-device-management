# device-stack/some-linux-x86_64-qemu/Dockerfile
#
# Buildroot host toolchain image.  The build is driven at *runtime* by mounting
# the current source directory into the container, so artefacts land directly
# on the host filesystem instead of being buried inside an image layer.
#
# ── Build the toolchain image ONCE ──────────────────────────────────────────
#   docker build -t cdm-qemu-builder .
#
# ── Build the QEMU device image ─────────────────────────────────────────────
#   docker run --rm -v "$(pwd):/workspace" cdm-qemu-builder
#
# Output on the host:
#   device-stack/some-linux-x86_64-qemu/deploy/bzImage
#   device-stack/some-linux-x86_64-qemu/deploy/rootfs.cpio.gz
#
# ── Run the built image natively ────────────────────────────────────────────
#   BRIDGE_API_URL=http://... THINGSBOARD_HOST=... ./run-qemu.sh

ARG BUILDROOT_VERSION=2024.02.7

FROM debian:12-slim

ARG BUILDROOT_VERSION

# Buildroot host dependency list (from Buildroot manual §2.1)
RUN apt-get update && apt-get install -y --no-install-recommends \
        bc \
        binutils \
        bzip2 \
        ca-certificates \
        cpio \
        curl \
        file \
        g++ \
        gcc \
        git \
        gzip \
        libncurses-dev \
        make \
        patch \
        perl \
        python3 \
        rsync \
        sed \
        tar \
        unzip \
        wget \
        xz-utils \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /build

# Pre-download Buildroot into the image layer so subsequent build runs
# (docker run ...) don't need to re-fetch the tarball.
RUN echo ">>> Downloading Buildroot ${BUILDROOT_VERSION} ..." \
    && curl -fL \
        "https://buildroot.org/downloads/buildroot-${BUILDROOT_VERSION}.tar.gz" \
        | tar xz \
    && echo ">>> Buildroot ${BUILDROOT_VERSION} ready."

ENV BUILDROOT_VERSION=${BUILDROOT_VERSION}

# The entrypoint reads sources from /workspace (mounted at runtime) and writes
# the finished artefacts to /workspace/deploy/.
COPY docker-entrypoint.sh /usr/local/bin/docker-entrypoint.sh
RUN chmod 755 /usr/local/bin/docker-entrypoint.sh

VOLUME /workspace

ENTRYPOINT ["/usr/local/bin/docker-entrypoint.sh"]
