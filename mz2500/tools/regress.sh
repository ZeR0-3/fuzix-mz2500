#!/bin/bash
. "$(dirname "${BASH_SOURCE[0]}")/env.sh"
# Regression test: boots m3.d88 + root.hdf in the emulator, types a command
# script and checks the screen at several checkpoints (the final screen only
# holds the last 25 rows, so each check is a separate run of N frames).
# usage: tools/regress.sh [extra emulator args, e.g. --no-emm]
EMU=${EMU:-$MZ_EMU}
cd "$(dirname "$0")/.."
TYPES=(--type 'hda\r:900'
  --type 'echo regress-echo\r:1500'
  --type 'cp /bin/sh /rg1\r:1900'
  --type '/rg1\r:2500'
  --type 'echo nested-ok\r:3000'
  --type 'ps\r:3400'
  --type 'mkdir /rgd\r:3900'
  --type 'ls / ^ cat\r:4300'
  --type 'rm /rg1\r:4800'
  --type 'rmdir /rgd\r:5200'
  --type 'ls /\r:5600')
fail=0
run() { $EMU --rom-dir $MZ_ROMDIR --real-ipl --disk-a m3.d88 --hdf root.hdf "${@:2}" --frames "$1" "${TYPES[@]}" --screen-report 2>&1 | grep '^screen'; }
check() { # frames pattern
  if run "$1" $EXTRA | grep -q -- "$2"; then echo "ok   [$1] $2"; else echo "FAIL [$1] $2"; fail=1; fi; }
EXTRA="$*"
check 1500 'init version'
check 2000 'regress-echo'
check 3350 'nested-ok'
check 3300 'cp /bin/sh /rg1'
check 3800 'PID    TTY'
check 4200 'rgd'
check 4700 'rgd'
check 5300 'ls /'
check 6200 '# _'
[ $fail = 0 ] && echo ALL PASS || echo FAILURES
exit $fail
