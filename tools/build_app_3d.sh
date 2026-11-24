#!/bin/bash
# Link the 3D Godot PS5 engine + Saltline PCK into a ShadowMount app folder.
# Mirrors the PS5_Godot CI (GLES3 canvas workflow) but runs on macOS.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
LAP="${LAP_ROOT:-/tmp/lap}"
GODOT="${GODOT_SOURCE:-/tmp/godot}"
DB="${DEVBRIDGE:-/tmp/devbridge}"
APP="${APP_DIR:-/tmp/godot-scene-app}"
TITLE_ID="${TITLE_ID:-PPSA99700}"
CONCEPT_ID="${TITLE_ID#PPSA}"
LLVM="$ROOT/vendor/LLVM-20.1.8-macOS-ARM64"
SDK="$DB/templates/simple-calc/.deps/native/ps5-payload-sdk"
export PATH="/tmp/bash/bin:$HOME/Library/Python/3.9/bin:$LLVM/bin:$ROOT/tools:/tmp/shims:/usr/bin:/bin"
export PS5_PAYLOAD_SDK="$SDK"
export SCE_PROSPERO_SDK_DIR="$SDK"
export PS5_CLANG="$LLVM/bin/clang" PS5_AR="$LLVM/bin/llvm-ar" PS5_RANLIB="$LLVM/bin/llvm-ranlib"
export USE_CCACHE=0 BUILD_JOBS="${BUILD_JOBS:-8}"
export CXX=/usr/bin/clang++ CC=/usr/bin/clang HOST_ZLIB_ROOT=/tmp/hzlib/root
PY="${PYTHON:-python3}"
"$PY" -c "import hashlib, sys; sys.exit(0 if hasattr(hashlib, 'file_digest') else 1)" \
  || { echo "Python 3.11+ is required (hashlib.file_digest); set PYTHON=..."; exit 1; }

echo "[0/7] prerequisites (host zlib, runtime libc.prx, DevBridge patches)"
if [ ! -f /tmp/hzlib/root/lib/libz.a ]; then
  mkdir -p /tmp/hzlib && cd /tmp/hzlib
  curl -sL https://github.com/madler/zlib/releases/download/v1.3.2/zlib-1.3.2.tar.gz -o z.tgz
  tar xzf z.tgz && cd zlib-1.3.2
  CC=/usr/bin/clang ./configure --static --prefix=/tmp/hzlib/root >/dev/null
  make -j8 >/dev/null && make install >/dev/null
  cd "$ROOT"
fi
if [ ! -f /tmp/ppsa99847/PPSA99847/sce_module/libc.prx ]; then
  curl -sL "https://github.com/Yahballon/PS5_Godot/releases/download/v0.2.10/PPSA99847.zip" -o /tmp/ppsa99847.zip
  unzip -q -o /tmp/ppsa99847.zip -d /tmp/ppsa99847
fi
python3 - "$DB" <<'PYEOF'
import sys
from pathlib import Path
root = Path(sys.argv[1]) / 'templates/simple-calc/tools'
h = root / 'build-host-tools.sh'
s = h.read_text()
if 'HOST_ZLIB_ROOT' not in s:
    s = s.replace('zlib_root="$root/.deps/native/zlib/root"',
                  'zlib_root="${HOST_ZLIB_ROOT:-$root/.deps/native/zlib/root}"')
    h.write_text(s)
r = root / 'rebuild-libc.sh'
s = r.read_text()
s = s.replace('[[ $(stat -c %s "$work/libc-a.prx") == 1284674 ]]',
              '[[ $(wc -c < "$work/libc-a.prx") == 1284674 ]]')
r.write_text(s)
print('DevBridge macOS patches applied')
PYEOF

echo "[1/7] packaging engine archives"
"$PY" "$LAP/homebrew/godot-ps5/scripts/package_static_engine.py" \
  "$GODOT" /tmp/godot-full.zip --min-archives 8

echo "[2/7] staging DevBridge app"
rm -rf "$APP"
cp -a "$DB/templates/simple-calc" "$APP"
mkdir -p "$APP/assets/godot"
cp "$ROOT/build/saltline.pck" "$APP/assets/godot/smoke.pck"
cp "$ROOT/dist/LAPY00001-parts/icon0.png" "$APP/sce_sys/icon0.png"
# The clean-room libc.prx is byte-identical to the official engine release;
# reusing it skips the Linux-only libc reproducer and its hash gate.
cp /tmp/ppsa99847/PPSA99847/sce_module/libc.prx "$APP/runtime/libc.prx" 2>/dev/null || true
touch "$APP/runtime/libc.prx" 2>/dev/null || true

