#!/usr/bin/make -f

UID ?= $(shell id -u)
GID ?= $(shell id -g)
MAKEFILE_PATH ?= $(abspath $(lastword $(MAKEFILE_LIST)))
MAKEFILE_DIR ?= $(dir $(MAKEFILE_PATH))
BUILD_DIR ?= build
export BUILD_DIR
INSTALL_DESTINATION ?= 10.11.99.1
# Installed app directory (where the Vellum package deploys netsurf). make install
# deploys here so it matches production and never writes the divergent ~/.netsurf,
# which (being first in NETSURF_FB_RESPATH) would otherwise shadow shipped resources.
APP_DIR ?= /home/root/xovi/exthome/appload/netsurf
IMAGE_TAG ?= latest
CLANGD_CONTAINER ?= netsurf-clangd

# Target device architecture.
#   armv7   - reMarkable 1 / 2
#   aarch64 - reMarkable Paper Pro ("Ferrari", i.MX8MM)
# The Paper Pro has no 32-bit loader and no armhf libraries, so an armv7 binary
# fails there with "Exec format error"; it needs a native aarch64 build. The
# toolchain image bakes in whichever triple is selected here, so `make image`
# must be re-run after changing ARCH.
ARCH ?= armv7

ifeq ($(ARCH), aarch64)
    TC_DIR := aarch64-remarkable-linux-gnu
    TC_PREFIX := aarch64-remarkable-linux-gnu
else ifeq ($(ARCH), armv7)
    TC_DIR := arm-remarkable-linux-gnueabihf
    TC_PREFIX := arm-linux-gnueabihf
else
    $(error ARCH must be armv7 or aarch64, got '$(ARCH)')
endif

# The toltec toolchain images are published for linux/amd64 only, so an arm64
# host (Apple Silicon) has to run them emulated rather than natively.
DOCKER_PLATFORM ?= linux/amd64

UNAME_S := $(shell uname -s)
ifeq ($(UNAME_S), Darwin)
    USE_VOLUME_MOUNT ?= YES
else
	USE_VOLUME_MOUNT ?= NO
endif

.PHONY: help all clean build install uninstall image copy-resources copy-binary remove-resources remove-binary checkout clangd-build clangd-start clangd-stop

