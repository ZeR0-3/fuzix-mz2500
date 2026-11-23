;
;	MZ-1R37 EMM driver (640KB, 2560 blocks of 256 bytes)
;
;	Hardware (from the emulator / MZ-2500 docs):
;	  OUT (ACh): bus A15-8 = B ... address bits 19-16 in B, data = bits 15-8
;	  IN/OUT (ADh): B = address bits 7-0, data in A (no auto increment)
;	A block number is therefore simply D=bits 19-16, E=bits 15-8.
;
;	Interface (registers only, all asm):
;	  emm_rd256   DE = block, HL = destination   (destroys AF, BC, HL)
;	  emm_wr256   DE = block, HL = source        (destroys AF, BC, HL; HL = src - 1 on return)
;	  emm_init    detect, sets _emm_blocks (0 = absent)
;
	.module emm

	.globl _emm_blocks
	.globl _emm_chk
	.globl emm_init
	.globl emm_rd256
	.globl emm_wr256
	.globl _emm_cache_init
	.globl _emm_cache_get
	.globl _emm_cache_put
	.globl _emm_cache_on
	.globl outchar

EMM_HI		.equ 0xAC
EMM_DAT		.equ 0xAD
EMM_BLOCKS	.equ 2560

TB_SAVE		.equ 0xC000	; scratch buffers inside window 6 (dummy page)
TB_READ		.equ 0xC100
TB_PAT		.equ 0xC200

	.area _COMMONMEM

emm_rd256:
	ld a, e
	ld c, #EMM_HI
	ld b, d
	out (c), a
	ld c, #EMM_DAT
	ld b, #0
1$:in a, (c)
	ld (hl), a
	inc hl
	inc b
	in a, (c)
	ld (hl), a
	inc hl
	inc b
	in a, (c)
	ld (hl), a
	inc hl
	inc b
	in a, (c)
	ld (hl), a
	inc hl
	inc b
	jr nz, 1$
	ret

; OTDR decrements B before putting it on the address bus: starting at
; B=0 the addresses are FFh, FEh ... 00h, so walk the source downwards.
emm_wr256:
	ld a, e
	ld c, #EMM_HI
	ld b, d
	out (c), a
	ld c, #EMM_DAT
	ld b, #0
	inc h
	dec hl			; HL = source + 255
	otdr
	ret

;
;	Write/read-back test of one block, contents preserved.
;	DE = block. Returns Z if the block holds data. Needs the scratch
;	buffers mapped. Destroys everything but DE.
;
emm_test:
	push de
	ld hl, #TB_SAVE
	call emm_rd256
	pop de
	push de
	; pattern: i ^ 5Ah, i from 0..255
	ld hl, #TB_PAT
	ld b, #0
1$:	ld a, b
	xor #0x5A
	ld (hl), a
	inc hl
	inc b
	jr nz, 1$
	ld hl, #TB_PAT
	call emm_wr256
	pop de
	push de
	ld hl, #TB_READ
	call emm_rd256
	; compare read-back with the pattern
	ld hl, #TB_PAT
	ld de, #TB_READ
	ld b, #0
2$:	ld a, (de)
	cp (hl)
	jr nz, 3$
	inc hl
	inc de
	djnz 2$
3$:	push af			; Z = identical
	pop bc			; save flags in C
	pop de
	push de
	push bc
	ld hl, #TB_SAVE
	call emm_wr256		; restore the original contents
	pop bc
	pop de
	push bc
	pop af			; flags back
	ret

emm_init:
	ld hl, #0
	ld (_emm_blocks), hl
	ld (_emm_chk), hl
	ld a, #6
	out (0xB4), a
	ld a, #0x0E		; dummy page in window 6 as scratch
	out (0xB5), a
	ld de, #EMM_BLOCKS - 1	; last block must hold data
	call emm_test
	jr nz, 4$
	ld a, #1
	ld (_emm_chk), a
	ld de, #EMM_BLOCKS	; one past the end must not
	call emm_test
	jr z, 5$
	ld hl, #EMM_BLOCKS
	ld (_emm_blocks), hl
	ld a, #1
	ld (_emm_chk + 1), a
	jr 4$
5$:	; wraps around (or larger): treat as 640KB only when bit-exact
	; size is unknown; leave _emm_blocks = 0 for now
