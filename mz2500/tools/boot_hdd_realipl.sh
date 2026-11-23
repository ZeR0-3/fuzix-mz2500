#!/usr/bin/env bash
. "$(dirname "${BASH_SOURCE[0]}")/env.sh"
# HDD-only boot through the real IPL ROM + an Enhanced SASI option ROM (user supplied, FILE.ROM).
EMU=${EMU:-$MZ_EMU}
SROM=${SROM:-$MZ_SASI_ROM}
cd $MZ_WORK
$EMU --rom-dir $MZ_ROMDIR --real-ipl --sasi-rom $SROM --hdf root.hdf --frames ${FRAMES:-4500} --type 'hda\r:1500' --screen-report ${EMUARGS:-} 2>&1 | grep -E '^screen' | grep -v '^screen: *$' | tail -${TAILN:-6}
