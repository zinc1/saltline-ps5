#!/bin/bash
# Load a payload over the ELF loader port (9021).
set -euo pipefail
HOST="${PS5_HOST:?set PS5_HOST to the console address}"
PORT="${PS5_PORT:-9021}"
[ $# -ge 1 ] || { echo "usage: $0 payload.elf"; exit 1; }
[ -f "$1" ] || { echo "no such file: $1"; exit 1; }
echo "[deploy] $1 -> $HOST:$PORT"
nc "$HOST" "$PORT" < "$1" || true
