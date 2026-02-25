#!/bin/sh
# docker-entrypoint.sh – Builds the CDM FreeRTOS POSIX device binary.
#
# The workspace directory is mounted at /workspace (read-write):
#   docker run --rm -v "$(pwd):/workspace" cdm-freertos-builder
#
# Sources read from /workspace (the full project tree).
# FetchContent deps are served from /deps (pre-fetched in the image layer)
# so no network access is required at build time.
#
# Artefact written to /workspace/deploy/:
#   cdm-freertos-device

set -eu

WORKSPACE="${WORKSPACE:-/workspace}"
BUILD_DIR="/build"
DEPLOY_DIR="$WORKSPACE/deploy"

# ── Sanity check ──────────────────────────────────────────────────────────────
if [ ! -f "$WORKSPACE/CMakeLists.txt" ]; then
    echo "ERROR: $WORKSPACE/CMakeLists.txt not found."
    echo "       Mount the source directory:"
    echo "  docker run --rm -v \"\$(pwd):/workspace\" cdm-freertos-builder"
    exit 1
fi

# ── CMake configure ───────────────────────────────────────────────────────────
echo ">>> Configuring (cmake) ..."
cmake -S "$WORKSPACE" -B "$BUILD_DIR" \
    -G Ninja \
    -DCMAKE_BUILD_TYPE=Release \
    -DFETCHCONTENT_BASE_DIR=/deps \
    -DFETCHCONTENT_UPDATES_DISCONNECTED=ON

# ── Build ─────────────────────────────────────────────────────────────────────
echo ">>> Building ..."
cmake --build "$BUILD_DIR" -j"$(nproc)"

# ── Export artefact ───────────────────────────────────────────────────────────
echo ">>> Copying artefact to $DEPLOY_DIR ..."
mkdir -p "$DEPLOY_DIR"
cp "$BUILD_DIR/cdm-freertos-device" "$DEPLOY_DIR/cdm-freertos-device"
chmod 755 "$DEPLOY_DIR/cdm-freertos-device"

echo ""
echo "=== Build complete ==="
echo "  $DEPLOY_DIR/cdm-freertos-device"
echo ""
echo "Run with:"
echo "  BRIDGE_API_URL=http://<host>:8888/api \\"
echo "  STEP_CA_FINGERPRINT=<fingerprint> \\"
echo "  THINGSBOARD_HOST=<host> \\"
echo "  ./deploy/cdm-freertos-device"
