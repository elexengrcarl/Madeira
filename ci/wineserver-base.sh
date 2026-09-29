#!/bin/bash
# CI: the base libwineserver.a that build/wineserver/build.sh patches.
#
# That script swaps its patched objects into an existing archive ("ERROR: No base
# libwineserver.a found" otherwise), and the archive is git-ignored, so a clean checkout
# cannot build it. This compiles every wine/server/*.c the script does NOT rebuild itself,
# with the script's own flags, into app/Madeira/libwineserver.a. build.sh then adds the
# patched objects and applies its symbol renames.
set -euo pipefail
R="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_DIR="$R/build/wineserver"
WINE_SRC="$R/wine"
SDK=$(xcrun --sdk iphoneos --show-sdk-path)
OBJ="$R/build/wineserver/obj-base"
OUT="$R/app/Madeira/libwineserver.a"
rm -rf "$OBJ" && mkdir -p "$OBJ"

# Keep in step with CC_FLAGS in build/wineserver/build.sh.
CC_FLAGS=(
    -arch arm64 -isysroot "$SDK" -miphoneos-version-min=17.0 -O2
    -I"$WINE_SRC/include" -I"$WINE_SRC/include/wine"
    -I"$WINE_SRC/build-macos/include"
    -I"$BUILD_DIR" -I"$WINE_SRC/server"
    -I"$R/build/ntdll-unix/shims"
    -I"$R/build/madsync" -DHAVE_LINUX_NTSYNC_H=1
    -include "$BUILD_DIR/config_ios.h"
    -include stdarg.h
    -include "$BUILD_DIR/unicode_fix.h"
    -include "$BUILD_DIR/wineserver_ios_kill.h"
    -DBINDIR=\"/usr/local/bin\" -DDATADIR=\"/usr/local/share\"
    -D__WINESRC__ -DWINE_IOS=1
    -Dmain=wineserver_main
    -Wno-implicit-function-declaration
)

# Sources build.sh compiles itself (PATCHED_FILES), by the object name they replace.
REBUILT=" request main mach unicode fd object event handle async process window user mapping
          class region queue winstation thread inproc_sync sock "

failed=()
n=0
for src in "$WINE_SRC"/server/*.c; do
    name=$(basename "$src" .c)
    case "$REBUILT" in *" $name "*) continue ;; esac
    if xcrun -sdk iphoneos clang "${CC_FLAGS[@]}" -c "$src" -o "$OBJ/$name.o" 2>"$OBJ/$name.err"; then
        n=$((n + 1))
    else
        failed+=("$name")
        echo "---- $name"; head -20 "$OBJ/$name.err"
    fi
done
echo "base wineserver: $n objects compiled, ${#failed[@]} failed: ${failed[*]:-}"
[ ${#failed[@]} -eq 0 ] || exit 1
rm -f "$OUT"
ar rcs "$OUT" "$OBJ"/*.o
ls -l "$OUT"
