#!/usr/bin/env python3
"""Patch the memory request (a_size, header byte 13, in 256 byte units) of a
FUZIX relocatable binary so the kernel gives it only the 8KB pages it needs.

usage: setsize.py FILE [TOP_HEX]
  TOP_HEX = top of the process (multiple of 2000h). Default: file size + 4KB
  (room for bss/heap/stack) rounded up to 8KB.
"""
import sys, os
path = sys.argv[1]
d = bytearray(open(path, 'rb').read())
if d[0] != 0xA8 or d[1] != 0x80:
    sys.exit("%s: not a FUZIX binary" % path)
if len(sys.argv) > 2:
    top = int(sys.argv[2], 16)
else:
    top = ((len(d) + 0x1000 + 0x100 + 0x1FFF) // 0x2000) * 0x2000
top = max(0x2000, min(top, 0xE000))
d[13] = (top >> 8) - 1          # a_size; top = (a_base(1) + a_size) << 8
open(path, 'wb').write(d)
print("%s: %d bytes -> top %04X (%d pages)" % (os.path.basename(path), len(d), top, top // 0x2000))
