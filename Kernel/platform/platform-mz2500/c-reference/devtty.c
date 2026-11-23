/*
 *	MZ-2500 text console. Text VRAM (physical page 38h) is permanently in
 *	CPU window 6 (C000h) of the kernel bank:
 *		C000h Text1 plane, C800h attribute plane, D000h Text2 plane
 *	A cell is (row * VT_WIDTH + col) in each plane. For a character c the
 *	two glyph-select bytes are Text1 = (c & 3Fh) * 4 and Text2 = 8Ch + (c >> 6).
 */
#include <kernel.h>
#include <kdata.h>
#include <printf.h>
#include <stdbool.h>
#include <devtty.h>
#include <vt.h>
#include <tty.h>

#define TEXT1	((volatile uint8_t *)0xC000)
#define TEXTA	((volatile uint8_t *)0xC800)
#define TEXT2	((volatile uint8_t *)0xD000)
#define CELLS	(VT_WIDTH * VT_HEIGHT)

uint8_t vtattr_cap = 0;

static uint8_t tbuf1[TTYSIZ];

struct s_queue ttyinq[NUM_DEV_TTY + 1] = {	/* ttyinq[0] is never used */
	{NULL, NULL, NULL, 0, 0, 0},
	{tbuf1, tbuf1, tbuf1, TTYSIZ, 0, TTYSIZ / 2},
};

tcflag_t termios_mask[NUM_DEV_TTY + 1] = {
	0,
	_CSYS,
};

static uint16_t cursor_cell;
static uint8_t cursor_save1, cursor_save2;
static bool cursor_shown;

static void put_cell(uint16_t off, uint8_t c)
{
	TEXT1[off] = (uint8_t)((c & 0x3F) << 2);
	TEXT2[off] = (uint8_t)(0x8C + ((c >> 6) & 3));
}

extern void vram_clear(void);
extern uint16_t vstart;
#define CELLOFF(y, x) ((uint16_t)(((uint16_t)(y) * VT_WIDTH + (x) + vstart) & 0x7FF))

void mz_video_init(void)
{
	vram_clear();
	cursor_shown = false;
	vtinit();
}

void clear_lines(int8_t y, int8_t ct)
{
	clear_across(y, 0, (int16_t)ct * VT_WIDTH);
}

void cursor_off(void)
{
	if (cursor_shown) {
		TEXT1[cursor_cell] = cursor_save1;
		TEXT2[cursor_cell] = cursor_save2;
		cursor_shown = false;
	}
}

void cursor_on(int8_t y, int8_t x)
{
	cursor_off();
	cursor_cell = CELLOFF(y, x);
	cursor_save1 = TEXT1[cursor_cell];
	cursor_save2 = TEXT2[cursor_cell];
	put_cell(cursor_cell, VT_CURSOR_CHAR);
	cursor_shown = true;
}

void cursor_disable(void)
{
	cursor_off();
}

void plot_char(int8_t y, int8_t x, uint16_t c)
{
	uint16_t off = CELLOFF(y, x);
	put_cell(off, (uint8_t)c);
	if (cursor_shown && off == cursor_cell) {
		/* overwriting the cursor cell: remember the new content */
		cursor_save1 = TEXT1[off];
		cursor_save2 = TEXT2[off];
	}
}

void do_beep(void)
{
}

void vtattr_notify(void)
{
}

/* Output for the system console (kprintf etc) */
void kputchar(uint_fast8_t c)
{
	if (c == '\n')
		tty_putc(minor(TTYDEV), '\r');
	tty_putc(minor(TTYDEV), c);
}

ttyready_t tty_writeready(uint_fast8_t minor)
{
	used(minor);
	return TTY_READY_NOW;
}

void tty_putc(uint_fast8_t minor, uint_fast8_t c)
{
	used(minor);
	vtoutput(&c, 1);
}

int tty_carrier(uint_fast8_t minor)
{
	used(minor);
	return 1;
}

void tty_data_consumed(uint_fast8_t minor)
{
	used(minor);
}

void tty_setup(uint_fast8_t minor, uint_fast8_t flags)
{
	used(minor);
	used(flags);
}

void tty_sleeping(uint_fast8_t minor)
{
	used(minor);
}

/*
 *	Keyboard. Row (0-13) is selected through E8h (bit 4 = strobe enable,
 *	bits 3-0 = row); E8h bits 7-5 hold other state (bit 5 = 80 columns) so
 *	they are read back and preserved. EAh returns the row, 0 = pressed.
 *	Scanned at the 50Hz timer tick.
 */
