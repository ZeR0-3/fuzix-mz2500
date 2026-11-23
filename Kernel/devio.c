#include <kernel.h>
#include <printf.h>
#include <kdata.h>
#include <stdarg.h>

/* Error checking */

void validchk(uint16_t dev, const char *p)
{
        if (!validdev(dev)) {
                kputs(p);
                kputchar(':');
                panic(PANIC_INVD);
        }
}

/* Buffer pool management */
/*********************************************************************
The high-level interface is through bread() and bfree().
Bread() is given a device and block number, and a rewrite flag.  If
rewrite is 0, the block is actually read if it is not already in the
buffer pool. If rewrite is set, it is assumed that the caller plans to
rewrite the entire contents of the block, and it will not be read in,
but only have a buffer named after it.

Bfree() is given a buffer pointer and a dirty flag.  If the dirty flag
is 0, the buffer is made available for further use.  If the flag is 1,
the buffer is marked "dirty", and it will eventually be written out to
disk.  If the flag is 2, it will be immediately written out.

Zerobuf() returns a buffer of zeroes not belonging to any device.  It
must be bfree'd after use, and must not be dirty. It is used when a
read() wants to read an unallocated block of a file.

Bufsync() write outs all dirty blocks.

Note that a pointer to a buffer structure is the same as a pointer to
the data if the buffer is inline. This is very important.

FIXME: need to add locking to this for the sleeping case, and a hash for
the bigger systems
**********************************************************************/

extern uint16_t bufclock;		/* Time-stamp counter for LRU (bufcache.s) */

#define bisbusy(x)	((x)->bf_busy == BF_BUSY)

#ifndef CONFIG_BLOCK_SLEEP
#define	block(x)	((x)->bf_busy = BF_BUSY)
#define bunlock(x)	((x)->bf_busy = BF_FREE)
#define bcheck(x)	bisbusy(x)
#define block_s(x)
#define bunlock_s(x)
#else

static void block(bufptr bp)
{
	while (bp->bf_busy == BF_BUSY)
		psleep_nosig(bp);
	bp->bf_busy = BF_BUSY;
}

static void bunlock(bufptr bp)
{
	if (bp->bf_busy == BF_FREE)
		panic(BFREEFREE);
	bp->bf_busy = BF_FREE;
	pwake(bp);
}

#define block_s(x)	block(x)
#define bunlock_s(x)	bunlock(x)
#define bcheck(x)	0

#endif

/*********************************************************************
Bdread() and bdwrite() are the block device interface routines.  They
are given a buffer pointer, which contains the device, block number,
and data location.  They basically validate the device and vector the
call.

Cdread() and cdwrite are the same for character (or "raw") devices,
and are handed a device number.  Udata.u_base, count, and offset have
the rest of the data.
**********************************************************************/

/*********************************************************************
The device driver read and write routines now have only two arguments,
minor and rawflag.  If rawflag is zero, a single block is desired, and
the necessary data can be found in udata.u_buf.  Otherwise, a "raw" or
character read is desired, and udata.u_offset, udata.u_count, and
udata.u_base should be consulted instead.
Any device other than a disk will have only raw access.
**********************************************************************/

static void bdsetup(bufptr bp)
{
	udata.u_buf = bp;
	udata.u_block = bp->bf_blk;
	udata.u_blkoff = 0;
	udata.u_nblock = 1;
	udata.u_dptr = bp->__bf_data;
}

int bdread(bufptr bp)
{
	uint16_t dev = bp->bf_dev;
	validchk(dev, PANIC_BDR);
	bdsetup(bp);
	return ((*dev_tab[major(dev)].dev_read) (minor(dev), 0, 0));
}

int bdwrite(bufptr bp)
{
	uint16_t dev = bp->bf_dev;
	validchk(dev, PANIC_BDW);
	bdsetup(bp);
	return ((*dev_tab[major(dev)].dev_write) (minor(dev), 0, 0));
}

int cdread(uint16_t dev, uint_fast8_t flag)
{
	validchk(dev, PANIC_CDR);
	return ((*dev_tab[major(dev)].dev_read) (minor(dev), 1, flag));
}

int cdwrite(uint16_t dev, uint_fast8_t flag)
{
	validchk(dev, PANIC_CDW);
	return ((*dev_tab[major(dev)].dev_write) (minor(dev), 1, flag));
}

int d_open(uint16_t dev, uint_fast8_t flag)
{
	if (!validdev(dev)) {
	        udata.u_error = ENXIO;
		return -1;
        }
	return ((*dev_tab[major(dev)].dev_open) (minor(dev), flag));
}

int d_close(uint16_t dev)
{
	validchk(dev, PANIC_DCL);
        bdrop(dev);
	return (*dev_tab[major(dev)].dev_close) (minor(dev));
}

int d_ioctl(uint16_t dev, uint16_t request, char *data)
{
	int ret;

	if (!validdev(dev)) {
		udata.u_error = ENXIO;
		return -1;
	}

	ret =  (*dev_tab[major(dev)].dev_ioctl) (minor(dev), request, data);
	/* -1 with no error code means 'unknown ioctl'. Turn this into the
	   right code to save doing it all over */
	if (ret == -1 && !udata.u_error)
			udata.u_error = ENOTTY;
	return ret;
}

