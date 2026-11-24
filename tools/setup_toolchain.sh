#!/bin/bash
# One-time: PS5 payload sysroot + a linker (zig's LLD).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
V="$ROOT/vendor"
mkdir -p "$V"
if [ ! -d "$V/ps5-payload-sdk" ]; then
  echo "[sdk] downloading ps5-payload-sdk v0.50"
  curl -fL -o "$V/sdk.zip" \
    https://github.com/ps5-payload-dev/sdk/releases/download/v0.50/ps5-payload-sdk.zip
  unzip -q "$V/sdk.zip" -d "$V"
fi
# The engine cross-compile expects an LLVM 20 toolchain for macOS arm64.
if ! ls "$V"/LLVM-*/bin/clang >/dev/null 2>&1; then
  cat <<'MSG'
[llvm] LLVM 20 for macOS arm64 is required for the engine build.
       Download LLVM-20.1.8-macOS-ARM64.tar.xz from
       https://github.com/llvm/llvm-project/releases/tag/llvmorg-20.1.8
       and extract it into vendor/ so that
       vendor/LLVM-20.1.8-macOS-ARM64/bin/clang exists.
MSG
fi
python3 -c "import ziglang" 2>/dev/null || python3 -m pip install --user ziglang
python3 -m ziglang version
echo "[ok] toolchain ready. Build: tools/build_payload.sh"
