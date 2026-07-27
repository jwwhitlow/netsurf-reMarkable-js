#!/bin/bash

# Build script which sets up environment variables appropriately so cross-compilation
# works inside the docker container.

# This script should also be runnable on the host system itself, if SYSROOT is configured appropriately,
# but that has not been tested.

SCRIPTPATH="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
# env.sh requires ${HOST}-gcc -dumpmachine to equal $HOST exactly; CROSS_COMPILE
# (set by /opt/x-tools/switch-{arm,aarch64}.sh) isn't always that string itself
# (e.g. armv7's CROSS_COMPILE is a shorter compatibility alias), so ask the
# compiler what it actually is instead of guessing/hardcoding a triple.
HOST="$("${CROSS_COMPILE}gcc" -dumpmachine)"

if [ -z "$TARGET_WORKSPACE" ]; then echo "TARGET_WORKSPACE is required, but not set." && exit 1; fi

if [ -z "$MAKE" ]; then export MAKE=make; fi

source $SCRIPTPATH/versions.sh
source $SCRIPTPATH/env.sh

# Required so the netsurf make picks up the previously built libraries
export CFLAGS="$CFLAGS -I$TARGET_WORKSPACE/inst-$HOST/include"
# upstream idna.c switched to <utf8proc.h>; NetSurf libutf8proc mirror installs it under include/libutf8proc/
export CFLAGS="$CFLAGS -I$TARGET_WORKSPACE/inst-$HOST/include/libutf8proc"
export LDFLAGS="$LDFLAGS -L$TARGET_WORKSPACE/inst-$HOST/lib" 
# freetype libs end up in /usr/local, so include that for pkg-config
export PKG_CONFIG_LIBDIR="$PKG_CONFIG_LIBDIR:$SYSROOT/usr/local/lib/pkgconfig"

# For local development, you can clone any repository into target workspace
# before running this script
ns-clone
ns-make-tools install
ns-make-libs install

cd $TARGET_WORKSPACE/netsurf/

# Would probably be nicer to to pkg_config libevdev in the netsurf Makefile,
# but we are re-pulling that Makefile every build.
# This works for now.
# --whole-archive pulls in all of static libevdev regardless of where the
# linker places -levdev relative to libnsfb (which references it); without it
# the link fails with undefined references to libevdev_* now that libevdev is
# statically linked rather than resolved from a shared lib.
export LDFLAGS="$LDFLAGS -Wl,--whole-archive -levdev -Wl,--no-whole-archive -lpthread"

# WebP + JPEG-XL are statically linked from the sysroot. NetSurf calls pkg-config
# without --static, so only -lwebp / -ljxl are emitted; spell out the transitive
# static deps here. --start-group resolves the jxl<->hwy<->brotli<->skcms cross-refs.
# libstdc++ / libgcc_s are present on the device, so they stay dynamic.
export LDFLAGS="$LDFLAGS -Wl,--start-group -ljxl -ljxl_cms -lhwy -lbrotlienc -lbrotlidec -lbrotlicommon -lsharpyuv -Wl,--end-group -lstdc++"

export CC="${CROSS_COMPILE}gcc"
export STRIP="${CROSS_COMPILE}strip"
# NETSURF_USE_DUKTAPE=YES compiles in the Duktape engine plus the DOM bindings
# nsgenbind generates from the .bnd/WebIDL files. This is only half the switch:
# desktop/options.h defaults enable_javascript to false, so example/Choices has
# to set it to 1 as well or a Duktape build still runs with scripting off.
$MAKE TARGET=framebuffer NETSURF_FB_FONTLIB=freetype NETSURF_STRIP_BINARY=YES NETSURF_USE_LIBICONV_PLUG=NO NETSURF_USE_DUKTAPE=YES NETSURF_REMARKABLE=YES
