;
;	MZ-2500 text console primitives in assembler.
;	Text1 plane C000h, attribute C800h, Text2 plane D000h (window 6),
;	80 columns x 25 rows (E8h bit 5, CRTC 7/8 set in _mz_video_init). Glyph blank = Text1 80h / Text2 8Ch.
;	C callable (SDCC: args on stack, caller cleans up):
;	  void scroll_up(void), scroll_down(void),
;	  void clear_across(int8_t y, int8_t x, int16_t l), void vram_clear(void)
;
	.module video

	.globl _scroll_up
	.globl _scroll_down
	.globl _clear_across
	.globl _vram_clear
	.globl _vstart

TEXT1		.equ 0xC000
TEXTA		.equ 0xC800
TEXT2		.equ 0xD000
COLS		.equ 80
ROWS		.equ 25

	.area _COMMONMEM

; The text planes are 2KB rings (800h cells) and the CRTC shows 2000 cells
; from the start cell in CRTC registers 01h (low) / 02h (high 3 bits).
; Scrolling only moves that start cell by one row and blanks the new row.
; _vstart = ring offset of logical row 0.

; scroll_up: new bottom row = old row 25 position (vstart + 2000)
_scroll_up:
	ld hl, (_vstart)
	ld de, #COLS * ROWS
	add hl, de
	call blankrow
	ld hl, (_vstart)
	ld de, #COLS
	add hl, de
	jr setstart

; scroll_down: the new top row is vstart - COLS
_scroll_down:
	ld hl, (_vstart)
	ld de, #COLS
	or a
	sbc hl, de
	push hl
	call blankrow
	pop hl
	jr setstart

; blankrow: HL = ring offset (masked here), blank COLS cells; preserves nothing
blankrow:
	ld a, h
	and #7
	ld h, a
	ld bc, #COLS
	jr clrcells

; setstart: HL = new vstart (masked), program CRTC registers 01h/02h
setstart:
	ld a, h
	and #7
	ld h, a
	ld (_vstart), hl
	ld a, #1
	out (0xF4), a
	ld a, l
	out (0xF5), a
	ld a, #2
	out (0xF4), a
	ld a, h
	out (0xF5), a
	ret

; fill: HL = start, BC = count (> 0), A = value. Destroys AF, BC, DE, HL
fill:
	ld (hl), a
	dec bc
	ld a, b
	or c
	ret z
	ld d, h
	ld e, l
	inc de
	ldir
	ret

; clear_across(y, x, l): args at SP+2 (y), SP+3 (x), SP+4..5 (l, signed)
_clear_across:
	ld hl, #2
	add hl, sp
	ld a, (hl)		; y
	inc hl
	ld c, (hl)		; x
	inc hl
	ld e, (hl)
	inc hl
	ld d, (hl)		; DE = l
	bit 7, d
	ret nz			; negative: nothing to do
	ld b, a
	ld a, d
	or e
	ret z
	ld a, b
	ld l, a
	ld h, #0
	push de			; count
	ld e, l
	ld d, h			; DE = y
	add hl, hl
	add hl, hl		; 4y
	add hl, de		; 5y
	add hl, hl
	add hl, hl
	add hl, hl
	add hl, hl		; 80y
	ld b, #0
	add hl, bc		; 80y + x
	ld bc, (_vstart)
	add hl, bc
	ld a, h
	and #7
	ld h, a			; ring offset
	pop bc			; BC = count
	jr clrcells

; clrcells: HL = ring offset (0..7FFh), BC = count. Blank both planes,
; wrapping at the end of the ring.
clrcells:
	ld a, b
	or c
	ret z
	push bc
	push hl
	ex de, hl
	ld hl, #0x800
	or a
	sbc hl, de		; HL = room to the end of the ring
	or a
	sbc hl, bc
	jr c, 1$
	pop hl
	pop bc
	jr clrseg
1$:	add hl, bc		; HL = room
	ld b, h
	ld c, l			; BC = first segment length
	pop hl			; offset
	pop de			; total count
	push de
	push bc
	call clrseg
	pop hl			; first length
	pop bc			; total
	ld a, c
	sub l
	ld c, a
	ld a, b
	sbc a, h
	ld b, a			; remaining count
	ld hl, #0

; clrseg: HL = ring offset, BC = count, no wrap. Blank both planes.
clrseg:
	push hl
	push bc
	ld de, #TEXT1
	add hl, de
	ld a, #0x80
	call fill
	pop bc
	pop hl
	ld de, #TEXT2
	add hl, de
	ld a, #0x8C
	jr fill

; vram_clear: blank all three planes (text1 80h, attribute white 07h, text2 8Ch)
_vram_clear:
	ld hl, #0
	call setstart
	ld hl, #TEXT1
	ld bc, #COLS * ROWS
	ld a, #0x80
	call fill
	ld hl, #TEXTA
	ld bc, #COLS * ROWS
	ld a, #0x07
	call fill
	ld hl, #TEXT2
	ld bc, #COLS * ROWS
	ld a, #0x8C
	jp fill

	.area _DATA
_vstart::
	.dw 0
