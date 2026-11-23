; data_asm.s - kernel global data, system-call dispatch table (hand-written)
	.module data_asm
	.globl _syscall_dispatch
	.globl ___exit,__open,__close,__rename,__mknod,__link,__unlink,__read,__write,__lseek,__chdir,__sync
	.globl __access,__chmod,__chown,__stat,__fstat,__dup,__getpid,__getppid,__getuid,__umask,__statfs,__execve
	.globl __getdirent,__setuid,__setgid,__time,__stime,__ioctl,__brk,__sbrk,__fork,__mount,__umount,__signal
	.globl __dup2,__pause,__alarm,__kill,__pipe,__getgid,__times,__utime,__geteuid,__getegid,__chroot,__fcntl
	.globl __fchdir,__fchmod,__fchown,__mkdir,__rmdir,__setpgrp,__uname,__waitpid,__profil,__uadmin,__nice
	.globl __sigdisp,__flock,__getpgrp,__sched_yield,__acct,__memalloc,__memfree,__nosys,__ftruncate,_ptab
	.area _DATA
_tod_deci::
	.ds 1
_rtcsec::
	.ds 1
_init_process::
	.ds 2
_ramsize::
	.ds 2
_procmem::
	.ds 2
_maxproc::
	.ds 2
_nproc::
	.ds 2
_nready::
	.ds 1
_inswap::
	.ds 1
_runticks::
	.ds 2
_root_dev::
	.ds 2
_ticks_this_dsecond::
	.ds 1
_ticks_per_dsecond::
	.ds 1
_root::
	.ds 2
_waitno::
	.ds 2
_tod::
	.ds 8
_ticks::
	.ds 4
_bufpool::
	.ds 3120
_ptab::
	.ds 1125
_ptab_end::
	.ds 2
_alarms::
	.ds 2
_of_tab::
	.ds 256
_i_tab::
	.ds 1500
_fs_tab::
	.ds 908
_lastname::
	.ds 31
_load_average_utick::
	.ds 1
__rename_srci_65536_290::
	.ds 2
__rename_srcp_65536_290::
	.ds 2
__rename_dsti_65536_290::
	.ds 2
__rename_dstp_65536_290::
	.ds 2
_ttydata::
	.ds 64
_tty_ioctl_tm::
	.ds 20
	.area _INITIALIZED
_cmdline::
	.ds 2
_loadavg::
	.ds 9
_getproc_nextp::
	.ds 2
_nextpid::
	.ds 2
	.area _INITIALIZER
__xinit__cmdline:
	.dw #0x0000
__xinit__loadavg:
	.db #0xeb	; 235
	.dw #0x0000
	.db #0xfb	; 251
	.dw #0x0000
	.db #0xfe	; 254
	.dw #0x0000
__xinit__getproc_nextp:
	.dw (_ptab + 0)
__xinit__nextpid:
	.dw #0x0000
	.area _CONST
_syscall_dispatch:
	.dw ___exit
	.dw __open
	.dw __close
	.dw __rename
	.dw __mknod
	.dw __link
	.dw __unlink
	.dw __read
	.dw __write
	.dw __lseek
	.dw __chdir
	.dw __sync
	.dw __access
	.dw __chmod
	.dw __chown
	.dw __stat
	.dw __fstat
	.dw __dup
	.dw __getpid
	.dw __getppid
	.dw __getuid
	.dw __umask
	.dw __statfs
	.dw __execve
	.dw __getdirent
	.dw __setuid
	.dw __setgid
	.dw __time
	.dw __stime
	.dw __ioctl
	.dw __brk
	.dw __sbrk
	.dw __fork
	.dw __mount
	.dw __umount
	.dw __signal
	.dw __dup2
	.dw __pause
	.dw __alarm
	.dw __kill
	.dw __pipe
	.dw __getgid
	.dw __times
	.dw __utime
	.dw __geteuid
	.dw __getegid
	.dw __chroot
	.dw __fcntl
	.dw __fchdir
	.dw __fchmod
	.dw __fchown
	.dw __mkdir
	.dw __rmdir
	.dw __setpgrp
	.dw __uname
	.dw __waitpid
	.dw __profil
	.dw __uadmin
	.dw __nice
	.dw __sigdisp
	.dw __flock
	.dw __getpgrp
	.dw __sched_yield
	.dw __acct
	.dw __memalloc
	.dw __memfree
	.dw __nosys
	.dw __ftruncate
