# yocto-raspberrypi4-tpm – CDM Enrollment & mTLS (TPM-backed Keys)

A Yocto-based **Raspberry Pi 4 (64-bit)** device image with **hardware-backed key storage**
using the [Infineon SLB9672 TPM 2.0](https://www.reichelt.com/de/en/shop/product/raspberry_pi_-_trusted_platform_module_tpm_slb9672-253834)
connected via SPI.

The EC P-256 private key is generated **inside** the TPM and is never exported.
All cryptographic operations (signing, ECDH) happen in the TPM hardware.
The host OS and network see only the public key and the certificate.

> See [`../yocto-raspberrypi4/`](../yocto-raspberrypi4/) for the plain (filesystem-only)
> variant and [`../docker-based/`](../docker-based/) for the full feature set.

---

## Hardware

**Infineon OPTIGA™ TPM SLB9672** (Raspberry Pi TPM module)
- Reichelt article: [SLB9672](https://www.reichelt.com/de/en/shop/product/raspberry_pi_-_trusted_platform_module_tpm_slb9672-253834)
- Interface: SPI (compatible with `tpm-slb9670` DT overlay)
- Standard: TCG TPM 2.0, firmware-upgradable

**Wiring to RPi 4 GPIO header:**

```
SLB9672 signal │ RPi4 pin │ GPIO     │ SPI signal
───────────────┼──────────┼──────────┼────────────
VCC  (3.3 V)   │ pin  1   │ 3.3 V    │ power
GND            │ pin  6   │ GND      │ ground
MOSI  (SDI)    │ pin 19   │ GPIO10   │ SPI0_MOSI
MISO  (SDO)    │ pin 21   │ GPIO9    │ SPI0_MISO
SCLK           │ pin 23   │ GPIO11   │ SPI0_SCLK
CS             │ pin 26   │ GPIO7    │ SPI0_CE1
```

> CE0 (pin 24, GPIO8) also works — adjust `dtoverlay=tpm-slb9670,ce0_pin=24` in `conf/local.conf`.

---

## Repository Structure

```
yocto-raspberrypi4-tpm/
├── Dockerfile                        # Toolchain image (adds meta-security to base RPi 4)
├── docker-entrypoint.sh              # Build logic
├── Makefile
├── conf/
│   ├── local.conf                    # MACHINE, RPI_EXTRA_CONFIG (dtoverlay), TPM packages
│   └── bblayers.conf                 # Adds /yocto/layers/meta-security + meta-tpm
└── meta-cdm-tpm/
    ├── conf/layer.conf
    ├── recipes-kernel/
    │   └── linux/
    │       ├── linux-raspberrypi_%.bbappend   # Applies TPM SPI kernel config fragment
    │       └── files/tpm-spi.cfg              # CONFIG_TCG_TIS_SPI=y, CONFIG_TCG_TPM=y
    └── recipes-cdm/
        ├── images/
        │   └── cdm-image-rpi4-tpm.bb
        └── cdm-enroll/
            ├── cdm-enroll-tpm.bb
            └── files/
                ├── cdm-enroll-tpm.sh          # TPM enrollment script
                ├── cdm-enroll.service          # systemd oneshot (After=tpm2-abrmd)
                ├── cdm-enroll.env
                └── tpm2-abrmd.service.d-override.conf
```

---

## Security Model

```
┌──────────────────────────────────────────────────────────────────────┐
│                         Raspberry Pi 4                               │
│                                                                      │
│  ┌──────────────────┐   tpm2-openssl    ┌──────────────────────┐    │
│  │  cdm-enroll.sh   │ ─────provider──▶  │  Infineon SLB9672    │    │
│  │  (user space)    │                   │  TPM 2.0 (via SPI)   │    │
│  │                  │ ◀── pubkey only ─ │                      │    │
│  └──────────────────┘                   │  Private key         │    │
│         │                               │  generated here,     │    │
│         │ certificate                   │  NEVER exported      │    │
│         ▼                               └──────────────────────┘    │
│  /var/lib/cdm/certs/                                                 │
│    device.pem       ← signed by Tenant Sub-CA (public, safe to keep)│
│    ca-chain.pem     ← CA chain (public)                             │
│    device-pubkey.pem← TPM public key export (not secret)            │
│                                                                      │
│  TPM persistent handle 0x81000001 ← ECC P-256 key (stays in TPM)   │
└──────────────────────────────────────────────────────────────────────┘
```

**What the filesystem contains after enrollment:**

| File | Sensitivity | Notes |
|---|---|---|
| `device.pem` | Public | Signed device certificate |
| `ca-chain.pem` | Public | CA chain for verification |
| `device-pubkey.pem` | Public | TPM public key export |
| `/var/lib/cdm/.enrolled` | — | Enrollment flag |

**What stays in the TPM hardware:**

| TPM object | Handle | Cannot be… |
|---|---|---|
| ECC P-256 private key | `0x81000001` | exported, read, migrated |

---

## Build

### Option A – Docker (recommended)

```bash
cd yocto-raspberrypi4-tpm

# 1. Build toolchain image ONCE (~12 min, clones poky + meta-oe + meta-rpi + meta-security)
make docker-builder

# 2. Build RPi 4 TPM image (first run: ~1-3 h)
make docker-image

# Share download/sstate cache with the non-TPM variant (same Yocto branch):
DL_DIR=$HOME/.yocto/downloads SSTATE_DIR=$HOME/.yocto/sstate-cache make docker-image
```

Output: `deploy/cdm-image-rpi4-tpm-raspberrypi4-64.rootfs.wic.bz2`

### Option B – Native (Ubuntu 24.04)

Same as the base RPi 4 variant; additionally clone `meta-security` and set
`YOCTO_BRANCH=scarthgap`:

```bash
git clone --depth 1 -b scarthgap https://git.yoctoproject.org/meta-security \
    poky/meta-security
# Add meta-security + meta-security/meta-tpm to bblayers.conf (adjust absolute paths)
bitbake cdm-image-rpi4-tpm
```

---

## Flash & First Boot

```bash
# Flash (interactive)
make flash

# Or manually
bzip2 -dc deploy/cdm-image-rpi4-tpm-*.wic.bz2 \
    | sudo dd of=/dev/sdX bs=4M status=progress conv=fsync
```

On first boot (after DHCP):

1. `tpm2-abrmd.service` starts the TPM Access Broker.
2. `cdm-enroll.service` runs `cdm-enroll.sh` (via symlink to `cdm-enroll-tpm.sh`):
   - Waits for `/dev/tpmrm0`.
   - Creates a primary key in the TPM owner hierarchy.
   - Creates an ECC P-256 child key — **private key never leaves the TPM**.
   - Makes the key persistent at `0x81000001`.
   - Generates a PKCS#10 CSR by signing with the TPM key
     (via `openssl req -provider tpm2`).
   - POSTs the CSR to the Tenant IoT Bridge API.
   - Stores the signed certificate and CA chain in `/var/lib/cdm/certs/`.
   - Verifies the TLS handshake with `openssl s_client -provider tpm2`.
   - Touches `/var/lib/cdm/.enrolled`.

Re-enroll (e.g. after certificate expiry):
```bash
# On the device:
sudo tpm2_evictcontrol -C o -c 0x81000001   # remove persistent key
sudo rm /var/lib/cdm/.enrolled
sudo systemctl restart cdm-enroll.service
```

---

## Configuration

| Variable | Default | Description |
|---|---|---|
| `DEVICE_ID` | `rpi4-tpm-device-001` | Cert CN + MQTT client ID |
| `DEVICE_TYPE` | `rpi4-tpm` | Informational tag |
| `TENANT_ID` | `tenant1` | CDM tenant ID |
| `BRIDGE_API_URL` | — | Tenant IoT Bridge API base URL |
| `STEP_CA_FINGERPRINT` | — | Tenant Sub-CA SHA-256 fingerprint |
| `THINGSBOARD_HOST` | — | ThingsBoard MQTT broker hostname/IP |
| `THINGSBOARD_MQTT_PORT` | `8883` | ThingsBoard MQTT TLS port |

Override any value without rebuilding by appending `cdm.KEY=VALUE` to the
**last line** of `/boot/cmdline.txt` on the SD card.

---

## mosquitto mTLS with TPM key (production path)

The enrollment script tests the TPM key via `openssl s_client -provider tpm2`.
For production MQTT telemetry, `mosquitto_pub`/`mosquitto_sub` need the private key
accessible via the PKCS#11 interface (`tpm2-pkcs11` + `libp11`):

The enrollment script automatically attempts to set up a `tpm2-pkcs11` token
(`cdm-device`) and link the persistent handle into it. If successful,
`mosquitto_pub` is called with:

```
--key "pkcs11:token=cdm-device;object=device-key;type=private;pin-value=cdmuserpin"
--keyform engine --tls-engine pkcs11
```

This requires that mosquitto was built with OpenSSL engine support and that
`/usr/lib/pkcs11/libtpm2_pkcs11.so` is present in the image.

---

## Status

> **Alpha.** All source files and the Docker-based build toolchain are present.
> The image has not yet been built and end-to-end tested against a live
> Provider/Tenant Stack or physical SLB9672 hardware.
