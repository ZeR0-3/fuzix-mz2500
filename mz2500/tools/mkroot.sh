#!/usr/bin/env bash
. "$(dirname "${BASH_SOURCE[0]}")/env.sh"
# Build the FUZIX root filesystem image (2MB): init = sh, a few tools, device nodes.
set -euo pipefail
FUZIX=$MZ_FUZIX
OUT=${1:-$MZ_WORK/root.img}
cd $FUZIX/Standalone
rm -f $OUT
TMPB=$(mktemp -d)
./mkfs $OUT ${ISIZE:-64} ${FSIZE:-4096} >/dev/null
U=$FUZIX/Applications/util
S=$FUZIX/Applications/V7/cmd/sh
APPS="${APPS_OVERRIDE:-${EXTRA:-} ls cat echo mount sync mkdir remount cp rm pwd ps df uname kill date wc od sort ed more chmod touch head tail fsck grep sleep tee tr cal du sum cmp basename dirname yes true false mkfs rmdir reboot setdate uptime free mknod id env printenv uniq cut seq xargs which stty umount sed who whoami ln mv fdformat fdcopy}"
ETC=$MZ_WORK/etc
TOOLS=$MZ_WORK/tools
# private copies with a per-program memory size (8KB pages)
# memory-hungry programs get a bigger top (sort/ed/grep buffer the whole input)
for p in init $APPS; do cp $U/$p $TMPB/$p
  case $p in sort|ed|grep|sed|more) python3 $TOOLS/setsize.py $TMPB/$p ${BIGTOP:-A000} >> /tmp/setsize.log;; *) python3 $TOOLS/setsize.py $TMPB/$p >> /tmp/setsize.log;; esac
done
cp $S/${SHBIN:-sh} $TMPB/sh; python3 $TOOLS/setsize.py $TMPB/sh ${SHTOP:-C000} >> /tmp/setsize.log
# ucp's get/bget create the file in the working directory (path part ignored)
{
echo "mkdir /bin"; echo "mkdir /dev"; echo "mkdir /tmp"; echo "mkdir /etc"; echo "mkdir /var"; echo "mkdir /var/run"; echo "mkdir /root"
echo "cd /"
echo "bget $TMPB/init init"; echo "chmod 755 init"
echo "cd /bin"
echo "bget $TMPB/sh sh"
for p in $APPS; do echo "bget $TMPB/$p $p"; done
echo "chmod 755 sh"
for p in $APPS; do case $p in su|passwd) echo "chmod 4755 $p";; *) echo "chmod 755 $p";; esac; done
echo "cd /var/run"; echo "bget $ETC/utmp utmp"; echo "chmod 666 utmp"
echo "cd /etc"
echo "bget $ETC/rc rc"; [ -n "${NOINITTAB:-}" ] || echo "bget $ETC/${INITTAB:-inittab} inittab"; echo "bget $ETC/inittab itest"; echo "bget $ETC/passwd passwd"; echo "bget $ETC/group group"; echo "bget $ETC/issue issue"; echo "chmod 755 rc"
[ -n "${NOPROFILE:-}" ] || { echo "cd /root"; echo "bget $ETC/profile.root .profile"; echo "cd /tmp"; echo "bget $ETC/profile.root .profile"; }; echo "cd /dev"
echo "mknod null 20666 1024"; echo "mknod zero 20666 1026"; echo "mknod proc 20444 1027"
echo "mknod tty1 20660 513"
echo "mknod tty 20666 513"
echo "mknod hda 60660 0"; echo "mknod fd0 60660 256"; echo "mknod fd1 60660 257"; echo "mknod fdw0 60660 260"; echo "mknod fdw1 60660 261"
echo "exit"
} | timeout 60 ./ucp $OUT > /tmp/mkroot.log 2>&1 || { cat /tmp/mkroot.log; exit 1; }
grep -i "error\|can't" /tmp/mkroot.log && exit 1
echo "root image: $OUT"
