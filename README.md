# NetSurf-reMarkable [![Build for reMarkable](https://github.com/MaicroNotHard/netsurf-reMarkable/actions/workflows/build.yml/badge.svg)](https://github.com/MaicroNotHard/netsurf-reMarkable/actions/workflows/build.yml)[![rm1](https://img.shields.io/badge/rM1-supported-green)](https://remarkable.com/store/remarkable)[![rm2](https://img.shields.io/badge/rM2-supported-green)](https://remarkable.com/store/remarkable-2)[![opkg](https://img.shields.io/badge/OPKG-netsurf-blue)](https://toltec-dev.org/)

> **_NOTE:_**  The original author (alex0809) no longer owns a reMarkable and is no longer maintaining the upstream repository, as they can't validate changes. This fork is maintained by MaicroNotHard.

NetSurf is a lightweight and portable open-source web browser. This project adapts NetSurf for the reMarkable E Ink tablet.
This repository contains the code for to building and releasing new versions.

## Installation

### Vellum (recommended)

[Vellum](https://github.com/vellum-dev/vellum) is the actively maintained package manager for the reMarkable. A VELBUILD recipe for NetSurf (built from this fork, with fonts fetched from upstream DejaVu releases at build time) lives in [MaicroNotHard/vellum](https://github.com/MaicroNotHard/vellum) under `packages/netsurf`.

Until the package is published in the official Vellum index, build and sideload it yourself:

```
git clone https://github.com/MaicroNotHard/vellum
cd vellum
./scripts/build-package.sh netsurf armv7
```

Copy the resulting `dist/armv7/netsurf-*.apk` to the device and install it with [vellum-cli](https://github.com/vellum-dev/vellum-cli):

```
scp dist/armv7/netsurf-*.apk root@10.11.99.1:/tmp/
ssh root@10.11.99.1 /home/root/.vellum/bin/vellum add --allow-untrusted /tmp/netsurf-*.apk
```

Once the package is published in the index, installation will simply be `vellum install netsurf`.

### Toltec (legacy)

> **_NOTE:_** This install path predates the Vellum recipe above and has not been tested against this fork recently - it's kept here for historical reference. We recommend installing via Vellum.

You can install neturf with [Toltec](https://toltec-dev.org) using the following command:

```
opkg install netsurf
```

### Github Release

On the [releases page](https://github.com/alex0809/netsurf-reMarkable/releases), you can find the latest release.
The release assets contain a file `netsurf_[version]_rmall.ipk` that allows for easy installation on device.

Example commands to download and install the ipk file:
```
version=0.4
wget https://github.com/alex0809/netsurf-reMarkable/releases/download/v$version/netsurf_$version-1_rmall.ipk
scp netsurf_$version-1_rmall.ipk root@10.11.99.1:
ssh root@remarkable opkg install netsurf_$version-1_rmall.ipk
```

To install a different release change the `version=` line to the version number for the release you wish to install.

## Usage

The 'a' in the bottom-right corner screen toggles the keyboard.

More usage information may be found on the [official NetSurf website](https://www.netsurf-browser.org/documentation/#User).

## JavaScript

This branch builds with JavaScript **enabled**. Upstream (and every reMarkable fork before it) shipped
`NETSURF_USE_DUKTAPE=NO`, so the engine was compiled out entirely.

Scripting is gated twice in NetSurf and both gates have to move:

- `scripts/build.sh` — `NETSURF_USE_DUKTAPE=YES` compiles in the engine and the `nsgenbind`-generated bindings.
- `example/Choices` — `enable_javascript:1`. The compiled-in default in `desktop/options.h` is `false`, so a
  Duktape build still runs with scripting off unless `Choices` says otherwise.

### What this actually gets you

Be realistic before relying on it. NetSurf's engine is [Duktape](https://duktape.org/), an **ES5.1**
interpreter, driven by 67 WebIDL binding files.

**Works:** DOM traversal and mutation, `getElementById` / `querySelector`, `createElement`, `classList`
(`DOMTokenList`), CSSOM (`CSSRule` / `CSSStyleSheet`), most `HTML*Element` interfaces, `addEventListener`,
`KeyboardEvent`, `Location`, `Navigator`, `console`, `JSON`, `<canvas>` 2D, form access and validation.

**Absent — verified against the binding set, not merely untested:**

| API | Consequence |
| --- | --- |
| `XMLHttpRequest`, `fetch` | No AJAX of any kind. |
| `Promise` | No `async`/`await`. |
| `WebSocket` | No live connections. |
| `localStorage` / `sessionStorage` | No client-side persistence. |
| `Worker` | No background threads. |

One polyfill ships (`Array.from`). ES6+ syntax — arrow functions, `let`/`const`, classes, template literals —
is a **parse error** to an ES5.1 interpreter, so a modern bundle fails at load rather than degrading.

The practical line: this runs **scripted pages**, not **web apps**. Progressive-enhancement sites, form
validation, menus and canvas work. Anything built on React/Vue/Angular, or that fetches JSON to render
itself, will not — and no configuration changes that, because it is the engine. A browser for modern sites
on the reMarkable needs a WebKit-family engine (e.g. WPE) instead.

### Verifying

`example/jstest.html` is a probe page that reports which APIs the built binary actually exposes. Copy it to
the device and open it with a `file:///` URL. It is deliberately written in strict ES5: a single ES6 token
would be a parse error and the page would report nothing at all.

If you are upgrading an existing install and keeping your old config, set the flag by hand rather than
letting `make install` overwrite `Choices` — and do it while NetSurf is not running, since it rewrites the
file on exit:

```sh
ssh root@<device> "sed -i 's/^enable_javascript:0/enable_javascript:1/' <path-to>/Choices"
```

### Local build and installation

#### Requirements

The build itself is done in a Docker container, so apart from Docker and make, there
should be no additional requirements.

`make` prints a list of all available commands by default.

#### Build

`make image` to build the Docker image with the toolchain, then `make build` to build netsurf.
The resulting netsurf binary is `build/netsurf/nsfb`.

> MacOS note:
> There is an [open issue](https://github.com/alex0809/netsurf-reMarkable/issues/21) with the build when using a bind-mounted build directory.
> A workaround will be automatically enabled when running `make build` under MacOS, please see the ticket for details.

#### Installation

`make install` to build and then install the updated binary to the device.
This will use `scp` to copy the binary and required files to the device.
Device address used is by default `10.11.99.1` (i.e. reMarkable connected to your PC via USB), but can be overridden with the `INSTALL_DESTINATION` variable.
The netsurf binary and resources are copied into the installed app directory `/home/root/xovi/exthome/appload/netsurf/` (matching where the Vellum package installs them); the existing binary is backed up to `netsurf.bak`. `make uninstall` restores that backup.

The font files defined in the configuration file `res/Choices` must exist on the device.
Install the NetSurf Vellum package first so its fonts are present under the app dir's `res/fonts/`, or copy your own fonts there and adapt `Choices`.

Installation of pre-configured fonts:
```
opkg install dejavu-fonts-ttf-DejaVuSans dejavu-fonts-ttf-DejaVuSans-Bold dejavu-fonts-ttf-DejaVuSans-BoldOblique dejavu-fonts-ttf-DejaVuSans-Oblique dejavu-fonts-ttf-DejaVuSerif dejavu-fonts-ttf-DejaVuSerif-Bold dejavu-fonts-ttf-DejaVuSerif-Italic dejavu-fonts-ttf-DejaVuSansMono dejavu-fonts-ttf-DejaVuSansMono-Bold
```

`make uninstall` to remove the binary and other installed files from the device.

## Local development

`make checkout` to set up the workspace for local development.
This will prepare the `build/` directory by cloning the HEAD of all forked code repositories.

The build script (called when running `make build`) will only clone missing repositories,
so any local changes will be picked up with the next build.

To use clangd language server, you can run `make clangd-build`, which will prepare a Docker container
clangd and compile-commands set up.
After the build is complete, you can can start the container with `make clangd-start`, and access with
[clangd_docker.sh](scripts/clangd_docker.sh).

For running a locally-built binary on the tablet and capturing before/after
screenshots, see [docs/on-device-testing.md](docs/on-device-testing.md).

## Related repositories

- [libnsfb-reMarkable](https://github.com/MaicroNotHard/libnsfb-reMarkable): fork of libnsfb with reMarkable-specific code for drawing to the screen and input handling
- [netsurf](https://github.com/MaicroNotHard/netsurf): fork of netsurf-browser/netsurf, with the reMarkable framebuffer port on top
