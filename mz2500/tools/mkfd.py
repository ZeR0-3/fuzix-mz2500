#!/usr/bin/env python3
"""Logical 256-byte-record image (record r: cylinder r/32, head (r/16)&1, sector r%16+1; the
logical head is the inverse of the physical side, like the IPL disks: D88 position = r XOR 10h)
Raw 256-byte-record image (80 cyl x 2 heads x 16 sectors) -> plain D88 (data not inverted).
Usage: mkfd.py raw.img out.d88"""
import struct, sys
raw = open(sys.argv[1], 'rb').read()
raw = raw.ljust(80 * 2 * 16 * 256, b'\0')
FS = int(sys.argv[3]) if len(sys.argv) > 3 else 256   # first record of the filesystem
raw = b'\0' * (FS * 256) + raw
raw = raw[:80 * 2 * 16 * 256]
tracks = []
for t in range(160):
    c, h = t // 2, t % 2
    blob = b""
    for s in range(16):
        r = ((t * 16 + s) ^ 0x10)   # physical position -> logical record
        blob += struct.pack("<BBBBHBBB5xH", c, h, s + 1, 1, 16, 0x00, 0, 0, 256) + raw[r * 256:(r + 1) * 256]
    tracks.append(blob)
base = 0x2B0
offs, cur = [], base
for t in tracks:
    offs.append(cur); cur += len(t)
head = b"FUZIX FD".ljust(17, b"\0") + b"\0" * 9 + bytes([0x00, 0x10]) + struct.pack("<I", cur)
head += b"".join(struct.pack("<I", o) for o in offs)
open(sys.argv[2], 'wb').write(head.ljust(base, b"\0") + b"".join(tracks))
