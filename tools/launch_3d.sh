#!/bin/bash
# Launch the Saltline title from a payload.
#
# The system rejects sceLncUtilLaunchApp with a NULL param for ShadowMount
# titles; a 1024-byte param block with size + foreground user id works
# (returns the app id and starts the title asynchronously).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
H="${PS5_HOST:?set PS5_HOST to the console address}"
LLVM="$ROOT/vendor/LLVM-20.1.8-macOS-ARM64"
SDK="${PS5_PAYLOAD_SDK:-$ROOT/vendor/ps5-payload-sdk}"
OUT="$ROOT/build/launch_app.elf"
mkdir -p "$ROOT/build"
PATH="$ROOT/tools:$LLVM/bin:$PATH" "$LLVM/bin/clang" -target x86_64-sie-ps5 --sysroot="$SDK" \
  -O1 -o "$OUT" "$ROOT/native/launch_app.c" -lSceSystemService -lSceUserService -lc
echo "[launch] $H"
timeout 30 nc "$H" 9021 < "$OUT" || true
sleep 5
curl -s -m 5 "ftp://$H:2121/data/GodotPS5/userdata/godot_app_userdata_Saltline/saltline_boot.log" | tail -3
