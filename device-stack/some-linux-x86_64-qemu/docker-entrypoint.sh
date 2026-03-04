#!/bin/sh
# docker-entrypoint.sh – Builds the CDM minimal Linux image inside the container.
#
# The workspace directory is mounted at /workspace (read-write):
#   docker run --rm -v "$(pwd):/workspace" cdm-qemu-builder
#
# Sources read from /workspace:
#   buildroot.config, overlay/, enroll.sh
#
# Artefacts written to /workspace/deploy/:
#   bzImage, rootfs.cpio.gz

set -eu

WORKSPACE="${WORKSPACE:-/workspace}"
BUILD_DIR="/build/buildroot-${BUILDROOT_VERSION}"
OUTPUT_DIR="/build/output"
OVERLAY_DIR="/build/overlay"
DEPLOY_DIR="$WORKSPACE/deploy"

# ── Sanity check ─────────────────────────────────────────────────────────────
if [ ! -f "$WORKSPACE/buildroot.config" ]; then
    echo "ERROR: $WORKSPACE/buildroot.config not found."
    echo "       Mount the source directory:"
    echo "  docker run --rm -v \"\$(pwd):/workspace\" cdm-qemu-builder"
    exit 1
fi

# ── Overlay: merge workspace overlay + enroll.sh ─────────────────────────────
echo ">>> Preparing rootfs overlay ..."
mkdir -p "$OVERLAY_DIR/etc/init.d" "$OVERLAY_DIR/usr/bin"
rsync -a "$WORKSPACE/overlay/" "$OVERLAY_DIR/"
install -m 755 "$WORKSPACE/enroll.sh" "$OVERLAY_DIR/usr/bin/enroll.sh"
chmod 755 "$OVERLAY_DIR/etc/init.d/S99cdm-enroll"

# ── Configure Buildroot ───────────────────────────────────────────────────────
echo ">>> Configuring Buildroot ..."
mkdir -p "$OUTPUT_DIR"
cp "$WORKSPACE/buildroot.config" "$OUTPUT_DIR/.config"
make -C "$BUILD_DIR" O="$OUTPUT_DIR" olddefconfig

# ── Build ─────────────────────────────────────────────────────────────────────
echo ">>> Building image (may take ~10–20 min on first run) ..."
make -C "$BUILD_DIR" O="$OUTPUT_DIR" -j"$(nproc)"

# ── Export artefacts ─────────────────────────────────────────────────────────
echo ">>> Copying artefacts to $DEPLOY_DIR ..."
mkdir -p "$DEPLOY_DIR"
cp "$OUTPUT_DIR/images/bzImage"        "$DEPLOY_DIR/bzImage"
cp "$OUTPUT_DIR/images/rootfs.cpio.gz" "$DEPLOY_DIR/rootfs.cpio.gz"

echo ""
echo "=== Build complete ==="
echo "  $DEPLOY_DIR/bzImage"
echo "  $DEPLOY_DIR/rootfs.cpio.gz"
echo ""
echo "Run with:"
echo "  BRIDGE_API_URL=http://<host>:8888/api THINGSBOARD_HOST=<host> ./run-qemu.sh"
