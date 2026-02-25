# Makefile – CDM freertos-x86_64-posix
#
# Targets:
#   make build          – native CMake build → deploy/cdm-freertos-device
#   make docker-builder – build the Docker toolchain image
#   make docker-image   – build the binary via Docker (no local toolchain needed)
#   make run            – run deploy/cdm-freertos-device with env vars
#   make clean          – remove deploy/ and native build dir
#   make distclean      – also remove the cmake FetchContent cache

DOCKER_IMAGE := cdm-freertos-builder
BUILD_DIR    := $(CURDIR)/build
DEPLOY_DIR   := $(CURDIR)/deploy

.PHONY: all build docker-builder docker-image run clean distclean

all: build

# ── Native: configure + build ────────────────────────────────────────────────
build:
	@echo ">>> Configuring (cmake) ..."
	cmake -S "$(CURDIR)" -B "$(BUILD_DIR)" \
	      -G Ninja \
	      -DCMAKE_BUILD_TYPE=Release
	@echo ">>> Building ..."
	cmake --build "$(BUILD_DIR)" -j$(shell nproc)
	mkdir -p "$(DEPLOY_DIR)"
	cp "$(BUILD_DIR)/cdm-freertos-device" "$(DEPLOY_DIR)/cdm-freertos-device"
	chmod 755 "$(DEPLOY_DIR)/cdm-freertos-device"
	@echo ">>> Build complete. Binary in deploy/"

# ── Docker: build toolchain image ─────────────────────────────────────────────
docker-builder:
	docker build -t $(DOCKER_IMAGE) .

# ── Docker: build binary (mounts current dir, writes to deploy/) ──────────────
docker-image:
	docker run --rm -v "$(CURDIR):/workspace" $(DOCKER_IMAGE)

# ── Run ───────────────────────────────────────────────────────────────────────
run:
	@[ -f deploy/cdm-freertos-device ] || \
	    (echo "Run 'make build' or 'make docker-image' first." && exit 1)
	./deploy/cdm-freertos-device

# ── Cleanup ───────────────────────────────────────────────────────────────────
clean:
	rm -rf deploy build

distclean: clean
