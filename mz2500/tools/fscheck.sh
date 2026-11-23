#!/bin/bash
. "$(dirname "${BASH_SOURCE[0]}")/env.sh"
# FS consistency test: create (redirect, big multi-block file), delete, mkdir/rmdir,
# sync, then check the saved image with the host fsck and look for kernel warnings.
# usage: tools/fscheck.sh [extra emulator args]
EMU=${EMU:-$MZ_EMU}
cd "$(dirname "$0")/.."
OUT=/tmp/fscheck.hdf; rm -f $OUT
SCR=$($EMU --rom-dir $MZ_ROMDIR --real-ipl --disk-a m3.d88 --hdf root.hdf --hdf-save $OUT "$@" --frames 9000 \
 --type 'hda\r:900' --type 'ls / > /p1\r:1500' --type 'cp /bin/sh /a\r:2000' \
 --type 'cat /a /a /a /a /a /a > /b\r:2700' --type 'mkdir /d1\r:4800' --type 'cp /p1 /d1/x\r:5200' \
 --type 'rm /d1/x\r:5700' --type 'rmdir /d1\r:6100' --type 'rm /a\r:6500' --type 'rm /b\r:6900' \
 --type 'rm /p1\r:7300' --type 'ls /\r:7700' --type 'sync\r:8200' --screen-report 2>&1 | grep '^screen')
fail=0
echo "$SCR" | grep -Eq 'panic|bad nlink|corrupt' && { echo "FAIL kernel warning"; fail=1; }
[ -s $OUT ] || { echo "FAIL no image saved"; echo FAILURES; exit 1; }
cp $OUT /tmp/fscheck_c.hdf
R=$($MZ_FUZIX/Standalone/fsck -y /tmp/fscheck_c.hdf:139520 </dev/null 2>&1)
echo "$R" | grep -Eq 'detached|Bad|bad|Dup|dup|missing|Fix' && { echo "FAIL fsck"; echo "$R" | tail -6; fail=1; }
[ $fail = 0 ] && echo "ok   fscheck" || echo "FAILURES"
exit $fail
