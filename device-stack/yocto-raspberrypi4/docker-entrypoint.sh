#!/bin/bash
# docker-entrypoint.sh – Builds the CDM Yocto image for Raspberry Pi 4.
#
# Must run as non-root user (BitBake requirement) — the Dockerfile switches to
# the 'yocto' user before ENTRYPOINT.
#
# Mounts expected (all read-write):
#   /workspace          – project dir (conf/, meta-cdm/, deploy/ written here)
#   /yocto/downloads    – (optional) persistent download cache
#   /yocto/sstate-cache – (optional) persistent sstate cache
#
# Artefacts written to /workspace/deploy/:
#   cdm-image-rpi4-raspberrypi4-64.rootfs.wic.bz2
#   cdm-image-rpi4-raspberrypi4-64.rootfs.manifest

set -euo pipefail

WORKSPACE="${WORKSPACE:-/workspace}"
LAYERS_DIR="/yocto/layers"
BUILD_DIR="/yocto/build"
DEPLOY_DIR="$WORKSPACE/deploy"
IMAGE_NAME="cdm-image-rpi4"

# ── Sanity check ──────────────────────────────────────────────────────────────
if [ ! -d "$WORKSPACE/conf" ]; then
    echo "ERROR: $WORKSPACE/conf/ not found."
    echo "       Mount the project directory:"
    echo "  docker run --rm -v \"\$(pwd):/workspace\" cdm-yocto-rpi4-builder"
    exit 1
fi

# ── Initialize Yocto build environment ───────────────────────────────────────
echo ">>> Initializing Yocto build environment ..."
mkdir -p "$BUILD_DIR"
# source oe-init-build-env writes conf/ only when the build dir is fresh.
# We always overwrite conf/ from /workspace/conf to stay in sync.
source "$LAYERS_DIR/poky/oe-init-build-env" "$BUILD_DIR" > /dev/null

# ── Inject project conf ───────────────────────────────────────────────────────
echo ">>> Applying project conf (local.conf, bblayers.conf) ..."
cp "$WORKSPACE/conf/local.conf"    "$BUILD_DIR/conf/local.conf"
cp "$WORKSPACE/conf/bblayers.conf" "$BUILD_DIR/conf/bblayers.conf"

# ── Inject meta-cdm layer from workspace ─────────────────────────────────────
if [ -d "$WORKSPACE/meta-cdm" ]; then
    echo ">>> Linking meta-cdm layer ..."
    # Use absolute path so BitBake can find it regardless of CWD
    META_CDM_ABS="$WORKSPACE/meta-cdm"
    # Append to bblayers.conf if not already present
    if ! grep -q "meta-cdm" "$BUILD_DIR/conf/bblayers.conf"; then
        sed -i "s|^\(BBLAYERS ?= \"\)|  ${META_CDM_ABS} \\\\\n\1|" \
            "$BUILD_DIR/conf/bblayers.conf" || true
        echo "  BBLAYERS += \"${META_CDM_ABS}\"" \
            >> "$BUILD_DIR/conf/bblayers.conf"
    fi
fi

# ── Point DL_DIR + SSTATE_DIR to the mounted cache volumes ───────────────────
{
    echo "DL_DIR       = \"/yocto/downloads\""
    echo "SSTATE_DIR   = \"/yocto/sstate-cache\""
} >> "$BUILD_DIR/conf/local.conf"

# ── BitBake ───────────────────────────────────────────────────────────────────
echo ">>> Running bitbake $IMAGE_NAME ..."
echo "    (first build: 1-3 h and ~50 GB disk; subsequent builds are much faster)"
echo ""
bitbake "$IMAGE_NAME"

# ── Collect artefacts ─────────────────────────────────────────────────────────
echo ""
echo ">>> Copying artefacts to $DEPLOY_DIR ..."
mkdir -p "$DEPLOY_DIR"

IMAGE_DEPLOY="$BUILD_DIR/tmp/deploy/images/raspberrypi4-64"

# wic.bz2 (flashable SD-card image) + manifest
for ext in wic.bz2 wic.bmap rootfs.manifest; do
    src=$(find "$IMAGE_DEPLOY" -maxdepth 1 -name "${IMAGE_NAME}-raspberrypi4-64*.${ext}" \
          -newer "$IMAGE_DEPLOY" 2>/dev/null | head -1 || true)
    [ -n "$src" ] || src=$(ls "$IMAGE_DEPLOY"/${IMAGE_NAME}-raspberrypi4-64*.${ext} 2>/dev/null | head -1 || true)
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
