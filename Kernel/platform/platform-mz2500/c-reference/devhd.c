/*
 *	MZ-1E30 style SASI hard disk driver (SASI ID 0, LUN 0).
 *
 *	A4h = data (an access acknowledges the byte), A5h = status (read) /
 *	control (write). Status: b7 REQ, b6 ACK, b5 BSY, b4 MSG, b3 C/D,
 *	b2 I/O. Control: b5 SEL, b3 RST. The disk has 256 byte blocks, a Fuzix
 *	block (512 bytes) is two of them.
 *
 *	Layout: block 3 holds the "EHSASI" partition table (signature, then up
 *	to 15 entries of 16 bytes). The partition flagged for priority boot
 *	(entry byte 0, bit 7) is Fuzix drive hda. Its first FSBASE blocks are the
 *	boot area (IPLPRO header and kernel image), the Fuzix filesystem follows.
 *
 *	Minor numbers: bits 7-4 drive (only 0), bits 3-0 partition: 0 = the
 *	filesystem area of the boot partition. Others are not yet supported.
 *
 *	Only transfers into kernel buffers (rawflag 0) are implemented; set
 *	CONFIG_LARGE_IO_DIRECT to 0 so the kernel always goes via the buffer
 *	cache.
 */
#include <kernel.h>
#include <kdata.h>
#include <printf.h>
#include <devhd.h>

extern int emm_cache_get(uint16_t blk, uint8_t *buf);
extern void emm_cache_put(uint16_t blk, uint8_t *buf);
extern void emm_cache_init(void);

__sfr __at 0xA4 sasi_data;
__sfr __at 0xA5 sasi_ctl;

#define ST_REQ	0x80
#define ST_ACK	0x40
#define ST_BSY	0x20
#define ST_MSG	0x10
#define ST_CD	0x08
#define ST_IO	0x04

#define SEL	0x20
#define RST	0x08

#define PHASE_MASK	(ST_MSG | ST_CD | ST_IO)
#define PH_CMD		(ST_CD)
#define PH_DIN		(ST_IO)
#define PH_DOUT		(0)
#define PH_STATUS	(ST_CD | ST_IO)
#define PH_MSGIN	(ST_MSG | ST_CD | ST_IO)

#define FSBASE		512UL		/* boot area, in 256 byte blocks */
#define SPIN		60000U

static uint32_t part_top;		/* first block of the boot partition */
static uint32_t part_len;		/* capacity in 256 byte blocks */
static uint8_t hd_present;
static uint8_t sasi_cdb[6];

/* wait for REQ with ACK low; returns the status or 0 on timeout */
static uint8_t wait_req(void)
{
	uint16_t n = SPIN;
	uint8_t s;
	while (n--) {
		s = sasi_ctl;
		if ((s & (ST_REQ | ST_ACK)) == ST_REQ)
			return s;
	}
	return 0;
}

/* the bus is free or the target has let go */
static uint8_t wait_free(void)
{
	uint16_t n = SPIN;
	while (n--) {
		if (!(sasi_ctl & ST_BSY))
			return 1;
	}
	return 0;
}

static void sasi_reset(void)
{
	uint16_t n;
	sasi_ctl = RST;
	for (n = 0; n < 2000; n++)
		;
	sasi_ctl = 0;
	for (n = 0; n < 20000; n++)
		;
}

/* select the target and send the 6 byte command. 0 = ok */
static int sasi_command(void)
{
	uint8_t i;
	uint16_t n;
	uint8_t s;

	if (!wait_free())
		return -1;
	sasi_data = 0x01;		/* ID 0 */
	sasi_ctl = SEL;
	n = SPIN;
	while (n--) {
		if (sasi_ctl & ST_BSY)
			break;
	}
	sasi_ctl = 0;
	if (!(sasi_ctl & ST_BSY))
		return -1;
	for (i = 0; i < 6; i++) {
		s = wait_req();
		if (!s || (s & PHASE_MASK) != PH_CMD)
			return -1;
		sasi_data = sasi_cdb[i];
	}
	return 0;
}

/* status and message phases after the data: 0 = good */
static int sasi_finish(void)
{
	uint8_t s, status = 0xFF;
	uint8_t n = 8;

	while (n--) {
		s = wait_req();
		if (!s)
			return -1;
		switch (s & PHASE_MASK) {
		case PH_STATUS:
			status = sasi_data;
			break;
		case PH_MSGIN:
			(void)sasi_data;
			return status ? -1 : 0;
		default:
			return -1;
		}
	}
	return -1;
}

