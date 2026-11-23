# FUZIX for the Sharp MZ-2500

A port of [FUZIX](https://github.com/EtchedPixels/FUZIX) (a UNIX-like OS for 8-bit systems) to the **Sharp MZ-2500**
(Z80A, 256 KB RAM, banked memory). The kernel is written entirely in Z80 assembly; the root filesystem lives on a
SASI hard disk or on a bootable 2DD floppy.

Status: runs in the [MZ-2500 web emulator](https://github.com/Zabaglione/mz2500-web-emulator) (native CLI); **not yet tested on real hardware**.
See [`docs/REALHW-CHECKLIST.md`](docs/REALHW-CHECKLIST.md) for what to check first.

シャープ MZ-2500 向けの FUZIX 移植です。カーネルは全て Z80 アセンブラで書かれています。ルートファイルシステムは
SASI ハードディスク、またはブート可能な 2DD フロッピーに置きます。現在はエミュレータで動作確認済みで、**実機は未確認**です。

## What is in this repository / 内容

| Path | Contents |
|---|---|
| `Kernel/platform/platform-mz2500/` | the port: all kernel code (`*.s`), `config.h`, linker script, Makefile |
| `Kernel/platform/platform-mz2500/c-reference/` | the original C implementations (not built; kept as reference for the assembly) |
| `Kernel/`, `Applications/`, `Library/` (other files) | small changes to upstream FUZIX files and new utilities (see below) |
| `mz2500/` | build/test scripts (`tools/`), root filesystem files (`etc/`), `run_hdd.sh` |
| `docs/` | guide and real-hardware checklist |
| `install.sh` | copies the overlay onto a FUZIX source tree |

Changes to upstream files (everything else under `Kernel/`, `Applications/`, `Library/` is new):

- `Kernel/syscall_fs3.c`: permission check when opening an existing file (upstream only checks on creation)
- `Kernel/devio.c`: buffer-cache functions removed (they are implemented in assembly in the port directory)
- `Applications/util/init.c`, `Applications/V7/cmd/sh/xec.c`: init no longer leaves SIGWINCH pending for the shell it starts; the shell exits correctly after a forked builtin
- `Applications/util/Makefile.common`: adds `ln`, `mv`, `fdformat`, `fdcopy`
- `Library/libs/ltostr.c`: 16-bit arithmetic for the common case (32-bit division is very slow on a Z80)
- `Applications/util/`: new `ln`, `mv`, `fdformat`, `fdcopy` and the test programs `edge*.c`, `vtt.c`, `flk.c`, `ftest.c`

## Requirements / 必要なもの

- A FUZIX source tree (upstream `master`), a Z80 toolchain as FUZIX needs it: the Fuzix Compiler Kit / Bintools
  (`fcc`, `asz80`, `ldz80`), SDCC 3.9 (Z80 port; compiles the few generic kernel C files that are still used), flex, Python 3.
- The MZ-2500 emulator CLI (`mz2500w-cli`) for the test scripts.
- **Your own MZ-2500 ROMs** (IPL ROM, and the SASI option ROM `FILE.ROM` for hard disk boot). They are not included
  and must not be added to this repository.

## Quick start

```sh
git clone https://github.com/EtchedPixels/FUZIX.git     # or any FUZIX tree
git clone <this repository> fuzix-mz2500
fuzix-mz2500/install.sh FUZIX
export MZ_FUZIX=$PWD/FUZIX MZ_EMU=/path/to/mz2500w-cli MZ_ROMDIR=/path/to/your/roms MZ_SASI_ROM=/path/to/FILE.ROM
cd fuzix-mz2500/mz2500
./tools/build_userland.sh        # host tools, libraries, applications
./tools/mkroot.sh $PWD/root.img  # root filesystem image
./run_hdd.sh                     # builds the kernel, makes the disk images, boots (answer the prompt with: hda)
./tools/regress.sh               # regression tests (also --no-emm); fdtest.sh, fscheck.sh
./tools/mkfdsys.sh               # bootable floppy: fdboot.d88
```

Settings are in `mz2500/tools/env.sh` (environment variables `MZ_FUZIX`, `MZ_EMU`, `MZ_ROMDIR`, `MZ_SASI_ROM`, `MZ_TOOLCHAIN`).
Boot prompt: `hda` (hard disk), `hda rw`, `fd0 rw` (floppy).

More details: [`docs/GUIDE.md`](docs/GUIDE.md).

## Author

Port by ZeR0-3.

## License

FUZIX is licensed under the GNU GPL v2 (see `LICENSE`, the upstream licence file, which also lists the LGPL parts for the
libraries). The files added by this port are distributed under the same terms (GPLv2). Applications under
`Applications/` may carry their own licences; check the licence files of the relevant directories.

No third-party source code from other MZ-2500 projects is included. `mz2500/tools/emu-profiler.patch` is a small
development patch for the (MIT licensed) emulator.
