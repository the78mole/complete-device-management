# device-stack/freertos-x86_64-posix/Dockerfile
#
# CMake/GCC toolchain image for the FreeRTOS POSIX simulator build.
# FetchContent deps (FreeRTOS-Kernel, mbedTLS, coreMQTT) are pre-downloaded
# into /deps during the image build so runtime invocations don't need internet.
#
# ── Build the toolchain image ONCE ──────────────────────────────────────────
#   docker build -t cdm-freertos-builder .
#
# ── Build the device binary ─────────────────────────────────────────────────
#   docker run --rm -v "$(pwd):/workspace" cdm-freertos-builder
#
# Output on the host:
#   device-stack/freertos-x86_64-posix/deploy/cdm-freertos-device
#
# ── Run the built binary directly ───────────────────────────────────────────
#   BRIDGE_API_URL=http://... THINGSBOARD_HOST=... ./deploy/cdm-freertos-device

FROM debian:12-slim

# Host build tools
RUN apt-get update && apt-get install -y --no-install-recommends \
        ca-certificates \
        cmake \
        curl \
        g++ \
        gcc \
        git \
        libcurl4-openssl-dev \
        make \
        ninja-build \
        pkg-config \
        python3 \
    && rm -rf /var/lib/apt/lists/*

# ── Pre-fetch FetchContent dependencies ──────────────────────────────────────
#
# Copy only the build description files and synthetic stubs so cmake can resolve
# all FetchContent declarations and download the sources into /deps.  The real
# sources are provided from /workspace at runtime; /deps is shared via
# FETCHCONTENT_BASE_DIR so clones are never repeated.
WORKDIR /prefetch
COPY CMakeLists.txt FreeRTOSConfig.h ./
COPY enroll/mbedtls_config.h         ./enroll/mbedtls_config.h

# Create minimal stub sources — enough for cmake to configure and run FetchContent
# without actually compiling everything at image build time.
RUN mkdir -p enroll mqtt \
    && printf '#ifndef ENROLL_H\n#define ENROLL_H\nint cdm_enroll(void);\n#endif\n' \
              > enroll/enroll.h \
    && printf '#ifndef MQTT_CLIENT_H\n#define MQTT_CLIENT_H\nint cdm_mqtt_connect_and_publish(void);\n#endif\n' \
              > mqtt/mqtt_client.h \
    && printf '#include "enroll.h"\nint cdm_enroll(void){return 0;}\n' \
              > enroll/enroll.c \
    && printf '#include "mqtt_client.h"\nint cdm_mqtt_connect_and_publish(void){return 0;}\n' \
              > mqtt/mqtt_client.c \
    && printf '#include "FreeRTOS.h"\nint main(void){return 0;}\n' \
              > main.c

RUN cmake -S /prefetch -B /prefetch/build \
          -G Ninja \
          -DCMAKE_BUILD_TYPE=Release \
          -DFETCHCONTENT_BASE_DIR=/deps \
    && rm -rf /prefetch/build /prefetch

# ── Runtime entrypoint ────────────────────────────────────────────────────────
# Sources are read from /workspace (mounted at runtime).
# The binary is written to /workspace/deploy/.
COPY docker-entrypoint.sh /usr/local/bin/docker-entrypoint.sh
RUN chmod 755 /usr/local/bin/docker-entrypoint.sh

VOLUME /workspace

ENTRYPOINT ["/usr/local/bin/docker-entrypoint.sh"]
