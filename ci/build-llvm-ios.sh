#!/bin/bash
# CI: LLVM 15 static libraries for iOS arm64, which DXMT's shader compiler (airconv) links.
#
# build/dxmt-ios/README.md describes the recipe but the repository has no script for it:
#   1. a host build of llvm-tblgen;
#   2. the iOS libraries, reusing that tblgen, with no targets, tools or utils;
#   3. AddLLVM.cmake taught that iOS links with -dead_strip, not --gc-sections.
# Outputs toolchains/llvm-ios-build/{lib,include} and toolchains/llvm-project/llvm/include,
# the three paths build/dxmt-ios/build.sh reads.
set -euo pipefail
R="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
T="$R/toolchains"
V="${LLVM_VERSION:-15.0.7}"
JOBS="${JOBS:-$(sysctl -n hw.ncpu)}"
mkdir -p "$T"

if [ ! -d "$T/llvm-project/llvm" ]; then
    echo "== fetching llvm-project $V"
    curl -fsSL "https://github.com/llvm/llvm-project/releases/download/llvmorg-$V/llvm-project-$V.src.tar.xz" \
        | tar -xJ -C "$T"
    mv "$T/llvm-project-$V.src" "$T/llvm-project"
fi

python3 - "$T/llvm-project/llvm/cmake/modules/AddLLVM.cmake" <<'PY'
import re, sys
p = sys.argv[1]
s = open(p).read()
pat = re.compile(r'(if\(\$\{CMAKE_SYSTEM_NAME\} MATCHES ")Darwin("\)\s*\n\s*set_property\(TARGET \$\{target_name\} APPEND_STRING PROPERTY\s*\n\s*LINK_FLAGS " -Wl,-dead_strip"\))')
s2, n = pat.subn(r'\1Darwin|iOS\2', s)
if n == 0 and 'MATCHES "Darwin|iOS")' in s:
    print("AddLLVM.cmake: already patched")
elif n != 1:
    sys.exit(f"AddLLVM.cmake: expected one -dead_strip block, found {n}")
else:
    open(p, "w").write(s2)
    print("AddLLVM.cmake: -dead_strip now also used for iOS")
PY

COMMON=(-G Ninja -DCMAKE_BUILD_TYPE=Release -DCMAKE_POLICY_VERSION_MINIMUM=3.5
        -DLLVM_TARGETS_TO_BUILD= -DLLVM_ENABLE_PROJECTS= -DLLVM_INCLUDE_TESTS=OFF
        -DLLVM_INCLUDE_BENCHMARKS=OFF -DLLVM_INCLUDE_EXAMPLES=OFF -DLLVM_INCLUDE_DOCS=OFF
        -DLLVM_ENABLE_ZLIB=OFF -DLLVM_ENABLE_ZSTD=OFF -DLLVM_ENABLE_LIBXML2=OFF
        -DLLVM_ENABLE_TERMINFO=OFF -DLLVM_ENABLE_BINDINGS=OFF)

echo "== host llvm-tblgen"
cmake -S "$T/llvm-project/llvm" -B "$T/llvm-host-build" "${COMMON[@]}"
ninja -C "$T/llvm-host-build" -j"$JOBS" llvm-tblgen

echo "== iOS libraries"
cmake -S "$T/llvm-project/llvm" -B "$T/llvm-ios-build" "${COMMON[@]}" \
    -DCMAKE_SYSTEM_NAME=iOS -DCMAKE_OSX_ARCHITECTURES=arm64 -DCMAKE_OSX_SYSROOT=iphoneos \
    -DCMAKE_OSX_DEPLOYMENT_TARGET=17.0 \
    -DLLVM_HOST_TRIPLE=arm64-apple-ios17.0 -DLLVM_DEFAULT_TARGET_TRIPLE=arm64-apple-ios17.0 \
    -DLLVM_TARGET_ARCH=host -DLLVM_BUILD_TOOLS=OFF -DLLVM_BUILD_UTILS=OFF \
    -DLLVM_TABLEGEN="$T/llvm-host-build/bin/llvm-tblgen"
ninja -C "$T/llvm-ios-build" -j"$JOBS"

ls "$T/llvm-ios-build/lib/"*.a | wc -l | xargs echo "iOS LLVM archives:"
lipo -info "$T/llvm-ios-build/lib/libLLVMCore.a"
