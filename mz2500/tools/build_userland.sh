#!/usr/bin/env bash
. "$(dirname "${BASH_SOURCE[0]}")/env.sh"
# Build the host tools, the Z80 userland library and the few applications of the root image.
# NEVER run the top-level "make clean": it removes all of this.
set -euo pipefail
export FUZIX_ROOT=$MZ_FUZIX USERCPU=z80 CPU=z80 TARGET=mz2500
cd $FUZIX_ROOT
(cd Standalone && make mkfs ucp fsck >/dev/null)
make TARGET=mz2500 ltools >/dev/null
make TARGET=mz2500 libs >/dev/null
(cd Applications/util && make -f Makefile.z80 init ls cat echo mount sync mkdir remount cp rm pwd ps df uname kill date wc od sort ed more chmod touch head tail fsck grep sleep tee tr cal du sum cmp basename dirname yes true false mkfs rmdir reboot setdate uptime free mknod id env printenv uniq cut seq xargs which stty umount sed who whoami ln mv passwd su fdformat fdcopy >/dev/null)
(cd Applications/V7/cmd/sh && make -f Makefile.z80 >/dev/null)
echo "userland ok"