int d_flush(uint16_t dev)
{
	/* Not as clean as would be ideal : FIXME */
	int r = d_ioctl(dev, BLKFLSBUF, 0);
	/* Not knowing the ioctl is not an offence */
	if (r && udata.u_error == ENOTTY) {
		udata.u_error = 0;
		r = 0;
	}
	return r;
}

/* 128, 256, 512 supported for now */
static uint16_t masks[3] = { 0x7F, 0xFF, 0x1FF };

/* This is not a commonly used path so can be slower */
int d_blkoff(uint_fast8_t shift)
{
	uint16_t m = masks[shift - 7];
	udata.u_block = udata.u_offset >> shift;
	if (((uint16_t)udata.u_offset) & m) {
		udata.u_error = EIO;
		return -1;
	}
	udata.u_nblock = (udata.u_count + m) >> shift;
	udata.u_dptr = udata.u_base;
	return 0;
}

/*
 *	No such device handler
 */

int nxio_open(uint_fast8_t minor, uint16_t flag)
{
	used(minor);
	used(flag);
	udata.u_error = ENXIO;
	return -1;
}

/*
 *	Default handlers.
 */
int no_open(uint_fast8_t minor, uint16_t flag)
{
	used(minor);
	used(flag);
	return 0;
}

int no_close(uint_fast8_t minor)
{
	used(minor);
	return 0;
}

int no_rdwr(uint_fast8_t minor, uint_fast8_t rawflag, uint_fast8_t flag)
{
	used(minor);
	used(rawflag);
	used(flag);
	udata.u_error = EINVAL;
	return -1;
}

int no_ioctl(uint_fast8_t minor, uarg_t a, char *b)
{
	used(minor);
	used(a);
	used(b);
	udata.u_error = ENOTTY;
	return -1;
}

/*
 *             Character queue management routines
 */

/* add something to the tail of the queue. */
bool insq(struct s_queue * qp, uint_fast8_t c)
{
	regptr struct s_queue *q = qp;
	bool r;

	irqflags_t irq = di();

	if (q->q_count == q->q_size)
		r = false;	// no space left :(
	else {
		PUTQ(q->q_tail, c);
		++q->q_count;
		if (++q->q_tail >= q->q_base + q->q_size)
			q->q_tail = q->q_base;
		r = true;
	}
	irqrestore(irq);
	return r;
}


/* Remove something from the head of the queue. */
bool remq(struct s_queue * qp, uint_fast8_t *cp)
{
	regptr struct s_queue *q = qp;
	bool r;

	irqflags_t irq = di();

	if (!q->q_count)
		r = false;
	else {
		*cp = GETQ(q->q_head);
		--q->q_count;
		if (++q->q_head >= q->q_base + q->q_size)
			q->q_head = q->q_base;
		r = true;
	}

	irqrestore(irq);
	return r;
}


/* Clear the queue to empty conditions.  (UZI280 addition) */
void clrq(struct s_queue *qp)
{
	regptr struct s_queue *q = qp;
	irqflags_t irq = di();

	q->q_head = q->q_tail = q->q_base;
	q->q_count = 0;

	irqrestore(irq);
}


/* Remove something from the tail; the most recently added char. */
bool uninsq(struct s_queue *qp, uint_fast8_t *cp)
{
	regptr struct s_queue *q = qp;
	bool r;
	irqflags_t irq = di();

	if (!q->q_count)
		r = false;
	else {
		--q->q_count;
		if (--q->q_tail < q->q_base)
			q->q_tail = q->q_base + q->q_size - 1;
		*cp = GETQ(q->q_tail);
		r = true;
	}
	irqrestore(irq);
	return r;
}

/* Returns true if the queue has more characters than its wakeup number */
bool fullq(struct s_queue *q)
{
    if (q->q_count > q->q_wakeup) // WRS: shouldn't this be >= ?
        return true;
    else
        return false;
}

/*********************************************************************
             Miscellaneous helpers
**********************************************************************/

int psleep_flags_io(void *p, uint_fast8_t flags)
{
	if (flags & O_NDELAY) {
	        if (!udata.u_done) {
	                udata.u_done = (usize_t)-1;
			udata.u_error = EAGAIN;
                }
		return -1;
	}
	psleep(p);
	if (chksigs()) {
	        if (!udata.u_done) {
	                udata.u_done = (usize_t)-1;
                        udata.u_error = EINTR;
                }
		return -1;
	}
	return 0;
}

int psleep_flags(void *p, uint_fast8_t flags)
{
	if (flags & O_NDELAY) {
		udata.u_error = EAGAIN;
		return -1;
	}
	psleep(p);
	if (chksigs()) {
                udata.u_error = EINTR;
		return -1;
	}
	return 0;
}

void kputs(const char *p)
{
	while (*p)
		kputchar(*p++);
}

static void putdigit0(uint_fast8_t c)
{
	kputchar("0123456789ABCDEF"[c & 15]);
}

