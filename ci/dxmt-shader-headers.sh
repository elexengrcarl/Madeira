#!/bin/bash
# CI: the embedded AIR shaders airconv includes (air_msad.h, air_samplepos.h, air_tessellation.h).
#
# research/dxmt/src/airconv/meson.build builds them with metalir_generator + hexdump_generator
# (research/dxmt/meson.build); build/dxmt-ios/build.sh generates only dxmt_command.h and expects
# these three in its shader-headers include dir already. Same commands, same symbol names.
set -euo pipefail
R="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT="$R/build/dxmt-ios/shader-headers"
mkdir -p "$OUT"
for name in air_msad air_samplepos air_tessellation; do
    (cd "$OUT" \
     && xcrun -sdk macosx metal -o "$name.air" -c "$R/research/dxmt/src/airconv/shaders/$name.metal" \
            -std=metal3.1 --target=air64-apple-macos14.0 \
     && xxd -n "$name" -i "$name.air" "$name.h")
    echo "  $name.h ($(wc -c < "$OUT/$name.air" | tr -d ' ') bytes of AIR)"
done
