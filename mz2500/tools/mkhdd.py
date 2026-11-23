#!/usr/bin/env python3
"""Build a SASI hard-disk image (256-byte blocks) for the FUZIX MZ-2500 port.

Own tool for the port (GPLv2, same as FUZIX).

  block 3          partition table: "EHSASI 20220510" + 16-byte entries
  PART_TOP ...     the boot partition:
                     record 0         IPLPRO header (kernel loader description)
                     records 16..     kernel image (optional, for HDD boot)
                     record FSBASE..  FUZIX filesystem (512-byte blocks)
Usage: mkhdd.py out.hdf fs.img [fuzix.ihx]
"""
import struct, sys
sys.path.insert(0, __file__.rsplit('/', 1)[0])
import mkimage

PART_TOP = 0x21
FSBASE = 512          # must match devhd.c

def main():
    out, fs = sys.argv[1], sys.argv[2]
    ihx = sys.argv[3] if len(sys.argv) > 3 else None
    fsdata = open(fs, 'rb').read()
    fsdata += b'\0' * (-len(fsdata) % 256)
    nfs = len(fsdata) // 256
    cap = FSBASE + nfs
    assert cap <= 0xFF00
    total = PART_TOP + cap + 16
    img = bytearray(total * 256)
    # partition table
    pt = bytearray(256)
    pt[0:16] = b"EHSASI 20220510\0"
    e = bytearray(16)
    e[0] = 0x81                        # priority boot, drive 1
    e[1:3] = struct.pack(">H", cap)
    e[3] = 0x01                        # SASI ID bit
    e[4] = 0                           # LUN
    e[5] = (PART_TOP >> 16) & 0xFF
    e[6] = (PART_TOP >> 8) & 0xFF
    e[7] = PART_TOP & 0xFF
    pt[16:32] = e
    img[3 * 256:4 * 256] = pt
    base = PART_TOP * 256
    if ihx:
        for r, data in mkimage.records(mkimage.read_ihx(ihx), 0x0100).items():
            img[base + r * 256:base + (r + 1) * 256] = data
    img[base + FSBASE * 256:base + FSBASE * 256 + len(fsdata)] = fsdata
    open(out, 'wb').write(img)
    print("%s: %d blocks, partition at %d, fs at block %d (%d blocks)" %
          (out, total, PART_TOP, PART_TOP + FSBASE, nfs))

main()