static void sasi_setup(uint8_t op, uint32_t lba, uint8_t count)
{
	sasi_cdb[0] = op;
	sasi_cdb[1] = (uint8_t)(lba >> 16) & 0x1F;	/* LUN 0 */
	sasi_cdb[2] = (uint8_t)(lba >> 8);
	sasi_cdb[3] = (uint8_t)lba;
	sasi_cdb[4] = count;
	sasi_cdb[5] = 0;
}

extern int sasi_rd512(uint8_t *buf);
extern int sasi_wr512(uint8_t *buf);

/* transfer 512 bytes (2 blocks) between the disk and a kernel buffer */
static int sasi_xfer(uint8_t *buf, uint32_t lba, bool is_read)
{

	sasi_setup(is_read ? 0x08 : 0x0A, lba, 2);
	if (sasi_command() < 0) {
		sasi_reset();
		return -1;
	}
	if (is_read ? sasi_rd512(buf) : sasi_wr512(buf))
		goto bad;
	if (sasi_finish() < 0)
		goto bad;
	return 0;
bad:
	sasi_reset();
	return -1;
}

/* read one 256 byte block at the start; used for the partition table */
static int sasi_read256(uint8_t *buf, uint32_t lba)
{
	uint16_t i;
	uint8_t s;

	sasi_setup(0x08, lba, 1);
	if (sasi_command() < 0) {
		sasi_reset();
		return -1;
	}
	for (i = 0; i < 256; i++) {
		s = wait_req();
		if (!s || (s & PHASE_MASK) != PH_DIN) {
			sasi_reset();
			return -1;
		}
		*buf++ = sasi_data;
	}
	if (sasi_finish() < 0) {
		sasi_reset();
		return -1;
	}
	return 0;
}

static uint8_t ptbuf[256];

void hd_probe(void)
{
	uint8_t *e;
	uint8_t i;

	hd_present = 0;
	if (sasi_ctl == 0xFF)			/* no interface */
		return;
	sasi_reset();
	if (sasi_read256(ptbuf, 3) < 0) {
		kputs("hd: no disk\n");
		return;
	}
	if (ptbuf[0] != 'E' || ptbuf[1] != 'H' || ptbuf[2] != 'S' ||
	    ptbuf[3] != 'A' || ptbuf[4] != 'S' || ptbuf[5] != 'I') {
		kputs("hd: no partition table\n");
		return;
	}
	for (i = 1; i < 16; i++) {
		e = ptbuf + (i << 4);
		if (e[0] & 0x80) {		/* priority boot partition */
			part_len = ((uint32_t)e[1] << 8) | e[2];
			part_top = ((uint32_t)e[5] << 16) | ((uint32_t)e[6] << 8) | e[7];
			hd_present = 1;
			emm_cache_init();
			kprintf("hd: partition at block %lx, %d blocks\n",
				part_top, (uint16_t)part_len);
			return;
		}
	}
	kputs("hd: no boot partition\n");
}

int hd_open(uint_fast8_t minor, uint16_t flag)
{
	used(flag);
	if (!hd_present || minor != 0) {
		udata.u_error = ENODEV;
		return -1;
	}
	return 0;
}

static int hd_transfer(bool is_read, uint_fast8_t rawflag)
{
	uint32_t lba;

	if (rawflag) {
		/* user space transfers are not supported yet */
		udata.u_error = EIO;
		return -1;
	}
	lba = part_top + FSBASE + ((uint32_t)udata.u_block << 1);
	if (lba + 2 > part_top + part_len) {
		udata.u_error = EIO;
		return -1;
	}
	if (is_read && emm_cache_get(udata.u_block, (uint8_t *)udata.u_dptr))
		return BLKSIZE;
	if (sasi_xfer((uint8_t *)udata.u_dptr, lba, is_read) < 0) {
		udata.u_error = EIO;
		return -1;
	}
	emm_cache_put(udata.u_block, (uint8_t *)udata.u_dptr);
	return BLKSIZE;
}

int hd_read(uint_fast8_t minor, uint_fast8_t rawflag, uint_fast8_t flag)
{
	used(minor);
	used(flag);
	return hd_transfer(true, rawflag);
}

int hd_write(uint_fast8_t minor, uint_fast8_t rawflag, uint_fast8_t flag)
{
	used(minor);
	used(flag);
	return hd_transfer(false, rawflag);
}
