#!/bin/bash
# Reproduce the 3D Godot PS5 engine from scratch on macOS (no Docker/Homebrew).
#
#   tools/setup_toolchain.sh        # SDK sysroot + LLVM linker + SCons
#   tools/build_engine_3d.sh        # this script: clone sources, patch, build
#   tools/build_app_3d.sh           # link engine + PCK into the PS5 folder
#   tools/deploy_3d.sh              # upload the folder + PCK, let ShadowMount mount
#
# Caches everything under /tmp (override with GODOT_SRC/LAP_ROOT/DEVBRIDGE).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WORK="${PS5_WORK:-/tmp}"
GODOT="${GODOT_SOURCE:-$WORK/godot}"
LAP="${LAP_ROOT:-$WORK/lap}"
DB="${DEVBRIDGE:-$WORK/devbridge}"
LLVM="$ROOT/vendor/LLVM-20.1.8-macOS-ARM64"
SDK="$DB/templates/simple-calc/.deps/native/ps5-payload-sdk"

export PATH="/tmp/bash/bin:/tmp/shims:$HOME/Library/Python/3.9/bin:$LLVM/bin:$ROOT/tools:/usr/bin:/bin"
export SCE_PROSPERO_SDK_DIR="$SDK" PS5_PAYLOAD_SDK="$SDK"
export PS5_CLANG="$LLVM/bin/clang" PS5_AR="$LLVM/bin/llvm-ar" PS5_RANLIB="$LLVM/bin/llvm-ranlib"
export GODOT_MODULE_SET=smoke3d
export GODOT_PS5_GLES3_ARCHIVES=1 GODOT_PS5_DISPLAY_EXPERIMENT=1
export GODOT_PS5_NATIVE_GLES3=1 GODOT_PS5_AUDIOOUT=1
export BUILD_JOBS="${BUILD_JOBS:-8}"

echo "[1/6] sources"
[ -d "$GODOT" ] || git clone --depth=1 --branch 4.7.2-stable https://github.com/godotengine/godot.git "$GODOT"
[ -d "$LAP" ]   || git clone --depth=1 --branch test/godot-ps5-m26-platformer-acceptance https://github.com/Yahballon/tmp_lap.git "$LAP"
[ -d "$DB" ]    || { git clone https://github.com/Yahballon/PS5-DevBridge.git "$DB"; git -C "$DB" checkout ce6178ed7b7668a4686e5368971ca567b33d394b; }

echo "[2/6] macOS shims (bash 5, sha256sum, wget, realpath, ln)"
if [ ! -x /tmp/bash/bin/bash ]; then
  ( cd /tmp && curl -sL https://ftp.gnu.org/gnu/bash/bash-5.2.37.tar.gz -o bash.tgz \
    && tar xzf bash.tgz && cd bash-5.2.37 \
    && ./configure --prefix=/tmp/bash --without-bash-malloc --disable-nls >/dev/null \
    && make -j8 >/dev/null && make install >/dev/null )
fi
/tmp/bash/bin/bash "$ROOT/tools/make_shims.sh"

echo "[3/6] ps5-payload-sdk + ps5-opengl SDK (pinned mirror)"
[ -d "$SDK" ] || curl -fL -o /tmp/sdk.zip https://github.com/ps5-payload-dev/sdk/releases/download/v0.42/ps5-payload-sdk.zip \
  && unzip -q /tmp/sdk.zip -d "$DB/templates/simple-calc/.deps/native"
prefix="$(/tmp/bash/bin/bash "$LAP/homebrew/godot-ps5/gpu-probe/fetch-mirrored-opengl-sdk.sh")"
env PATH="/tmp/bash/bin:/tmp/shims:$LLVM/bin:$PATH" PS5_OPENGL_PREFIX="$prefix" \
  /tmp/bash/bin/bash "$DB/templates/simple-calc/tools/prepare-opengl.sh"

echo "[4/6] 3D module set + haptics pad driver"
cp "$ROOT/engine-overlay/pad_ps5.cpp" "$LAP/homebrew/godot-ps5/engine/platform/ps5/pad_ps5.cpp"
python3 "$ROOT/tools/patch_engine_3d.py" "$LAP/homebrew/godot-ps5/scripts/build-engine.sh"

echo "[5/6] engine build (3D + GLES3 + FreeType + AudioOut)"
/tmp/bash/bin/bash "$LAP/homebrew/godot-ps5/scripts/build-engine.sh"

echo "[6/6] done. Next: tools/build_app_3d.sh && tools/deploy_3d.sh"
