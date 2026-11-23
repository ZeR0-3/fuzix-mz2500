#!/usr/bin/env python3
"""profsum.py PROF MAP [N]: sum emulator --pc-profile output per symbol (nearest preceding map symbol)."""
import sys, bisect, re
prof, mp = sys.argv[1], sys.argv[2]
top = int(sys.argv[3]) if len(sys.argv) > 3 else 30
syms = []
for line in open(mp):
    m = re.match(r'\s+([0-9A-Fa-f]{8})\s+(\S+)', line)
    if m and not m.group(2).startswith(('l__', 's__', 'e__', 'b__')):
        syms.append((int(m.group(1), 16), m.group(2)))
syms.sort()
addrs = [a for a, _ in syms]
tot = {}
total = 0
for line in open(prof):
    a, c = line.split()
    a, c = int(a, 16), int(c)
    total += c
    if a >= 0x10000:
        tot['(user program)'] = tot.get('(user program)', 0) + c
        continue
    i = bisect.bisect_right(addrs, a) - 1
    name = syms[i][1] if i >= 0 and a < 0xF000 else '(user/other %04x)' % (a & 0xF000)
    if a >= 0xE000 and i >= 0:
        name = syms[i][1]
    tot[name] = tot.get(name, 0) + c
print('total cycles', total)
for n, c in sorted(tot.items(), key=lambda x: -x[1])[:top]:
    print('%6.2f%% %12d  %s' % (100.0 * c / total, c, n))
