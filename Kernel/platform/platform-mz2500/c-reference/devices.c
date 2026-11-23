#include <kernel.h>
#include <version.h>
#include <kdata.h>
#include <tty.h>
#include <vt.h>
#include <devsys.h>
#include <devtty.h>
#include <devhd.h>

struct devsw dev_tab[] =  /* The device driver switch table */
{
  /* 0: /dev/hd		Hard disc block devices (SASI: not yet) */
  {  hd_open,     no_close,    hd_read,   hd_write,   no_ioctl  },
  /* 1: /dev/fd		Floppy disc block devices */
  {  no_open,     no_close,    no_rdwr,   no_rdwr,    no_ioctl  },
  /* 2: /dev/tty	TTY devices */
  {  tty_open,    tty_close,   tty_read,  tty_write,  vt_ioctl  },
  /* 3: /dev/lpr	Printer devices */
  {  no_open,     no_close,    no_rdwr,   no_rdwr,    no_ioctl  },
  /* 4: /dev/mem etc	System devices (one offs) */
  {  no_open,     no_close,    sys_read,  sys_write,  sys_ioctl },
};

bool validdev(uint16_t dev)
{
	if (dev > ((sizeof(dev_tab)/sizeof(struct devsw)) << 8) - 1)
		return false;
	return true;
}

void device_init(void)
{
	hd_probe();
}
