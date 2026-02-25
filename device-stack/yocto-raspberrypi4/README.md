# yocto-raspberrypi4 – CDM Enrollment & mTLS

A Yocto-based **Raspberry Pi 4 (64-bit)** device image covering CDM enrollment and mTLS MQTT.

Built with [Yocto 5.0 LTS "scarthgap"](https://docs.yoctoproject.org/5.0/) using:
- `poky` — base distro
- `meta-openembedded` — networking + curl packages
- `meta-raspberrypi` — RPi 4 BSP
- `meta-cdm` *(in this directory)* — enrollment service

On first boot the `cdm-enroll.service` systemd unit runs `cdm-enroll.sh`, which generates an EC P-256 key pair, POSTs a CSR to the Tenant IoT Bridge API, and persists the signed certificate to `/var/lib/cdm/certs/`. Subsequent boots detect `/var/lib/cdm/.enrolled` and skip enrollment.

> Full features (WireGuard, OTA, Telegraf) are intentionally out of scope.  
> See [`../docker-based/`](../docker-based/) for the complete feature set.

---

## Repository Structure

```
yocto-raspberrypi4/
├── Dockerfile                      # Toolchain image (Ubuntu 24.04 + Yocto layers cloned inside)
├── docker-entrypoint.sh            # Build logic executed inside the container at runtime
├── Makefile                        # docker-builder, docker-image, flash, clean
├── conf/
│   ├── local.conf                  # MACHINE=raspberrypi4-64, IMAGE_INSTALL, formats
│   └── bblayers.conf               # Layer paths (/yocto/layers/… inside container)
└── meta-cdm/                       # Custom Yocto layer
    ├── conf/layer.conf
    └── recipes-cdm/
        ├── images/
        │   └── cdm-image-rpi4.bb   # Image recipe (extends core-image-minimal)
        └── cdm-enroll/
            ├── cdm-enroll.bb       # Recipe: installs script + systemd service
            └── files/
                ├── cdm-enroll.sh   # Enrollment + mTLS test script
                ├── cdm-enroll.service  # systemd oneshot unit
                └── cdm-enroll.env  # Static config (overridable via cmdline)
```

---

## Build

### Option A – Docker (recommended)

The `Dockerfile` uses Ubuntu 24.04 (the Yocto-recommended host) and clones all three
Yocto layers into the image layer, so runtime builds need no internet access.
The build directory stays inside the container; only the finished SD-card image is
written back to `deploy/` on the host.

```bash
cd yocto-raspberrypi4

# 1. Build the toolchain image ONCE (~10 min, clones ~500 MB of Yocto layers)
make docker-builder

# 2. Build the RPi 4 image
#    First run: ~1-3 h, ~50 GB disk.
#    Subsequent runs with sstate-cache: ~10-30 min.
make docker-image

# Optional: use a custom cache location to share across projects
DL_DIR=/data/yocto/downloads SSTATE_DIR=/data/yocto/sstate make docker-image
```

Under the hood `docker-image` runs:
```
docker run --rm \
  -v "$(pwd):/workspace" \
  -v "$HOME/.yocto/downloads:/yocto/downloads" \
  -v "$HOME/.yocto/sstate-cache:/yocto/sstate-cache" \
  cdm-yocto-rpi4-builder
```

Output in `deploy/`:
```
cdm-image-rpi4-raspberrypi4-64.rootfs.wic.bz2   ← flashable SD-card image
cdm-image-rpi4-raspberrypi4-64.rootfs.wic.bmap   ← bmap for fast flash
cdm-image-rpi4-raspberrypi4-64.rootfs.manifest
```

### Option B – Native (Ubuntu 24.04 host)

Install the Yocto host packages manually and run BitBake directly:

```bash
# Install host deps (Ubuntu 24.04)
sudo apt install gawk wget git diffstat unzip texinfo gcc build-essential chrpath \
    socat cpio python3 python3-pip python3-pexpect xz-utils debianutils \
    iputils-ping python3-git python3-jinja2 python3-subunit zstd liblz4-tool \
    file libssl-dev

# Clone layers (once)
git clone --depth 1 -b scarthgap https://git.yoctoproject.org/poky poky
cd poky
git clone --depth 1 -b scarthgap https://git.openembedded.org/meta-openembedded
git clone --depth 1 -b scarthgap https://git.yoctoproject.org/meta-raspberrypi

# Initialize build env
source oe-init-build-env ../build

# Copy CDM conf
cp ../../conf/local.conf conf/
cp ../../conf/bblayers.conf conf/
# Adjust absolute paths in bblayers.conf for your host checkout!

bitbake cdm-image-rpi4
```

---

## Configuration

Edit `meta-cdm/recipes-cdm/cdm-enroll/files/cdm-enroll.env` before building, **or**
override any value at run time by appending `cdm.KEY=VALUE` to the last line of
`/boot/cmdline.txt` on the SD card (no re-build required):

```
# Example: /boot/cmdline.txt (append to existing line, no newline)
… cdm.device_id=rpi4-factory-007 cdm.bridge_api_url=https://cdm.example.com/api
```

| Variable | Default in env file | Description |
|---|---|---|
| `DEVICE_ID` | `rpi4-device-001` | Unique device identifier (cert CN, MQTT client ID) |
| `DEVICE_TYPE` | `rpi4` | Device type tag |
| `TENANT_ID` | `tenant1` | CDM tenant ID |
| `BRIDGE_API_URL` | — | Tenant IoT Bridge API base URL |
| `STEP_CA_FINGERPRINT` | — | Tenant Sub-CA SHA-256 fingerprint |
| `THINGSBOARD_HOST` | — | ThingsBoard MQTT broker hostname/IP |
| `THINGSBOARD_MQTT_PORT` | `8883` | ThingsBoard MQTT TLS port |

---

## Flash to SD Card

```bash
# Interactive (prompts for device)
make flash

# Manual
bzip2 -dc deploy/cdm-image-rpi4-raspberrypi4-64*.wic.bz2 \
    | sudo dd of=/dev/sdX bs=4M status=progress conv=fsync

# Fast (using bmaptool, recommended)
sudo bmaptool copy deploy/cdm-image-rpi4-*.wic.bz2 /dev/sdX
```

---

## Enrollment Flow

On first boot:

1. `network-online.target` is reached (DHCP).
2. systemd starts `cdm-enroll.service` (`ConditionPathExists=!/var/lib/cdm/.enrolled`).
3. `cdm-enroll.sh` generates EC P-256 key → PKCS#10 CSR → HTTP POST to IoT Bridge API.
4. Signed certificate + CA chain written to `/var/lib/cdm/certs/`.
5. `/var/lib/cdm/.enrolled` touched → service skipped on all subsequent boots.
6. `mosquitto_pub` mTLS connectivity test to verify the issued certificate.

Enroll a different device by removing the flag and rebooting:
```bash
sudo rm /var/lib/cdm/.enrolled && sudo reboot
```

---

## Status

> **Alpha.** All source files and the Docker-based build toolchain are present.
> The Yocto image has not yet been built and end-to-end tested against a live
> Provider/Tenant Stack.
