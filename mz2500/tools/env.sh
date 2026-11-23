# Common settings for the MZ-2500 port scripts. Source this file; override any
# variable from the environment before running a script.
#
#   MZ_FUZIX     FUZIX source tree with this repository's files copied over it
#                (see install.sh).  Default: ../FUZIX-master next to this repo.
#   MZ_EMU       MZ-2500 emulator command line tool (mz2500w-cli).
#   MZ_ROMDIR    directory with your own MZ-2500 ROMs (IPL ROM etc.). NOT included.
#   MZ_SASI_ROM  your own SASI option ROM (FILE.ROM). NOT included.
#   MZ_TOOLCHAIN directories with the Z80 toolchain (fcc, sdcc280, flex), PATH style.
_MZ_HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export MZ_WORK="${MZ_WORK:-$_MZ_HERE}"
export MZ_FUZIX="${MZ_FUZIX:-$(cd "$_MZ_HERE/../.." 2>/dev/null && pwd)/FUZIX-master}"
export MZ_EMU="${MZ_EMU:-mz2500w-cli}"
export MZ_ROMDIR="${MZ_ROMDIR:-$HOME/mz2500-roms}"
export MZ_SASI_ROM="${MZ_SASI_ROM:-$MZ_ROMDIR/FILE.ROM}"
export MZ_TOOLCHAIN="${MZ_TOOLCHAIN:-/opt/fcc/bin:$HOME/tools/sdcc280/bin:$HOME/tools/local/bin}"
export PATH="$MZ_TOOLCHAIN:$PATH"
export FUZIX_ROOT="$MZ_FUZIX" USERCPU=z80 CPU=z80 TARGET=mz2500
