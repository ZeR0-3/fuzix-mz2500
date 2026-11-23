#!/usr/bin/env bash
. "$(dirname "${BASH_SOURCE[0]}")/env.sh"
# Boot the kernel from the HDD image alone (emulator's built-in dummy IPL, no ROMs, no floppy).
EMU=${EMU:-$MZ_EMU}
cd $MZ_WORK
$EMU --hdf root.hdf --frames ${FRAMES:-3500} --type 'hda\r:1500' --screen-report ${EMUARGS:-} 2>&1 | grep -E '^screen' | grep -v '^screen: *$' | tail -${TAILN:-6}
