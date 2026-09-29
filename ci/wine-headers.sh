#!/bin/bash
# CI: the configured Wine tree the iOS unix-side builds read (config.h and the widl-generated
# headers). The scripts under build/ assume wine/build-macos already exists; the repository
# does not record how it was configured, so this is a plain macOS configure plus
# `make include/all` (every generated header, including the dwrite/mfobjects ones
# build/ntdll-unix/build.sh looks for).
set -euo pipefail
R="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TC="$R/toolchains/llvm-mingw-20260421-ucrt-macos-universal/bin"
export PATH="$TC:$(brew --prefix bison)/bin:$(brew --prefix flex)/bin:$PATH"
JOBS="${JOBS:-$(sysctl -n hw.ncpu)}"
B="$R/wine/build-macos"

if [ ! -f "$B/config.status" ]; then
    mkdir -p "$B"
    (cd "$B" && ../configure --without-x --disable-tests --enable-winegstreamer \
        --without-freetype --without-gnutls --without-vulkan --without-gstreamer \
        --without-sdl --without-cups --without-sane --without-krb5 --without-pcap \
        --without-usb --without-v4l2 --without-opencl --without-pcsclite) \
        > "$R/ci-logs/wine-macos-configure.log" 2>&1 \
        || { tail -40 "$R/ci-logs/wine-macos-configure.log"; exit 1; }
fi
make -C "$B" -j"$JOBS" include/all > "$R/ci-logs/wine-macos-include.log" 2>&1 \
    || { tail -60 "$R/ci-logs/wine-macos-include.log"; exit 1; }

# build/ntdll-unix/build.sh reads dwrite.h/dwrite_3.h from the arm64ec tree's include dir.
# They are architecture-independent widl output, so point that path at this tree.
if [ ! -e "$R/wine/build-arm64ec/include" ]; then
    mkdir -p "$R/wine/build-arm64ec"
    ln -s ../build-macos/include "$R/wine/build-arm64ec/include"
fi
ls "$B/include/config.h" "$B/include/dwrite.h" "$B/include/mfobjects.h"
