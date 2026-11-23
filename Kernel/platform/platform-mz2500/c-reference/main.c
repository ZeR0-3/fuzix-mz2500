#include <kernel.h>
#include <timer.h>
#include <kdata.h>
#include <printf.h>
#include <devtty.h>

uaddr_t ramtop = PROGTOP;

void plt_idle(void)
{
	/* nothing to poll yet: wait for the next interrupt */
	__asm
	halt
	__endasm;
}

void plt_interrupt(void)
{
	kbd_interrupt();
	timer_interrupt();
}

void map_init(void)
{
}

uint_fast8_t plt_param(char *p)
{
	used(p);
	return 0;
}
