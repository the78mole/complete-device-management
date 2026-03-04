# Makefile – CDM some-linux-x86_64-qemu
#
# Targets:
#   make image          – build bzImage + rootfs.cpio.gz (native, requires Buildroot deps)
#   make docker-builder – build the Docker toolchain image
#   make docker-image   – build the QEMU image via Docker (no local toolchain needed)
#   make run            – launch QEMU with deploy/bzImage
#   make toolchain      – download Buildroot and open menuconfig
#   make clean          – remove deploy/ and native build output
#   make distclean      – also remove the downloaded Buildroot source tree

BUILDROOT_VERSION  := 2024.02.7
BUILDROOT_DIR      := buildroot-$(BUILDROOT_VERSION)
BUILDROOT_URL      := https://buildroot.org/downloads/$(BUILDROOT_DIR).tar.gz
BUILD_DIR          := $(CURDIR)/$(BUILDROOT_DIR)
OUTPUT_DIR         := $(CURDIR)/output
DEPLOY_DIR         := $(CURDIR)/deploy
DOCKER_IMAGE       := cdm-qemu-builder

.PHONY: all image docker-builder docker-image run toolchain clean distclean

all: image

# ── Native: download Buildroot ────────────────────────────────────────────────
$(BUILDROOT_DIR)/.extracted:
	@echo ">>> Downloading Buildroot $(BUILDROOT_VERSION)..."
	curl -fL $(BUILDROOT_URL) | tar xz
	touch $(BUILDROOT_DIR)/.extracted

# ── Native: configure (menuconfig) ───────────────────────────────────────────
toolchain: $(BUILDROOT_DIR)/.extracted
	cp buildroot.config $(BUILD_DIR)/.config
	$(MAKE) -C $(BUILD_DIR) menuconfig

# ── Native: build image ───────────────────────────────────────────────────────
image: $(BUILDROOT_DIR)/.extracted
	@echo ">>> Building CDM Linux image (this may take ~10–20 min on first run)..."
	mkdir -p $(OUTPUT_DIR)
	cp buildroot.config $(OUTPUT_DIR)/.config
	$(MAKE) -C $(BUILD_DIR) O=$(OUTPUT_DIR) olddefconfig
	$(MAKE) -C $(BUILD_DIR) O=$(OUTPUT_DIR) -j$(shell nproc)
	mkdir -p $(DEPLOY_DIR)
	cp $(OUTPUT_DIR)/images/bzImage        $(DEPLOY_DIR)/bzImage
	cp $(OUTPUT_DIR)/images/rootfs.cpio.gz $(DEPLOY_DIR)/rootfs.cpio.gz
	@echo ">>> Build complete. Images in deploy/"

# ── Docker: build toolchain image ─────────────────────────────────────────────
docker-builder:
	docker build -t $(DOCKER_IMAGE) .

# ── Docker: build QEMU image (mounts current dir, writes to deploy/) ──────────
docker-image:
	docker run --rm -v "$(CURDIR):/workspace" $(DOCKER_IMAGE)

# ── Run in QEMU ───────────────────────────────────────────────────────────────
run:
	@[ -f deploy/bzImage ] || (echo "Run 'make image' or 'make docker-image' first." && exit 1)
	@./run-qemu.sh

# ── Cleanup ───────────────────────────────────────────────────────────────────
clean:
	rm -rf deploy output

distclean: clean
	rm -rf $(BUILDROOT_DIR)
