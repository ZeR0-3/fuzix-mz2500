#!/usr/bin/env python3
"""Look up the nearest preceding symbol for hex addresses in fuzix.map."""
import sys, re
syms = []
for line in open(__import__('os').environ.get('MZ_FUZIX','.')+'/Kernel/fuzix.map'):
    m = re.match(r'\s+([0-9A-Fa-f]{8})\s+(\S+)', line)
    if m:
        syms.append((int(m.group(1), 16), m.group(2)))
syms.sort()
for a in sys.argv[1:]:
    v = int(a, 16)
    best = None
    for s in syms:
        if s[0] <= v: best = s
        else: break
    print("%04X = %s+%d" % (v, best[1], v - best[0]) if best else "%04X ?" % v)
