#!/usr/bin/env bash
. "$(dirname "${BASH_SOURCE[0]}")/env.sh"
# Floppy driver test: data disk in drive 2 (/dev/fd1): read, write, motor-off/on, then verify both images on the host.
set -e
cd $MZ_WORK
EMU=$MZ_EMU
U=$MZ_FUZIX/Standalone
SROM=${SROM:-$MZ_SASI_ROM}
python3 - <<'PY'
open('/tmp/pat.bin','wb').write(bytes((i*7+i//251)&0xFF for i in range(20000)))
PY
rm -f /tmp/fd.img; (cd $U && ./mkfs /tmp/fd.img 32 1152 >/dev/null && printf 'bget /tmp/pat.bin pat\nexit\n' | ./ucp /tmp/fd.img >/dev/null)
python3 tools/mkfd.py /tmp/fd.img /tmp/fd.d88
$EMU --rom-dir $MZ_ROMDIR --real-ipl --sasi-rom $SROM --disk-a m3.d88 --disk-b /tmp/fd.d88 --disk-save 1:/tmp/fd_out.d88 --hdf root.hdf --hdf-save /tmp/hd_out.hdf --frames 6000 \
  --type 'hda\r:900' --type 'mount /dev/fd1 /tmp\r:1500' --type 'cp /tmp/pat /pat1\r:2100' --type 'cp /bin/ls /tmp/ls2\r:2700' \
  --type 'sync\r:3300' --type 'cp /tmp/pat /pat2\r:4300' --type 'sync\r:5000' > /tmp/fdtest.log 2>&1
python3 - <<'PY'
import struct
d=open('/tmp/fd_out.d88','rb').read()
offs=struct.unpack('<160I',d[0x20:0x20+640])
raw=bytearray(2560*256)
for t,o in enumerate(offs):
    p=o
    for s in range(16):
        c,h,r,n,nsec,den,dl,st=struct.unpack('<BBBBHBBB',d[p:p+9]); size=struct.unpack('<H',d[p+14:p+16])[0]
        data=d[p+16:p+16+size]; p+=16+size
        rec=((c*2+h)*16+(r-1))^0x10
        raw[rec*256:(rec+1)*256]=data
open('/tmp/fd_out.img','wb').write(bytes(raw[256*256:]))
PY
dd if=/tmp/hd_out.hdf of=/tmp/hd_out.fs bs=256 skip=545 2>/dev/null
cd /tmp; rm -f ls2 ls pat1 pat2
printf 'bput ls2\nexit\n' | $U/ucp /tmp/fd_out.img >/dev/null
printf 'cd /bin\nbput ls\nbget\nexit\n' | $U/ucp /tmp/hd_out.fs >/dev/null 2>&1 || true
printf 'cd /bin\nbput ls\nexit\n' | $U/ucp /tmp/hd_out.fs >/dev/null
printf 'bput pat1\nbput pat2\nexit\n' | $U/ucp /tmp/hd_out.fs >/dev/null
ok=1
cmp /tmp/ls2 /tmp/ls   && echo "ok   fd write (23171 bytes)"       || ok=0
cmp /tmp/pat1 /tmp/pat.bin && echo "ok   fd read (20000 bytes)"     || ok=0
cmp /tmp/pat2 /tmp/pat.bin && echo "ok   fd read after motor-off"     || ok=0
[ $ok = 1 ] && echo ALL PASS || { echo FAILURES; exit 1; }