static void putdigit(uint_fast8_t c, unsigned char *flag)
{
	if (c || *flag) {
		*flag |= c;
		putdigit0(c);
	}
}

void kputhex(unsigned int v)
{
	putdigit0(v >> 12);
	putdigit0(v >> 8);
	putdigit0(v >> 4);
	putdigit0(v);
}

void kputhexbyte(unsigned int v)
{
	putdigit0(v >> 4);
	putdigit0(v);
}

void kputunum(unsigned int v)
{
	unsigned char n = 0;
#ifdef CONFIG_32BIT
	putdigit((v / 1000000000) % 10, &n);
	putdigit((v / 100000000) % 10, &n);
	putdigit((v / 10000000) % 10, &n);
	putdigit((v / 1000000) % 10, &n);
	putdigit((v / 100000) % 10, &n);
#endif
	putdigit((v / 10000) % 10, &n);
	putdigit((v / 1000) % 10, &n);
	putdigit((v / 100) % 10, &n);
	putdigit((v / 10) % 10, &n);
	putdigit0(v % 10);
}

void kputnum(int v)
{
	if (v < 0) {
		kputchar('-');
		v = -v;
	}
	kputunum(v);
}

void kprintf(const char *fmt, ...)
{
	va_list ap;

	va_start(ap, fmt);
	while (*fmt) {
		if (*fmt == '%') {
			fmt++;
			switch (*fmt) {
				case 's':
				{
					char* str = va_arg(ap, char *);
					kputs(str);
					fmt++;
					continue;
				}

				case 'c':
				{
					char c = va_arg(ap, int);
					kputchar(c);
					fmt++;
					continue;
				}
#ifdef CONFIG_32BIT
				case 'p':
					fmt--;
#endif
				case 'l': /* assume an x is following */
				{
					long l = va_arg(ap, unsigned long);
					/* TODO: not 32-bit safe */
					kputhex((uint16_t)(l >> 16));
					kputhex((uint16_t)l);
					fmt += 2;
					continue;
				}

				case '2': /* assume an x is following */
				{
					char c = va_arg(ap, int);
					kputhexbyte(c);
					fmt += 2;
					continue;
				}

#ifndef CONFIG_32BIT
				case 'p':
#endif
				case 'x':
				case 'd':
				case 'u':
				{
					unsigned int v = va_arg(ap, int);

					if (*fmt == 'x' || *fmt == 'p')
						kputhex(v);
					else if (*fmt == 'd')
						kputnum(v);
					else if (*fmt == 'u')
						kputunum(v);

					fmt++;
					continue;
				}
			}
		}
		kputchar(*fmt);
		fmt++;
	}

	va_end(ap);
}

#ifdef CONFIG_IDUMP

void bufdump(void)
{
	bufptr j;

	kprintf("\ndev\tblock\tdirty\tbusy\ttime clock %d\n", bufclock);
	for (j = bufpool; j < bufpool_end; ++j)
		kprintf("%d\t%u\t%d\t%d\t%u\n", j->bf_dev, j->bf_blk,
			j->bf_dirty, j->bf_busy, j->bf_time);
}

void idump(void)
{
	inoptr ip;
	ptptr pp;
	extern struct cinode i_tab[];

	kprintf("Err %d root %d\n", udata.u_error, root - i_tab);
	kputs("\tMAGIC\tDEV\tNUM\tMODE\tNLINK\t(DEV)\tREFS\tR/W\tDIRTY\n");

	for (ip = i_tab; ip < i_tab + ITABSIZE; ++ip) {
		if(ip->c_magic != CMAGIC)
			continue;
		kprintf("%d\t%d\t%d\t%u\t%u\t",
			ip - i_tab, ip->c_magic, ip->c_dev, ip->c_num,
			ip->c_node.i_mode);
		kprintf("%d\t%d\t%d\t%d:%d\t%d\n",
			ip->c_node.i_nlink, ip->c_node.i_addr[0],
			ip->c_refs, ip->c_readers,ip->c_writers, ip->c_flags);
	}

	kputs
	    ("\n\tSTAT\tWAIT\tPID\tPPTR\tALARM\tPENDING\t\tIGNORED\n");
	for (pp = ptab; pp < ptab + PTABSIZE /*maxproc */ ; ++pp) {
		if (pp->p_status == P_EMPTY)
			continue;
		kprintf("%d\t%d\t0x%x\t%d\t",
			pp - ptab, pp->p_status, pp->p_wait, pp->p_pid);
		kprintf("%d\t%d\t0x%x%x\t0x%x%x\n",
			pp->p_pptr - ptab, pp->p_alarm, 
			/* kprintf has no %lx so we write out 32-bit
			 * values as two 16-bit values instead */
			pp->p_sig[0].s_pending, pp->p_sig[1].s_pending,
			pp->p_sig[0].s_ignored, pp->p_sig[1].s_ignored);
	}

	bufdump();

	kprintf("insys %d ptab %d call %d cwd %d sp 0x%x\n",
		udata.u_insys, udata.u_ptab - ptab, udata.u_callno,
		udata.u_cwd - i_tab, udata.u_sp);
}

#endif
