;
;	MZ-2500 keyboard scan, run from the 50Hz interrupt.
;	E8h: bits 7-5 kept, bit 4 = strobe enable, bits 3-0 = row; EAh = columns
;	(0 = pressed). The 12 rows are read into keyin[]; the common case (no
;	change, nothing held) returns here without touching the C code.
;
	.module kbd

	.globl _kbd_interrupt
	.globl _kbd_process
	.globl _keyin
	.globl _keyprev
	.globl _held_row

NROWS		.equ 12

	.area _COMMONMEM

_kbd_interrupt:
	ld hl, #_keyin
	ld b, #NROWS
	ld c, #0
1$:	in a, (0xE8)
	and #0xE0
	or #0x10
	or c
	out (0xE8), a
	in a, (0xEA)
	cpl
	ld (hl), a
	inc hl
	inc c
	djnz 1$
	ld a, (_held_row)
	or a
	jp p, _kbd_process	; a key is held: repeat timer must run
	ld hl, #_keyin
	ld de, #_keyprev
	ld b, #NROWS
2$:	ld a, (de)
	cp (hl)
	jp nz, _kbd_process
	inc hl
	inc de
	djnz 2$
	ret
