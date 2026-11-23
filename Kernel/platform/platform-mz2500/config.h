/* Sharp MZ-2500 platform configuration */
#undef CONFIG_IDUMP
#undef CONFIG_MONITOR
#undef CONFIG_PROFIL
#define CONFIG_MULTI
/* page-table memory manager in pagemap.c (not mm/bankfixed.c) */
#define CONFIG_VT
#define CONFIG_SMALL

/* User banks: 7 x 8K RAM pages (window 0-6); kernel bank is separate */
#define CONFIG_BANKS	1

/* the disk driver only transfers into kernel buffers */
#define CONFIG_LARGE_IO_DIRECT(x)	0
#define BOOTDEVICENAMES "hd#,fd"

/* Text screen: 40 x 25 as left by the IPL */
#define VT_WIDTH	40
#define VT_HEIGHT	25
#define VT_RIGHT	39
#define VT_BOTTOM	24

#define TICKSPERSEC 50		/* 8253 ch0 -> 50Hz */
#define PROGBASE    0x0000
#define PROGLOAD    0x0100
#define PROGTOP     0xE000	/* Top of program, base of U_DATA stash */
#define PROC_SIZE   8		/* KB: the unit of memory is one 8KB page */
#define PTABSIZE    15

#define BOOT_TTY (512 + 1)
#define CMDLINE	NULL

#define NUM_DEV_TTY 1
#define TTYDEV   BOOT_TTY
#define NBUFS       6
#define OFTSIZE     32
#define NMOUNTS	 4

#define plt_discard()
#define plt_copyright()