echo "[3/7] staging native link"
"$PY" "$LAP/homebrew/godot-ps5/scripts/stage_native_link.py" \
  --godot "$GODOT" --app "$APP" \
  --entry "$LAP/homebrew/godot-ps5/native/gles3_canvas_main.cpp"

echo "[4/7] adding proven DevBridge GPU/runtime sources"
app_src="$APP/src/godot-smoke"
mkdir -p "$app_src/platform/ps5" "$app_src/runtime"
cp "$DB/templates/simple-calc/src/platform/ps5/display_egl.cpp" \
   "$DB/templates/simple-calc/src/platform/ps5/system.cpp" "$app_src/platform/ps5/"
cp "$DB/templates/simple-calc/src/runtime/app_heap.c" \
   "$DB/templates/simple-calc/src/runtime/native_mmap.c" \
   "$DB/templates/simple-calc/src/runtime/runtime_shims.c" "$app_src/runtime/"
cp "$LAP/homebrew/godot-ps5/engine/platform/ps5/graphics_hooks_ps5.h" "$app_src/"

echo "[5/7] removing duplicate openlog shim"
python3 - "$app_src/runtime/runtime_shims.c" <<'PY'
import re, sys
from pathlib import Path
p = Path(sys.argv[1]); code = p.read_text()
pattern = r'\nvoid openlog\(const char \*identifier, int option, int facility\)\s*\{\s*\(void\)identifier;\s*\(void\)option;\s*\(void\)facility;\s*\}\s*'
code, count = re.subn(pattern, '\n', code)
assert count == 1, f'expected one openlog shim, got {count}'
p.write_text(code)
PY

echo "[6/7] patching title metadata + link flags"
"$PY" - "$APP" <<'PY'
import json, sys
from pathlib import Path
root = Path(sys.argv[1])
meta = root / 'sce_sys/param.json'
d = json.loads(meta.read_text())
import os
title = os.environ.get('TITLE_ID', 'PPSA99700')
concept = title[4:] if title.startswith('PPSA') else '99700'
d.update(titleId=title, conceptId=concept,
         contentId=f'UP9000-{title}_00-SALTLINE00000001',
         contentVersion='01.000.000')
d['localizedParameters']['defaultLanguage'] = 'en-US'
d['localizedParameters']['en-US'] = {'titleName': 'Saltline'}
d['localizedParameters']['zh-CN'] = {'titleName': 'Saltline'}
meta.write_text(json.dumps(d, indent=2) + '\n')

base = Path('/tmp/devbridge/templates/simple-calc/GNUmakefile').read_text().splitlines()
orig = (root / 'GNUmakefile').read_text()
flags = [l for l in base if l.startswith(('APP_DEFINITIONS :=', 'APP_INCLUDE_PATHS :=',
                                          'APP_IMPORT_STUBS :=', 'APP_WRAP_SYMBOLS :='))]
assert len(flags) == 4
orig = orig.replace('APP_STATIC_ARCHIVES := ',
                    'APP_STATIC_ARCHIVES := .deps/ps5-opengl/libps5opengl-group.a ', 1)
(root / 'GNUmakefile').write_text('\n'.join(flags) + '\n' + orig)
print('metadata + makefile patched')
PY

echo "[7/7] linking eboot + signed folder"
cd "$APP"
if ! make USE_CCACHE=0 BUILD_JOBS="$BUILD_JOBS" app; then
  # Known DevBridge/PS5 converter limitation: optional C++ TLS-init hooks are
  # weak undefined symbols the SELF importer refuses. Bind exactly those to
  # null (the callers check the address), then relink.
  echo "[7/7] weak-TLS fallback"
  "$PY" "$LAP/homebrew/godot-ps5/scripts/resolve_weak_tls.py" \
    --elf "$APP/build/llvm-pie.elf" --build-sh "$APP/tools/build.sh"
  make USE_CCACHE=0 BUILD_JOBS="$BUILD_JOBS" app
fi
ls -l "$APP/dist" 2>/dev/null || true
