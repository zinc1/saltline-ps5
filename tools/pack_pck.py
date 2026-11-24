#!/usr/bin/env python3
"""Pack a Godot 4.7 .pck from game/ using the layout the PS5 port already runs.

Layout (verified against a working /data/GodotPS5/games/saltline.pck):
  0x00  "GDPC" | pack_version=3 | version 4.7.2
  0x14  flags = 0x2 (relative file base)
  0x18  file_base (u64)
  0x20  dir_offset (u64) = 40
  0x28  directory: u32 count
        per file: u32 name_len | name (NUL padded to 4)
                  u64 offset (relative to file_base) | u64 size | md5[16] | u32 flags
  data: file_base, tightly packed.
"""
import hashlib
import os
import struct
import sys

HEADER = 40
DIR_OFF = 40


def align(n, a):
    return (n + a - 1) // a * a


def pack(entries, out_path):
    # directory bytes first, so file_base is known
    table = []
    d = bytearray(struct.pack("<I", len(entries)))
    for name, blob in entries:
        nb = name.encode("utf-8") + b"\x00"
        nb += b"\x00" * ((4 - len(nb) % 4) % 4)
        table.append((nb, len(blob), hashlib.md5(blob).digest()))
        d += struct.pack("<I", len(nb)) + nb
    dir_size = 4 + sum(4 + len(nb) + 16 + 16 + 4 for (nb, _size, _md5) in table)
    file_base = align(DIR_OFF + dir_size, 16)

    # second pass: offsets relative to file_base (tightly packed, like the sample)
    d = bytearray(struct.pack("<I", len(entries)))
    off = 0
    for (nb, size, md5) in table:
        d += struct.pack("<I", len(nb)) + nb
        d += struct.pack("<QQ", off, size) + md5 + struct.pack("<I", 0)
        off += size

    hdr = bytearray(b"GDPC")
    hdr += struct.pack("<4I", 3, 4, 7, 2)
    hdr += struct.pack("<I", 0x2)
    hdr += struct.pack("<Q", file_base)
    hdr += struct.pack("<Q", DIR_OFF)
    assert len(hdr) == HEADER

    body = bytearray(hdr)
    body += d
    body += b"\x00" * (file_base - len(body))
    for (_name, blob) in entries:
        body += blob
    open(out_path, "wb").write(bytes(body))
    return len(entries), file_base


def main():
    root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    game = os.path.join(root, "game")
    out = sys.argv[1] if len(sys.argv) > 1 else os.path.join(root, "build", "saltline.pck")
    os.makedirs(os.path.dirname(out), exist_ok=True)
    entries = []
    for base, _dirs, files in os.walk(game):
        for f in files:
            p = os.path.join(base, f)
            rel = os.path.relpath(p, game)
            entries.append(("res://" + rel.replace(os.sep, "/"), open(p, "rb").read()))
    entries.sort()
    n, base = pack(entries, out)
    print(f"packed {n} files -> {out} ({os.path.getsize(out)} bytes, file_base={base})")


if __name__ == "__main__":
    main()
