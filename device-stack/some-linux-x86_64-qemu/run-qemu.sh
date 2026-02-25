#!/bin/sh
# run-qemu.sh – Launch the CDM minimal Linux image in QEMU x86_64
#
# Passes CDM configuration as kernel command-line arguments; the init script
# (overlay/etc/init.d/S99cdm-enroll) reads them from /proc/cmdline and
# exports them as environment variables before calling enroll.sh.
#
# Usage:
#   BRIDGE_API_URL=http://10.0.2.2:8888/api \
#   STEP_CA_FINGERPRINT=abc123... \
#   THINGSBOARD_HOST=10.0.2.2 \
#   ./run-qemu.sh
#
# QEMU networking: user-mode SLIRP (no root required).
#   Host 10.0.2.2 = gateway (reachable as "host machine" from inside VM).
#
# Environment variables forwarded to the VM:
#   DEVICE_ID, DEVICE_TYPE, TENANT_ID
#   BRIDGE_API_URL, STEP_CA_FINGERPRINT
#   THINGSBOARD_HOST, THINGSBOARD_MQTT_PORT

set -eu

: "${DEVICE_ID:=qemu-device-001}"
: "${DEVICE_TYPE:=qemu-x86_64}"
: "${TENANT_ID:=tenant1}"
: "${BRIDGE_API_URL:?BRIDGE_API_URL must be set}"
: "${STEP_CA_FINGERPRINT:=}"
: "${THINGSBOARD_HOST:?THINGSBOARD_HOST must be set}"
: "${THINGSBOARD_MQTT_PORT:=8883}"

IMAGE_DIR="$(dirname "$0")/deploy"
KERNEL="$IMAGE_DIR/bzImage"
ROOTFS="$IMAGE_DIR/rootfs.cpio.gz"

if [ ! -f "$KERNEL" ] || [ ! -f "$ROOTFS" ]; then
    echo "ERROR: Kernel or rootfs not found in $IMAGE_DIR."
    echo "       Build first:"
    echo "  make image                                               # native"
    echo "  docker run --rm -v \"\$(pwd):/workspace\" cdm-qemu-builder  # Docker"
    exit 1
fi

echo "Starting QEMU x86_64..."
echo "  Device ID : $DEVICE_ID"
echo "  Tenant    : $TENANT_ID"
echo "  Bridge API: $BRIDGE_API_URL"
echo "  TB Host   : $THINGSBOARD_HOST:$THINGSBOARD_MQTT_PORT"
echo ""
echo "Press Ctrl-A X to quit QEMU."
echo "---"

exec qemu-system-x86_64 \
    -M pc \
    -m 256M \
    -nographic \
    -kernel "$KERNEL" \
    -initrd "$ROOTFS" \
    -net nic,model=virtio \
    -net user,hostfwd=tcp::2222-:22 \
    -append "console=ttyS0 quiet \
cdm.device_id=$DEVICE_ID \
cdm.device_type=$DEVICE_TYPE \
cdm.tenant_id=$TENANT_ID \
cdm.bridge_api_url=$BRIDGE_API_URL \
cdm.step_ca_fingerprint=$STEP_CA_FINGERPRINT \
cdm.thingsboard_host=$THINGSBOARD_HOST \
cdm.thingsboard_mqtt_port=$THINGSBOARD_MQTT_PORT"
