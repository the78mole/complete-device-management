# Makefile – CDM yocto-raspberrypi4
#
# Targets:
#   make docker-builder  – build the Docker toolchain image (once, ~10 min)
#   make docker-image    – build the RPi 4 image via Docker
#   make run             – flash deploy/*.wic.bz2 to an SD card (interactive)
#   make clean           – remove deploy/
#   make distclean       – also remove local Yocto cache dirs

DOCKER_IMAGE   := cdm-yocto-rpi4-builder
DEPLOY_DIR     := $(CURDIR)/deploy

# Optional: host-side persistent caches (avoids re-downloading on each build)
DL_DIR         ?= $(HOME)/.yocto/downloads
SSTATE_DIR     ?= $(HOME)/.yocto/sstate-cache

.PHONY: all docker-builder docker-image run flash clean distclean

all: docker-image

# ── Docker: build toolchain image ─────────────────────────────────────────────
docker-builder:
	docker build -t $(DOCKER_IMAGE) .

# ── Docker: build RPi 4 image ─────────────────────────────────────────────────
# Mounts:
#   /workspace          ← current directory (conf/, meta-cdm/, deploy/ written here)
#   /yocto/downloads    ← persistent download cache (optional but recommended)
#   /yocto/sstate-cache ← persistent sstate cache  (optional but recommended)
docker-image:
	@mkdir -p "$(DL_DIR)" "$(SSTATE_DIR)"
	docker run --rm \
	    -v "$(CURDIR):/workspace" \
	    -v "$(DL_DIR):/yocto/downloads" \
	    -v "$(SSTATE_DIR):/yocto/sstate-cache" \
	    $(DOCKER_IMAGE)

# ── Flash to SD card ──────────────────────────────────────────────────────────
flash:
	@IMAGE=$$(ls $(DEPLOY_DIR)/cdm-image-rpi4-raspberrypi4-64*.wic.bz2 2>/dev/null | head -1); \
	[ -n "$$IMAGE" ] || (echo "Run 'make docker-image' first." && exit 1); \
	read -p "Flash $$IMAGE to which device? (e.g. /dev/sdb): " DEV; \
	[ -n "$$DEV" ] || exit 1; \
	echo "Flashing to $$DEV ..."; \
	bzip2 -dc "$$IMAGE" | sudo dd of="$$DEV" bs=4M status=progress conv=fsync

# ── Cleanup ───────────────────────────────────────────────────────────────────
clean:
	rm -rf $(DEPLOY_DIR)

distclean: clean
	@echo "Remove $(DL_DIR) and $(SSTATE_DIR)? [y/N] "; \
	read ans; [ "$$ans" = "y" ] || exit 0; \
	rm -rf "$(DL_DIR)" "$(SSTATE_DIR)"
