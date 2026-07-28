FROM ghcr.io/toltec-dev/rust:v4.0

# Target architecture. The reMarkable 1 and 2 are armv7; the Paper Pro
# ("Ferrari", i.MX8MM) is aarch64 and has no 32-bit loader or armhf libs at all,
# so an armv7 binary dies there with "Exec format error". The VELBUILD recipe
# builds both (arch="armv7 aarch64") by sourcing the matching switch script, and
# every build script here is already driven by $CHOST/$CROSS_COMPILE, so
# selecting the toolchain is the only arch-specific decision.
#
# TC_DIR is the toolchain directory under /opt/x-tools; TC_PREFIX is the tool
# prefix. They are NOT always the same string -- armv7's tools are reached via
# the shorter compatibility alias -- so they are separate args.
#
#   armv7   (rM1/rM2)    TC_DIR=arm-remarkable-linux-gnueabihf TC_PREFIX=arm-linux-gnueabihf
#   aarch64 (Paper Pro)  TC_DIR=aarch64-remarkable-linux-gnu   TC_PREFIX=aarch64-remarkable-linux-gnu
#
# Values mirror /opt/x-tools/switch-{arm,aarch64}.sh. Use `make image ARCH=...`
# rather than setting these by hand.
ARG TC_DIR=arm-remarkable-linux-gnueabihf
ARG TC_PREFIX=arm-linux-gnueabihf

# base:v3.1 (Debian unstable/sid frozen in 2023) baked these in as image-level
# ENV; rust:v4.0 (Debian 12/bookworm) instead ships them in the switch scripts
# for opt-in sourcing. Bake the same values in here so both this Dockerfile's
# RUN steps and any container later started from the built image (e.g. `make build`
# invoking scripts/build.sh) see them without having to source that script.
ENV PATH="$PATH:/opt/x-tools/${TC_DIR}/bin" \
    CHOST="${TC_PREFIX}" \
    CROSS_COMPILE="${TC_PREFIX}-" \
    PKG_CONFIG_LIBDIR="/opt/x-tools/${TC_DIR}/${TC_DIR}/sysroot/usr/lib/pkgconfig:/opt/x-tools/${TC_DIR}/${TC_DIR}/sysroot/lib/pkgconfig:/opt/x-tools/${TC_DIR}/${TC_DIR}/sysroot/opt/lib/pkgconfig" \
    PKG_CONFIG_SYSROOT_DIR="/opt/x-tools/${TC_DIR}/${TC_DIR}/sysroot" \
    SYSROOT="/opt/x-tools/${TC_DIR}/${TC_DIR}/sysroot"

# libexpat-dev was renamed to libexpat1-dev between Debian sid (2023 snapshot
# in base:v3.1) and bookworm (rust:v4.0).
RUN apt-get update -y && apt-get install -y bison flex libexpat1-dev libpng-dev git gperf automake libtool

ADD scripts/install_dependencies.sh install_dependencies.sh

# install_dependencies.sh builds a static libevdev, but the sysroot also ships
# a prebuilt libevdev.so.2 that the linker would otherwise prefer; remove it so
# the static archive is used.
RUN rm -f "$SYSROOT"/usr/lib/libevdev.so* \
    && ./install_dependencies.sh

# Optional image-format libs gained by latest upstream NetSurf (WEBP, JPEG-XL).
# Separate layer so the base-deps layer above stays cached. libwebp + libjxl
# (+ its static deps highway/brotli) are cross-built static; the device ships
# neither, so they are baked into nsfb (libstdc++/libgcc_s stay dynamic).
ADD scripts/install_image_libs.sh install_image_libs.sh
RUN ./install_image_libs.sh
