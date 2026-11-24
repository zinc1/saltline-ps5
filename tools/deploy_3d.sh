#!/bin/bash
# Upload the freshly linked 3D app to the USB homebrew folder and let
# ShadowMount+ register it, then refresh the PCK the engine launches.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TITLE_ID="${TITLE_ID:-PPSA99700}"
H="${PS5_HOST:?set PS5_HOST to the console address}"
DIST="${DIST:-/tmp/godot-scene-app/dist/$TITLE_ID}"

[ -d "$DIST" ] || { echo "missing dist: $DIST"; exit 1; }
echo "[deploy] $DIST -> /mnt/usb0/homebrew/$TITLE_ID"
python3 "$ROOT/tools/ftp_deploy.py" "$DIST" "/mnt/usb0/homebrew/$TITLE_ID" | tail -4

echo "[pck] /data/GodotPS5/games/saltline.pck"
curl -s -m 30 -T "$ROOT/build/saltline.pck" "ftp://$H:2121/data/GodotPS5/games/saltline.pck"
printf 'saltline.pck\n' > /tmp/launch.txt
curl -s -m 10 -T /tmp/launch.txt "ftp://$H:2121/data/GodotPS5/launch.txt"

echo "[scan] waiting for ShadowMount to stabilise the folder"
sleep 14
curl -s -m 20 -X POST "http://$H:10101/api/v1/scan" -H 'Content-Type: application/json' -d '{}' >/dev/null 2>&1 || true
sleep 6
echo "=== shadowmount log ==="
curl -s -m 10 "ftp://$H:2121/data/shadowmount/debug.log" | tail -8
echo "=== mount ==="
curl -s -m 10 "ftp://$H:2121/user/app/$TITLE_ID/" 2>/dev/null | head -5 || echo "(not mounted yet)"