4$:	ld a, #6
	out (0xB4), a
	ld a, #0x38
	out (0xB5), a		; text VRAM back in window 6
	ret

;
;	Second-level block cache for the disk (512 byte filesystem blocks).
;	Direct mapped by the low 10 bits of the block number: 1024 slots.
;	EMM layout: blocks 0-7 = tags (2 bytes per slot, value = fs block + 1,
;	0 = empty), blocks 8.. = slot data (2 EMM blocks per slot). 514KB total.
;	Only used when emm_init found the memory.
;
;	C callable (SDCC stack args):
;	  void emm_cache_init(void)
;	  int  emm_cache_get(uint16_t blk, uint8_t *buf)   1 = hit, buf filled
;	  void emm_cache_put(uint16_t blk, uint8_t *buf)
;
; tagsel: DE = fs block. Selects the tag block in the EMM and leaves
; C = ADh, B = byte offset of the slot's tag. Destroys AF, HL
tagsel:
	ld a, d
	and #3
	ld h, a
	ld l, e			; HL = slot index (0..1023)
	ld a, l
	rlca
	and #1
	ld c, a
	ld a, h
	add a, a
	or c			; A = tag block (slot / 128)
	ld c, #EMM_HI
	ld b, #0
	out (c), a
	ld a, l
	add a, a
	ld b, a			; offset = (slot & 7Fh) * 2
	ld c, #EMM_DAT
	ret

; tagrd: DE = fs block -> HL = tag. Destroys AF, BC
tagrd:
	call tagsel
	in a, (c)
	ld l, a
	inc b
	in a, (c)
	ld h, a
	ret

; tagwr: DE = fs block, HL = tag value. Destroys AF, BC, HL
tagwr:
	push hl
	call tagsel
	pop hl
	ld a, l
	out (c), a
	inc b
	ld a, h
	out (c), a
	ret

; dataaddr: DE = fs block -> DE = first EMM block of its slot
dataaddr:
	ld a, d
	and #3
	ld d, a
	sla e
	rl d
	ld hl, #8
	add hl, de
	ex de, hl
	ret

_emm_cache_init:
	xor a
	ld (_emm_cache_on), a
	ld hl, (_emm_blocks)
	ld a, h
	or l
	ret z			; no EMM
	ld e, #0		; clear the 8 tag blocks
1$:	ld a, e
	ld c, #EMM_HI
	ld b, #0
	out (c), a
	ld c, #EMM_DAT
	xor a
2$:	out (c), a
	inc b
	jr nz, 2$
	inc e
	ld a, e
	cp #8
	jr nz, 1$
	ld a, #1
	ld (_emm_cache_on), a
	ret

_emm_cache_get:
	ld a, (_emm_cache_on)
	or a
	jr z, miss
	ld hl, #2
	add hl, sp
	ld e, (hl)
	inc hl
	ld d, (hl)		; DE = block
	inc hl
	ld c, (hl)
	inc hl
	ld b, (hl)		; BC = buffer
	push bc
	push de
	call tagrd		; HL = tag
	pop de
	push de
	inc de
	or a
	sbc hl, de		; tag == block + 1 ?
	pop de
	jr nz, miss1
	call dataaddr
	pop hl			; buffer
	call emm_rd256
	inc de
	call emm_rd256
	ld hl, #1
	ret
miss1:	pop bc
miss:	ld hl, #0
	ret

_emm_cache_put:
	ld a, (_emm_cache_on)
	or a
	ret z
	ld hl, #2
	add hl, sp
	ld e, (hl)
	inc hl
	ld d, (hl)		; DE = block
	inc hl
	ld c, (hl)
	inc hl
	ld b, (hl)		; BC = buffer
	push de			; block
	call dataaddr
	ld h, b
	ld l, c
	call emm_wr256
	inc de
	ld bc, #257		; otdr leaves HL = src - 1
	add hl, bc		; HL = src + 256
	call emm_wr256
	pop de			; block
	ld h, d
	ld l, e
	inc hl			; tag = block + 1
	jp tagwr

	.area _DATA
_emm_cache_on:
	.db 0

	.area _DATA
_emm_blocks:
	.dw 0
_emm_chk:
	.dw 0
