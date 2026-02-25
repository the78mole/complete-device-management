# freertos-x86_64-posix – CDM Enrollment & mTLS

FreeRTOS running on the **POSIX/Linux simulator port** (`FreeRTOS-Kernel/portable/ThirdParty/GCC/Posix`), compiled for `x86_64` Linux.

This variant covers the **minimum viable CDM device implementation**:

1. **Enrollment** — generate an EC P-256 key pair, create a PKCS#10 CSR, POST it to the Tenant IoT Bridge API, and persist the signed certificate + CA chain.
2. **mTLS MQTT** — connect to the Tenant ThingsBoard MQTT broker using the issued device certificate.

> Full features (WireGuard, OTA, Telegraf) are intentionally out of scope.  
> See [`../docker-based/`](../docker-based/) for the complete feature set.

## Repository Structure

```
freertos-x86_64-posix/
├── Dockerfile              # Toolchain image; run with -v $(pwd):/workspace to build
├── docker-entrypoint.sh    # Build logic executed inside the container at runtime
├── Makefile                # Targets: build, docker-builder, docker-image, run, clean
├── CMakeLists.txt          # Top-level CMake (FetchContent for FreeRTOS + mbedTLS + coreMQTT)
├── FreeRTOSConfig.h        # FreeRTOS POSIX port config (heap, tick rate, …)
├── main.c                  # FreeRTOS task entry point
├── enroll/
│   ├── enroll.c            # Enrollment task: key generation, CSR, HTTP POST, cert persist
│   ├── enroll.h
│   └── mbedtls_config.h    # mbedTLS profile: EC, PKCS#10, TLS 1.2/1.3, X.509
└── mqtt/
    ├── mqtt_client.c       # coreMQTT mTLS connect + minimal publish
    └── mqtt_client.h
```

## Dependencies

| Library | Version | Source |
|---|---|---|
| FreeRTOS Kernel (POSIX port) | ≥ 11.1 | `FetchContent` from GitHub |
| mbedTLS | ≥ 3.6 | `FetchContent` from GitHub |
| coreMQTT | ≥ 2.3 | `FetchContent` from GitHub |
| libcurl (enrollment HTTP) | system | `apt install libcurl4-openssl-dev` |

## Build & Run

Two equivalent options are available: Docker (no local toolchain needed) or native.

### Option A – Docker (recommended)

The `Dockerfile` creates a toolchain image with GCC, CMake, and all FetchContent deps
pre-downloaded into the image layer (no internet required at `docker run` time).

```bash
cd freertos-x86_64-posix

# 1. Build the toolchain image ONCE (~5 min, downloads FreeRTOS/mbedTLS/coreMQTT)
make docker-builder
# or: docker build -t cdm-freertos-builder .

# 2. Build the binary (mounts current dir, writes to deploy/)
make docker-image
# or: docker run --rm -v "$(pwd):/workspace" cdm-freertos-builder

# 3. Run
BRIDGE_API_URL=http://localhost:8888/api \
STEP_CA_FINGERPRINT=<tenant-sub-ca-fingerprint> \
THINGSBOARD_HOST=localhost \
make run
```

Output after step 2: `deploy/cdm-freertos-device`

### Option B – Native (Debian/Ubuntu)

```bash
# Install host dependencies
sudo apt install build-essential cmake ninja-build libcurl4-openssl-dev

cd freertos-x86_64-posix

# Build (FetchContent downloads FreeRTOS-Kernel, mbedTLS, coreMQTT automatically)
make build

# Run
BRIDGE_API_URL=http://localhost:8888/api \
STEP_CA_FINGERPRINT=<tenant-sub-ca-fingerprint> \
THINGSBOARD_HOST=localhost \
make run
```

Certificates are persisted to `./certs/` on the host filesystem.

## Configuration

All runtime parameters are read from environment variables:

| Variable | Default | Description |
|---|---|---|
| `DEVICE_ID` | `freertos-device-001` | Unique device identifier (used as MQTT client ID and CN) |
| `TENANT_ID` | `tenant1` | CDM tenant ID |
| `BRIDGE_API_URL` | — | Tenant IoT Bridge API base URL |
| `STEP_CA_FINGERPRINT` | — | Tenant Sub-CA SHA-256 fingerprint |
| `THINGSBOARD_HOST` | — | ThingsBoard MQTT hostname |
| `THINGSBOARD_MQTT_PORT` | `8883` | ThingsBoard MQTT TLS port |

## Status

> **Alpha.** All source files and the Docker-based build toolchain are present.
> The binary has not yet been built and end-to-end tested against a live
> Provider/Tenant Stack.