__sfr __at 0xE8 kbd_row;
__sfr __at 0xEA kbd_data;

#define NROWS	12
#define K_UP	KEY_UP
#define K_DN	KEY_DOWN
#define K_LT	KEY_LEFT
#define K_RT	KEY_RIGHT

/* [row][bit 0..7] */
static const uint8_t keytab[NROWS][8] = {
	{0, 0, 0, 0, 0, 0, 0, 0},					/* F1-F8 */
	{0, 0, '8', '9', ',', '.', '+', '-'},				/* F9 F10 tenkey */
	{'0', '1', '2', '3', '4', '5', '6', '7'},			/* tenkey */
	{KEY_TAB, ' ', '\r', K_UP, K_DN, K_LT, K_RT, KEY_STOP},
	{'/', 'a', 'b', 'c', 'd', 'e', 'f', 'g'},
	{'h', 'i', 'j', 'k', 'l', 'm', 'n', 'o'},
	{'p', 'q', 'r', 's', 't', 'u', 'v', 'w'},
	{'x', 'y', 'z', '^', '\\', '_', '.', ','},
	{'0', '1', '2', '3', '4', '5', '6', '7'},
	{'8', '9', ':', ';', '-', '@', '[', 0},
	{']', 0, KEY_HOME, KEY_DEL, KEY_BS, KEY_ESC, '*', '/'},
	{0, 0, 0, 0, 0, 0, 0, 0},					/* modifiers */
};

static const uint8_t keytab_shift[NROWS][8] = {
	{0, 0, 0, 0, 0, 0, 0, 0},
	{0, 0, '8', '9', ',', '.', '+', '-'},
	{'0', '1', '2', '3', '4', '5', '6', '7'},
	{KEY_TAB, ' ', '\r', K_UP, K_DN, K_LT, K_RT, KEY_STOP},
	{'?', 'A', 'B', 'C', 'D', 'E', 'F', 'G'},
	{'H', 'I', 'J', 'K', 'L', 'M', 'N', 'O'},
	{'P', 'Q', 'R', 'S', 'T', 'U', 'V', 'W'},
	{'X', 'Y', 'Z', '~', '|', '_', '>', '<'},
	{0, '!', '"', '#', '$', '%', '&', '\''},
	{'(', ')', '*', '+', '=', '`', '{', 0},
	{'}', 0, KEY_HOME, KEY_DEL, KEY_BS, KEY_ESC, '*', '/'},
	{0, 0, 0, 0, 0, 0, 0, 0},
};

struct vt_repeat keyrepeat = { 25, 3 };

uint8_t keyin[NROWS];		/* scanned by kbd_interrupt (kbd.s) */
uint8_t keyprev[NROWS];
int8_t held_row = -1;
static uint8_t held_bit;
static uint8_t held_timer;

static void key_emit(uint_fast8_t row, uint_fast8_t bit)
{
	uint_fast8_t mod = keyin[11];
	uint_fast8_t c;

	if (mod & 0x04)				/* SHIFT */
		c = keytab_shift[row][bit];
	else
		c = keytab[row][bit];
	if (!c)
		return;
	if (mod & 0x02)				/* LOCK = caps */
		if (c >= 'a' && c <= 'z')
			c -= 'a' - 'A';
		else if (c >= 'A' && c <= 'Z' && (mod & 0x04))
			c += 'a' - 'A';
	if (mod & 0x10) {			/* CTRL */
		if (c >= '@' && c <= '_')
			c &= 0x1F;
		else if (c >= 'a' && c <= 'z')
			c &= 0x1F;
	}
	vt_inproc(1, c);
}

/* kbd.s scans the matrix into keyin[] and only calls this when a key
   changed or one is being held (auto repeat) */
void kbd_process(void)
{
	uint_fast8_t r, b, mask, v;

	if (held_row >= 0) {
		if (keyin[held_row] & (1 << held_bit)) {
			if (--held_timer == 0) {
				key_emit(held_row, held_bit);
				held_timer = keyrepeat.continual;
			}
		} else
			held_row = -1;
	}
	for (r = 0; r < NROWS - 1; r++) {	/* row 11 = modifiers */
		v = keyin[r] & ~keyprev[r];
		if (!v)
			continue;
		for (b = 0, mask = 1; b < 8; b++, mask <<= 1) {
			if (v & mask) {
				key_emit(r, b);
				held_row = r;
				held_bit = b;
				held_timer = keyrepeat.first;
			}
		}
	}
	for (r = 0; r < NROWS; r++)
		keyprev[r] = keyin[r];
}

/* Used by the vt core */
uint16_t cursorpos;
