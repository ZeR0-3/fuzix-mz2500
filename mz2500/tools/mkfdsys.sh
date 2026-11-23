#!/usr/bin/env bash
. "$(dirname "${BASH_SOURCE[0]}")/env.sh"
# Build a stand-alone bootable system floppy (fdboot.d88): kernel + a root filesystem of core tools on the same disk.
set -euo pipefail
cd $MZ_WORK
APPS_OVERRIDE="${APPS_OVERRIDE:-ls cat echo mount sync mkdir remount cp rm pwd ps df uname kill date wc od sort grep ed more head tail tr sed sleep chmod touch free uptime who id ln mv passwd su fdformat fdcopy}"
INITTAB=${INITTAB:-} ISIZE=24 FSIZE=1152 APPS_OVERRIDE="$APPS_OVERRIDE" ./tools/mkroot.sh /tmp/fdroot.img
python3 tools/mkfdboot.py $MZ_FUZIX/Kernel/fuzix.ihx /tmp/fdroot.img fdboot.d88
