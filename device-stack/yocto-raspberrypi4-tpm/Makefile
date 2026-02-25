# Makefile – CDM yocto-raspberrypi4-tpm

DOCKER_IMAGE := cdm-yocto-rpi4-tpm-builder
DEPLOY_DIR   := $(CURDIR)/deploy

DL_DIR     ?= $(HOME)/.yocto/downloads
SSTATE_DIR ?= $(HOME)/.yocto/sstate-cache

.PHONY: all docker-builder docker-image flash clean distclean

all: docker-image

docker-builder:
	docker build -t $(DOCKER_IMAGE) .

docker-image:
	@mkdir -p "$(DL_DIR)" "$(SSTATE_DIR)"
	docker run --rm \
	    -v "$(CURDIR):/workspace" \
	    -v "$(DL_DIR):/yocto/downloads" \
	    -v "$(SSTATE_DIR):/yocto/sstate-cache" \
	    $(DOCKER_IMAGE)

flash:
	@IMAGE=$$(ls $(DEPLOY_DIR)/cdm-image-rpi4-tpm-raspberrypi4-64*.wic.bz2 2>/dev/null | head -1); \
	[ -n "$$IMAGE" ] || (echo "Run 'make docker-image' first." && exit 1); \
	read -p "Flash $$IMAGE to which device? (e.g. /dev/sdb): " DEV; \
	[ -n "$$DEV" ] || exit 1; \
	echo "Flashing to $$DEV ..."; \
	bzip2 -dc "$$IMAGE" | sudo dd of="$$DEV" bs=4M status=progress conv=fsync

clean:
	rm -rf $(DEPLOY_DIR)

distclean: clean
	@echo "Remove $(DL_DIR) and $(SSTATE_DIR)? [y/N] "; \
	read ans; [ "$$ans" = "y" ] || exit 0; \
	rm -rf "$(DL_DIR)" "$(SSTATE_DIR)"
