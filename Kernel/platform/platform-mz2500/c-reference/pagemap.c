/*
 *	MZ-2500 page manager: every process owns a variable number of 8KB
 *	pages (windows 0-6, up to 56KB). A bank token (1..15, kept in p_page)
 *	selects a row of the page table pmap[] in common memory; the map
 *	routines in mz2500.s program the CPU windows from it. Window slots
 *	above the process size point at one shared dummy page.
 *
 *	The udata stash is not here: see mzbank.s (one shared stash page).
 */
#include <kernel.h>
#include <kdata.h>
#include <printf.h>

#define NTOKENS		16
#define DUMMY_PAGE	0x0E		/* shared filler for unused windows */
#define MAXPAGES	7
#define DEFAULT_TOP	0xA000U		/* 40KB when a binary asks for "all" */

extern uint8_t pmap[NTOKENS][8];
extern uint8_t userbanks;		/* free pool size in pages, set by init_hardware */

static uint8_t pfree[24];		/* free physical pages */
static uint8_t pfptr;
static uint8_t tfree[NTOKENS];		/* free bank tokens */
static uint8_t tfptr;
static uint8_t pooltotal;

static uint8_t pages_for(uint16_t top)
{
	uint16_t n = (top + 0x1FFFU) >> 13;
	if (n == 0)
		n = 1;
	if (n > MAXPAGES)
		n = MAXPAGES;
	return (uint8_t)n;
}

void pagemap_init(void)
{
	uint8_t i;

	/* main RAM 08-0C; 0D is the udata stash page, 0E the dummy page */
	for (i = 0x08; i <= 0x0C; i++)
		pfree[pfptr++] = i;
	/* expansion RAM */
	if (userbanks > 5)
		for (i = 0x10; i <= 0x1F; i++)
			pfree[pfptr++] = i;
	pooltotal = pfptr;
	for (i = NTOKENS - 1; i >= 1; i--)
		tfree[tfptr++] = i;
}

void pagemap_add(uint8_t page)
{
	used(page);
}

static void row_clear(uint8_t *row, uint8_t from)
{
	while (from < 8)
		row[from++] = DUMMY_PAGE;
	row[7] = 0;
}

void pagemap_free(ptptr p)
{
	uint8_t tok = (uint8_t)p->p_page;
	uint8_t *row;
	uint8_t i;

	if (tok == 0)
		panic(PANIC_FREE0);
	row = pmap[tok];
	for (i = 0; i < MAXPAGES; i++)
		if (row[i] != DUMMY_PAGE)
			pfree[pfptr++] = row[i];
	row_clear(row, 0);
	tfree[tfptr++] = tok;
}

int pagemap_alloc(ptptr p)
{
	uint8_t need = pages_for(p->p_top);
	uint8_t tok, i;
	uint8_t *row;

	if (tfptr == 0 || need > pfptr)
		return ENOMEM;
	tok = tfree[--tfptr];
	row = pmap[tok];
	for (i = 0; i < need; i++)
		row[i] = pfree[--pfptr];
	row_clear(row, need);
	p->p_page = tok;
	return 0;
}

/* Called from exec with the new top of the program */
int pagemap_realloc(struct exec *hdr, uint16_t size)
{
	uint8_t want = pages_for(size + MAPBASE);
	uint8_t *row = pmap[(uint8_t)udata.u_page];
	uint8_t have = 0;
	uint8_t i;

	used(hdr);
	while (have < MAXPAGES && row[have] != DUMMY_PAGE)
		have++;
	if (want > have) {
		if (want - have > pfptr)
			return ENOMEM;
		for (i = have; i < want; i++)
			row[i] = pfree[--pfptr];
	} else {
		for (i = want; i < have; i++) {
			pfree[pfptr++] = row[i];
			row[i] = DUMMY_PAGE;
		}
	}
	udata.u_ptab->p_size = want << 3;
	return 0;
}

int pagemap_prepare(struct exec *hdr)
{
	/* If it is relocatable load it at PROGLOAD */
	if (hdr->a_base == 0)
		hdr->a_base = PROGLOAD >> 8;
	if (hdr->a_base != (PROGLOAD >> 8)) {
		udata.u_error = ENOEXEC;
		return -1;
	}
	/* "all the memory" means the default size, not the whole 56KB */
	if (hdr->a_size == 0)
		hdr->a_size = (DEFAULT_TOP >> 8) - hdr->a_base;
	/* top = (base + size) << 8 must not pass the 7 windows */
	if ((uint16_t)hdr->a_base + hdr->a_size > (PROGTOP >> 8)) {
		udata.u_error = ENOMEM;
		return -1;
	}
	return 0;
}

usize_t pagemap_mem_used(void)
{
	return (pooltotal - pfptr) << 3;
}
