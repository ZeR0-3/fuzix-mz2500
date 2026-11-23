#!/usr/bin/env bash
. "$(dirname "${BASH_SOURCE[0]}")/tools/env.sh"
# Rebuild kernel + images and boot with the HDD attached. FRAMES, TYPE override defaults.
set -euo pipefail
FUZIX=$MZ_FUZIX
EMU=${EMU:-$MZ_EMU}
find $FUZIX/Kernel -name "*.rel" -delete; rm -f $FUZIX/Kernel/fuzix.ihx
(cd $FUZIX && make TARGET=mz2500 kernel)  2>&1 | grep -E "rror|Undefined|Free memory" || true
cd $MZ_WORK
python3 tools/mkimage.py $FUZIX/Kernel/fuzix.ihx m3.d88 0x0100
python3 tools/mkhdd.py root.hdf root.img $FUZIX/Kernel/fuzix.ihx >/dev/null
$EMU --rom-dir $MZ_ROMDIR --real-ipl --disk-a m3.d88 --hdf root.hdf --frames ${FRAMES:-1500} --type "${TYPE:-hda\r:900}" --screen-report ${EMUARGS:-} 2>&1 | grep -E '^screen|^cpu' | grep -v '^screen: *$'
