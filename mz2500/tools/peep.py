#!/usr/bin/env python3
# peephole pass over k_*.s. usage: peep.py file.s [badlines-file]
# 1) jp L / jp Z|NZ|C|NC,L -> jr  (lines listed in badlines file and jump-table entries after jp (hl) are skipped)
# 2) ld a,#0 -> xor a,a when next instruction does not read flags
import re,sys
f=sys.argv[1]
bad=set()
if len(sys.argv)>2:
    bad={int(x) for x in open(sys.argv[2]).read().split()}
L=open(f).read().split('\n')
flagread=re.compile(r'^\s+(jr|jp|call|ret)\s+(NZ|Z|NC|C|PO|PE|P|M)\b|^\s+(adc|sbc|rla|rra|rl|rr|rlca|rrca|daa|ccf|scf|push\s+af)\b|^\s+ret\s+(nz|z|nc|c|po|pe|p|m)\b',re.I)
n1=n2=0
# Jump tables (jp (hl) dispatch with 3-byte entries) must keep every entry a 3-byte jp:
# mark the run of jp/jr lines that follows a label after "jp (hl)" as untouchable.
table=set()
pending=False
j=0
while j<len(L):
    t=L[j].strip()
    if re.match(r'^jp\s+\(hl\)',t): pending=True
    elif pending and re.match(r'^[\w$.]+:',t):
        k=j+1
        while k<len(L) and re.match(r'^\s+j[pr]\s',L[k]):
            table.add(k+1); k+=1
        pending=False
    elif pending and t and not t.startswith(';'): pending=False
    j+=1
bad|=table
labs=set(re.findall(r'^([\w.]+\$?|\d+\$):',open(f).read(),re.M))
for i,l in enumerate(L):
    m=re.match(r'^(\s+)jp(\s+)((?:NZ|Z|NC|C),)?([A-Za-z_.][\w$.]*|\d+\$)\s*(;.*)?$',l)
    if m and (i+1) not in bad and m.group(4) in labs:
        L[i]='%sjr%s%s%s'%(m.group(1),m.group(2),m.group(3) or '',m.group(4)); n1+=1
    if re.match(r'^\s+ld\s+a, #0x00\s*$',l):
        j=i+1
        while j<len(L) and (L[j].strip()=='' or L[j].lstrip().startswith(';') or re.match(r'^[\w$.]+:',L[j].strip())):
            if re.match(r'^[\w$.]+:',L[j].strip()): break
            j+=1
        if j<len(L) and not re.match(r'^[\w$.]+:',L[j].strip()) and not flagread.match(L[j]):
            L[i]=l.replace('ld\ta, #0x00','xor\ta, a'); n2+=1
open(f,'w').write('\n'.join(L))
print(f,'jr:',n1,'xor:',n2)