help:
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-20s\033[0m %s\n", $$1, $$2}'

all: help ## Print this help

clean: ## Clean build directory, build volume and clangd container
	rm -rf $(BUILD_DIR)
	docker volume rm -f netsurf-build
	docker rm -f $(CLANGD_CONTAINER)

ifeq ($(USE_VOLUME_MOUNT), NO)
build: ## Build netsurf in Docker container (bind mount BUILD_DIR as build directory)
	mkdir -p $(BUILD_DIR)
	docker run --rm --platform $(DOCKER_PLATFORM) \
	    --mount type=bind,source=$(MAKEFILE_DIR)/scripts,target=/opt/netsurf/scripts,readonly \
	    --mount type=bind,source=$(MAKEFILE_DIR)/$(BUILD_DIR),target=/opt/netsurf/build \
	    -e TARGET_WORKSPACE=/opt/netsurf/build \
	    --user=$(UID):$(GID) netsurf-build:$(IMAGE_TAG) \
	    /opt/netsurf/scripts/build.sh
else
build: ## Build netsurf in Docker container (volume mount build directory except BUILD_DIR/netsurf, select with USE_VOLUME_MOUNT=YES)
	$(info Using volume mount for build directory)
# Workaround: clone all bind-mounted repositories outside the container, 
# because we need the folders to exist before the container starts for mounting them.
# Only call setup if BUILD_DIR does not exist yet.
	if [ ! -d $(BUILD_DIR) ]; then mkdir -p $(BUILD_DIR) && scripts/setup_local_development.sh versioned; fi
# chown the build directory volume to the current user, so the build can run as current user
	docker run --rm --platform $(DOCKER_PLATFORM) \
		--mount type=volume,source=netsurf-build,target=/opt/netsurf/build \
	    netsurf-build:$(IMAGE_TAG) \
		chown -R $(UID):$(GID) /opt/netsurf/build
	docker run --rm --platform $(DOCKER_PLATFORM) \
	    --mount type=bind,source=$(MAKEFILE_DIR)/scripts,target=/opt/netsurf/scripts,readonly \
	    --mount type=volume,source=netsurf-build,target=/opt/netsurf/build \
	    --mount type=bind,source=$(MAKEFILE_DIR)/$(BUILD_DIR)/netsurf,target=/opt/netsurf/build/netsurf \
	    --mount type=bind,source=$(MAKEFILE_DIR)/$(BUILD_DIR)/libnsfb,target=/opt/netsurf/build/libnsfb \
	    -e TARGET_WORKSPACE=/opt/netsurf/build \
	    --user=$(UID):$(GID) netsurf-build:$(IMAGE_TAG) \
	    /opt/netsurf/scripts/build.sh
endif

install: image build copy-resources copy-binary ## Build and copy binary and resources to device

uninstall: remove-resources remove-binary ## Uninstall binary and resources from device

image: ## Build the Docker image that is used for building netsurf
	docker build --platform $(DOCKER_PLATFORM) \
	    --build-arg TC_DIR=$(TC_DIR) --build-arg TC_PREFIX=$(TC_PREFIX) \
	    -t netsurf-build:$(IMAGE_TAG) .

copy-resources: ## Copy resources into the installed app dir
	ssh root@$(INSTALL_DESTINATION) "mkdir -p $(APP_DIR)/res"
	scp -r $(BUILD_DIR)/netsurf/frontends/framebuffer/res/* root@$(INSTALL_DESTINATION):$(APP_DIR)/res/
	scp example/Choices root@$(INSTALL_DESTINATION):$(APP_DIR)/res/Choices

copy-binary: ## Copy binary into the installed app dir (backs up the existing one)
	ssh root@$(INSTALL_DESTINATION) '[ -e $(APP_DIR)/netsurf ] && cp -a $(APP_DIR)/netsurf $(APP_DIR)/netsurf.bak || true'
	scp $(BUILD_DIR)/netsurf/nsfb root@$(INSTALL_DESTINATION):$(APP_DIR)/netsurf

remove-resources: ## Resources are provided by the Vellum package; nothing to remove
	@echo "Resources are managed by the Vellum package; nothing to remove."

remove-binary: ## Restore the binary backup made by copy-binary
	ssh root@$(INSTALL_DESTINATION) '[ -e $(APP_DIR)/netsurf.bak ] && mv $(APP_DIR)/netsurf.bak $(APP_DIR)/netsurf || echo "no backup to restore"'

checkout: clean ## [Dev] Clean build directory and check out HEAD of forked repositories
	scripts/setup_local_development.sh head

clangd-build: ## [Dev] Prepare local dev container with clangd and compile-commands.json (Note: run checkout first to use HEAD)
	mkdir -p $(BUILD_DIR)
	docker rm -f $(CLANGD_CONTAINER)
	docker build -t netsurf-localdev -f Dockerfile.localdev .
	docker run --rm --platform $(DOCKER_PLATFORM) \
		--mount type=bind,source=$(MAKEFILE_DIR)/$(BUILD_DIR),target=/opt/netsurf/build \
	    netsurf-localdev:latest \
		chown -R $(UID):$(GID) /opt/netsurf/build
	docker run --rm --platform $(DOCKER_PLATFORM) \
		--mount type=bind,source=$(MAKEFILE_DIR)/scripts,target=/opt/netsurf/scripts \
		--mount type=bind,source=$(MAKEFILE_DIR)/$(BUILD_DIR),target=/opt/netsurf/build \
		-e TARGET_WORKSPACE=/opt/netsurf/build \
		-e MAKE="bear --append -- make" \
		--user=$(UID):$(GID) netsurf-localdev:latest \
		sh -c "cd /opt/netsurf/build && /opt/netsurf/scripts/build.sh"

clangd-start: ## [Dev] Start the local development docker container with clangd set up
	$(info To access clangd-container, you can use scripts/clangd_docker.sh.)
	docker run --detach --platform $(DOCKER_PLATFORM) --name netsurf-clangd \
		--mount type=bind,source=$(MAKEFILE_DIR)/scripts,target=/opt/netsurf/scripts \
		--mount type=bind,source=$(MAKEFILE_DIR)/$(BUILD_DIR),target=/opt/netsurf/build \
		-p 50505:50505 \
		--user=$(UID):$(GID) netsurf-localdev:latest \
		tail -f /dev/null
# Requires sudo to be able to copy the x-tools directory recursively to host
	sudo docker cp -a netsurf-clangd:/opt/x-tools \
		$(MAKEFILE_DIR)/$(BUILD_DIR)
# Change ownership to curent user and add write permission, so we don't need sudo for later deletion
	sudo chown -R $(UID):$(GID) $(BUILD_DIR)/x-tools
	chmod -R +w $(BUILD_DIR)/x-tools

clangd-stop: ## [Dev] Stop the local development docker container
	docker rm -f netsurf-clangd
