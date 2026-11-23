#!/usr/bin/env python3
"""Build a bootable IPLPRO D88 from the FUZIX kernel link output (fuzix.ihx).

Own tool for the FUZIX MZ-2500 port (GPLv2, same as FUZIX).

Memory image seen by the boot loader: kernel bank windows 0-5 (0000-BFFF) go to
physical pages 02-07; the common image (E000-FFFF) is staged in page 0Eh, because
page 0Fh is the IPL's own work area and cannot be a load destination. crt0 copies
page 0Eh into the fixed common page 0Fh. Window 6 is switched to text VRAM by the
kernel itself. Pages 00/01 are avoided (the IPL treats them specially).

Disk layout (real IPL convention): record 0 = header at C0/H1/R1; records are
numbered logically and record r lives at position i = r xor 10h, with
cyl = i/32, head = (i/16)&1, sector = i%16+1. Payload starts at record 16 and
runs contiguously, 32 records (8KB) per page. All data is stored inverted.
"""
import struct, sys

PAGES = [0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x0E]
LOADREC = 0x10

def read_ihx(path):
    mem = bytearray(65536)
    for line in open(path):
        line = line.strip()
        # bank-aware linker prefixes each record with "NN:" (bank number)
        if ':' not in line:
            continue
        bank, line = line.split(':', 1)
        if bank and int(bank, 16) != 0:
            raise SystemExit("unexpected banked output (bank %s)" % bank)
        line = ':' + line
        n = int(line[1:3], 16); addr = int(line[3:7], 16); typ = int(line[7:9], 16)
        if typ == 0:
            for i in range(n):
                mem[addr + i] = int(line[9 + 2 * i:11 + 2 * i], 16)
    return mem

def records(mem, entry, title=b"FUZIX MZ2500"):
    """Logical 256-byte records {number: bytes} of the boot header and kernel."""
    payload = bytes(mem[0x0000:0xC000]) + bytes(mem[0xE000:0x10000])
    assert len(payload) == 0x2000 * len(PAGES)
    hdr = bytearray(256)
    hdr[0] = 0x01
    hdr[1:7] = b"IPLPRO"
    t = (title + b"\r")[:16]
    hdr[7:7 + len(t)] = t
    hdr[0x18:0x1A] = struct.pack("<H", entry)
    hdr[0x1E] = LOADREC
    for i, p in enumerate(PAGES):
        hdr[0x20 + i] = p
    hdr[0x20 + len(PAGES)] = 0xFF
    for i, p in enumerate([0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08]):
        hdr[0x30 + i] = p            # CPU blocks 0-6 at entry
    logical = {0: bytes(hdr)}
    nrec = len(payload) // 256
    for k in range(nrec):
        logical[LOADREC + k] = payload[k * 256:(k + 1) * 256]
    return logical

def build(mem, entry, title=b"FUZIX MZ2500"):
    logical = records(mem, entry, title)
    pos = {}
    for r, data in logical.items():
        i = r ^ 0x10
        pos[(i // 32, (i // 16) & 1, i % 16 + 1)] = data
    cyls, heads, spt = 80, 2, 16
    tracks = []
    for c in range(cyls):
        for h in range(heads):
            blob = b""
            for r in range(1, spt + 1):
                data = pos.get((c, h, r), b"\x00" * 256)
                inv = bytes(b ^ 0xFF for b in data)
                blob += struct.pack("<BBBBHBBB5xH", c, h, r, 1, spt, 0x00, 0, 0, 256) + inv
            tracks.append(blob)
    base = 0x2B0
    offs, cur = [], base
    for t in tracks:
        offs.append(cur); cur += len(t)
    name = b"FUZIX MZ2500".ljust(17, b"\x00")
    head = name + b"\x00" * 9 + bytes([0x00, 0x10]) + struct.pack("<I", cur)
    head += b"".join(struct.pack("<I", o) for o in offs)
    head = head.ljust(base, b"\x00")
    return head + b"".join(tracks)

if __name__ == "__main__":
    ihx, dst = sys.argv[1], sys.argv[2]
    entry = int(sys.argv[3], 0) if len(sys.argv) > 3 else 0x0100
    open(dst, "wb").write(build(read_ihx(ihx), entry))
