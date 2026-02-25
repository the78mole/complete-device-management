#!/bin/bash
# docker-entrypoint.sh – Builds the CDM Yocto TPM image for Raspberry Pi 4.
#
# Identical flow to yocto-raspberrypi4/docker-entrypoint.sh but targets
# cdm-image-rpi4-tpm and injects meta-cdm-tpm instead of meta-cdm.

set -euo pipefail

WORKSPACE="${WORKSPACE:-/workspace}"
LAYERS_DIR="/yocto/layers"
BUILD_DIR="/yocto/build"
DEPLOY_DIR="$WORKSPACE/deploy"
IMAGE_NAME="cdm-image-rpi4-tpm"

if [ ! -d "$WORKSPACE/conf" ]; then
    echo "ERROR: $WORKSPACE/conf/ not found."
    echo "       Mount the project directory:"
    echo "  docker run --rm -v \"\$(pwd):/workspace\" cdm-yocto-rpi4-tpm-builder"
    exit 1
fi

echo ">>> Initializing Yocto build environment ..."
mkdir -p "$BUILD_DIR"
source "$LAYERS_DIR/poky/oe-init-build-env" "$BUILD_DIR" > /dev/null

echo ">>> Applying project conf ..."
cp "$WORKSPACE/conf/local.conf"    "$BUILD_DIR/conf/local.conf"
cp "$WORKSPACE/conf/bblayers.conf" "$BUILD_DIR/conf/bblayers.conf"

# Inject meta-cdm-tpm layer from workspace
if [ -d "$WORKSPACE/meta-cdm-tpm" ]; then
    echo ">>> Linking meta-cdm-tpm layer ..."
    META_CDM_ABS="$WORKSPACE/meta-cdm-tpm"
    if ! grep -q "meta-cdm-tpm" "$BUILD_DIR/conf/bblayers.conf"; then
        echo "  BBLAYERS += \"${META_CDM_ABS}\"" \
            >> "$BUILD_DIR/conf/bblayers.conf"
    fi
fi

# Point DL_DIR + SSTATE_DIR to the mounted cache volumes
{
    echo "DL_DIR     = \"/yocto/downloads\""
    echo "SSTATE_DIR = \"/yocto/sstate-cache\""
} >> "$BUILD_DIR/conf/local.conf"

echo ">>> Running bitbake $IMAGE_NAME ..."
echo "    (first build: 1-3 h; subsequent builds with sstate-cache: ~10-30 min)"
bitbake "$IMAGE_NAME"

echo ">>> Copying artefacts to $DEPLOY_DIR ..."
mkdir -p "$DEPLOY_DIR"
IMAGE_DEPLOY="$BUILD_DIR/tmp/deploy/images/raspberrypi4-64"

for ext in wic.bz2 wic.bmap rootfs.manifest; do
    src=$(ls "$IMAGE_DEPLOY"/${IMAGE_NAME}-raspberrypi4-64*.${ext} 2>/dev/null | head -1 || true)
    if [ -n "$src" ]; then
        cp "$src" "$DEPLOY_DIR/"
        echo "  copied: $(basename "$src")"
    fi
done

echo ""
echo "=== Build complete ==="
echo "  Artefacts in $DEPLOY_DIR/"
echo ""
echo "Flash to SD card:"
echo "  bzip2 -dc deploy/${IMAGE_NAME}-raspberrypi4-64*.wic.bz2 \\"
echo "    | sudo dd of=/dev/sdX bs=4M status=progress"
