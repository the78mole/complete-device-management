# some-linux-x86_64-qemu – CDM Enrollment & mTLS

A minimal **Linux on x86\_64** device implementation running inside **QEMU**, covering enrollment and mTLS.

The device image is built with [Buildroot](https://buildroot.org/) targeting a generic x86\_64 VM (QEMU `-M pc`). The result is a small `bzImage` + `rootfs.cpio.gz` initramfs that runs the CDM enrollment script on first boot and then connects to ThingsBoard via mTLS MQTT.

> Full features (WireGuard, OTA, Telegraf) are intentionally out of scope.  
> See [`../docker-based/`](../docker-based/) for the complete feature set.

## Repository Structure

```
some-linux-x86_64-qemu/
├── Dockerfile              # Toolchain image; run with -v $(pwd):/workspace to build
├── docker-entrypoint.sh    # Build logic executed inside the container at runtime
├── .dockerignore
├── Makefile                # Build targets: toolchain, image, run, clean
├── run-qemu.sh             # Launches QEMU x86_64 with the built image
├── enroll.sh               # Device enrollment script (runs inside the VM on first boot)
├── buildroot.config        # Buildroot defconfig (x86_64, BusyBox, OpenSSL, mosquitto)
└── overlay/
    └── etc/
        └── init.d/
            └── S99cdm-enroll  # SysV init script – calls enroll.sh on first boot
```

## Build & Run

Two equivalent options are available: native (requires a Debian/Ubuntu host) or Docker
(cross-platform, no local toolchain needed).

### Option A – Docker (recommended)

The `Dockerfile` creates a **toolchain image** containing Buildroot and all host deps.
The actual build happens at *runtime*: the source directory is mounted into the container
and the compiled artefacts are written back to `deploy/` on the host — so no files are
buried inside an image layer.

```bash
cd some-linux-x86_64-qemu

# 1. Build the toolchain image ONCE (~5 min, downloads Buildroot inside the image)
make docker-builder
# or: docker build -t cdm-qemu-builder .

# 2. Build the QEMU device image (mounts current dir, writes to deploy/)
make docker-image
# or: docker run --rm -v "$(pwd):/workspace" cdm-qemu-builder

# 3. Run natively (deploy/bzImage must exist)
BRIDGE_API_URL=http://10.0.2.2:8888/api \
STEP_CA_FINGERPRINT=<tenant-sub-ca-fingerprint> \
THINGSBOARD_HOST=10.0.2.2 \
make run
```

Output after step 2:
```
deploy/bzImage
deploy/rootfs.cpio.gz
```

### Option B – Native (Debian/Ubuntu)

```bash
# Install host dependencies
sudo apt install qemu-system-x86 build-essential git bc cpio rsync

cd some-linux-x86_64-qemu

# 1. Fetch Buildroot and build the image (~10 min on first run)
make image

# 2. Launch QEMU (serial console in the terminal, Ctrl-A X to quit)
BRIDGE_API_URL=http://10.0.2.2:8888/api \
STEP_CA_FINGERPRINT=<tenant-sub-ca-fingerprint> \
THINGSBOARD_HOST=10.0.2.2 \
make run
```

`10.0.2.2` is the default QEMU SLIRP gateway — it maps to the host machine.

## Configuration

Runtime parameters are passed to QEMU as kernel command-line arguments and exposed to the init script as environment variables:

| Variable | Default | Description |
|---|---|---|
| `DEVICE_ID` | `qemu-device-001` | Unique device identifier |
| `TENANT_ID` | `tenant1` | CDM tenant ID |
| `BRIDGE_API_URL` | — | Tenant IoT Bridge API base URL |
| `STEP_CA_FINGERPRINT` | — | Tenant Sub-CA SHA-256 fingerprint |
| `THINGSBOARD_HOST` | — | ThingsBoard MQTT hostname (use `10.0.2.2` for host) |
| `THINGSBOARD_MQTT_PORT` | `8883` | ThingsBoard MQTT TLS port |

## Enrollment Flow

On first boot, `S99cdm-enroll` calls `enroll.sh` which:

1. Generates an EC P-256 key pair with `openssl ecparam`.
2. Creates a PKCS#10 CSR with `openssl req`.
3. POSTs the CSR to the Tenant IoT Bridge API (`$BRIDGE_API_URL/v1/enroll`).
4. Writes the signed certificate and CA chain to `/persist/certs/` (survives reboots via a small ext4 partition in `rootfs`).
5. Touches `/persist/.enrolled` — subsequent boots skip enrollment.

After enrollment, `mosquitto_pub` / `mosquitto_sub` are used for a minimal mTLS connectivity test.

## Status

> **Alpha.** All source files are present (`enroll.sh`, `run-qemu.sh`, `buildroot.config`,
> overlay init script, `Dockerfile`). The Buildroot image has not yet been built and
> end-to-end tested against a live Provider/Tenant Stack.
