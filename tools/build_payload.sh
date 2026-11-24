#!/bin/bash
# Build one (or all) PS5 payloads in native/.
# Primary: real LLVM (vendor/LLVM-*/bin) + the SDK's prospero wrapper.
# Fallback: Apple clang + zig's LLD via tools/prospero-lld.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SDK="${PS5_PAYLOAD_SDK:-$ROOT/vendor/ps5-payload-sdk}"
LLVM_BIN=""
for d in "$ROOT"/vendor/LLVM-*/bin; do [ -x "$d/clang" ] && LLVM_BIN="$d" && break; done
export PATH="${LLVM_BIN:+$LLVM_BIN:}$ROOT/tools:$PATH"
export SCE_PROSPERO_SDK_DIR="$SDK"
[ -d "$SDK" ] || { echo "missing SDK: $SDK (run tools/setup_toolchain.sh)"; exit 1; }
mkdir -p "$ROOT/build"
SRC="${1:-}"
if [ -z "$SRC" ]; then
  for f in "$ROOT"/native/*.c; do "$0" "$(basename "$f")"; done
  exit 0
fi
name="${SRC%.c}"
echo "[build] $name  (llvm: ${LLVM_BIN:-apple clang + zig lld})"
if [ -n "$LLVM_BIN" ]; then
  "$SDK/bin/prospero-clang" -O2 -Wall -Wextra -Wno-unused-parameter \
    -o "$ROOT/build/$name.elf" "$ROOT/native/$SRC" -lSceUserService -lScePad -lc
else
  clang -target x86_64-sie-ps5 --sysroot="$SDK" -O2 -Wall -Wextra \
    -Wno-unused-parameter -o "$ROOT/build/$name.elf" "$ROOT/native/$SRC" \
    -lSceUserService -lScePad -lkernel_web -lc
fi
ls -l "$ROOT/build/$name.elf"
