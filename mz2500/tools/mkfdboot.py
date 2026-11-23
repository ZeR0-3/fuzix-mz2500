#!/usr/bin/env python3
"""Bootable FUZIX floppy: IPLPRO header + kernel in cylinders 0-7 (IPL polarity, data
inverted), filesystem from logical record 256 (data as is). 2DD, 80 cyl x 2 heads x 16 x 256.
Logical record r is at D88 position r XOR 10h (logical head = inverse of the side).
Usage: mkfdboot.py fuzix.ihx fs.img out.d88 [entry]"""
import struct, sys, os
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import mkimage
ihx, fs, out = sys.argv[1:4]
entry = int(sys.argv[4], 0) if len(sys.argv) > 4 else 0x0100
FSREC = 256
boot = mkimage.records(mkimage.read_ihx(ihx), entry)
assert max(boot) < FSREC, "kernel too large for the boot area"
fsdata = open(fs, 'rb').read()
nrec = 2560
rec = {}
for r in range(nrec):
    if r in boot:
        rec[r] = bytes(b ^ 0xFF for b in boot[r])
    elif r < FSREC:
        rec[r] = b'\xFF' * 256                      # inverted zeros
    else:
        o = (r - FSREC) * 256
        rec[r] = fsdata[o:o + 256].ljust(256, b'\0')
tracks = []
for t in range(160):
    c, h = t // 2, t % 2
    blob = b""
    for s in range(16):
        r = (t * 16 + s) ^ 0x10
        blob += struct.pack("<BBBBHBBB5xH", c, h, s + 1, 1, 16, 0x00, 0, 0, 256) + rec[r]
    tracks.append(blob)
base = 0x2B0
offs, cur = [], base
for t in tracks:
    offs.append(cur); cur += len(t)
head = b"FUZIX MZ2500".ljust(17, b"\0") + b"\0" * 9 + bytes([0x00, 0x10]) + struct.pack("<I", cur)
head += b"".join(struct.pack("<I", o) for o in offs)
open(out, 'wb').write(head.ljust(base, b"\0") + b"".join(tracks))
print("%s: kernel records %d..%d, fs %d bytes at record %d" % (out, min(boot), max(boot), len(fsdata), FSREC))
