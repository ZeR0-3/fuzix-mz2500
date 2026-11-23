;
;	User memory access for the MZ-2500 (replaces cpu-z80/usermem_std-z80.s)
;
;	The kernel lives in windows 0-5 (+ VRAM in 6, common in 7) while a user
;	process owns windows 0-6, so the kernel can never see user memory
;	through the normal map. The generic code therefore switched the whole
;	map twice for every byte (about 1000 cycles per byte).
;
;	Here the kernel stays mapped. A user address is reached by pointing
;	window 6 (C000h-DFFFh) at the user's page for that 8KB window; the copy
;	is a plain ldir, in chunks of at most 256 bytes that never cross an 8KB
;	window. Window 6 holds text VRAM for the kernel (page 38h), so
;	interrupts are off while it is redirected and it is restored right after
;	each chunk. User addresses at E000h and above are the common window and
;	are visible directly.
;
;	C interface (SDCC, args on the stack, caller cleans up):
;	  int  _uget(const void *user, void *kernel, usize_t count)
;	  int  _uput(const void *kernel, void *user, usize_t count)
;	  int  _uzero(void *user, usize_t count)
;	  int  _ugetc(const void *user)          (HL = address, result L)
;	  int  _ugetw(const void *user)          (HL = address, result HL)
;	  void _uputc(int c, void *user)
;	  void _uputw(int w, void *user)
;
	.module umem

	.include "kernel.def"
	.include "../../cpu-z80/kernel-z80.def"

	.globl __uget
	.globl __ugetc
	.globl __ugetw
	.globl __uput
	.globl __uputc
	.globl __uputw
	.globl __uzero
	.globl _pmap
	.globl _udata
	.globl _int_disabled

	.area _COMMONMEM

; umap: DE = user address (< E000h). Interrupts off, window 6 -> user page.
; Returns HL = address inside window 6. Destroys AF, BC.
umap:
	di
	ld a, (_udata + U_DATA__U_PAGE)
	ld l, a
	ld h, #0
	add hl, hl
	add hl, hl
	add hl, hl
	ld bc, #_pmap
	add hl, bc
	ld a, d
	rlca
	rlca
	rlca
	and #7
	add a, l
	ld l, a
	jr nc, 1$
	inc h
1$:	ld a, #6
	out (0xB4), a
	ld a, (hl)
	out (0xB5), a
	ld a, d
	and #0x1F
	or #0xC0
	ld h, a
	ld l, e
	ret

; uunmap: window 6 back to text VRAM, interrupts back on if the kernel had
; them on. Destroys AF
uunmap:
	ld a, #6
	out (0xB4), a
	ld a, #0x38
	out (0xB5), a
	ld a, (_int_disabled)
	or a
	ret nz
	ei
	ret

__ugetc:
	ld a, h
	cp #0xE0
	jr nc, 1$
	ex de, hl
	call umap
	ld l, (hl)
	call uunmap
	ld h, #0
	ret
1$:	ld l, (hl)
	ld h, #0
	ret

__ugetw:
	push hl
	call __ugetc
	ld a, l
	pop hl
	inc hl
	push af
	call __ugetc
	ld h, l
	pop af
	ld l, a
	ret

__uputc:
	ld hl, #2
	add hl, sp
	ld c, (hl)		; low byte of the value
	inc hl
	inc hl
	ld e, (hl)
	inc hl
	ld d, (hl)		; DE = user address
	jr putbyte

__uputw:
	ld hl, #2
	add hl, sp
	ld c, (hl)
	inc hl
	ld b, (hl)		; BC = word
	inc hl
	ld e, (hl)
	inc hl
	ld d, (hl)		; DE = user address
	push bc
	push de
	call putbyte
	pop de
	pop bc
	inc de
	ld c, b
; putbyte: DE = user address, C = value
putbyte:
	ld a, d
	cp #0xE0
	jr nc, 1$
	push bc
	call umap
	pop bc
	ld (hl), c
	jp uunmap
1$:	ex de, hl
	ld (hl), c
	ret

; ---------------------------------------------------------------------------
; copy: _uget (A=0) and _uput (A=1)
;   arg1 = source, arg2 = destination, count; all advanced in place
; ---------------------------------------------------------------------------
__uget:
	xor a
	jr ucopy
__uput:
	ld a, #1
ucopy:
	push ix
	push af
	ld ix, #0
	add ix, sp		; ix+1 = direction, +4 ret, +6 arg1, +8 arg2, +10 count
nextchunk:
	ld l, 10 (ix)
	ld h, 11 (ix)
	ld a, h
	or l
	jp z, done
	bit 0, 1 (ix)
	jr nz, 1$
	ld e, 6 (ix)		; get: user pointer is the source
	ld d, 7 (ix)
	jr 2$
1$:	ld e, 8 (ix)		; put: user pointer is the destination
	ld d, 9 (ix)
2$:	ld a, d
	cp #0xE0
	jp nc, direct
	; chunk = min(count, 256, 2000h - (user & 1FFFh))
	and #0x1F
	ld b, a
	ld c, e
	push hl			; count
	ld hl, #0x2000
	or a
	sbc hl, bc
	ld b, h
	ld c, l			; BC = room in this window
	pop hl
	ld a, b
	or a
	jr z, 3$
	ld bc, #0x0100
3$:	push hl
	or a
	sbc hl, bc
	pop hl
	jr nc, 4$
	ld b, h
	ld c, l			; count < chunk: take the rest
4$:	push bc			; remember the chunk length
	call umap		; HL = window pointer
	bit 0, 1 (ix)
	jr nz, 5$
	ld e, 8 (ix)		; get: source = window, destination = arg2
	ld d, 9 (ix)
	jr 6$
5$:	ex de, hl		; put: source = arg1, destination = window
	ld l, 6 (ix)
	ld h, 7 (ix)
6$:	pop bc
	push bc
	ldir
	call uunmap
	pop bc
	jp advance
direct:
	; common window: visible directly, still copy at most 256 per pass
	ld a, h
	or a
	jr z, 7$
	ld hl, #0x0100
7$:	ld b, h
	ld c, l			; BC = min(count, 256)
	push bc
	ld l, 6 (ix)
	ld h, 7 (ix)
	ld e, 8 (ix)
	ld d, 9 (ix)
	ldir
	pop bc
advance:
	ld l, 6 (ix)
	ld h, 7 (ix)
	add hl, bc
	ld 6 (ix), l
	ld 7 (ix), h
	ld l, 8 (ix)
	ld h, 9 (ix)
	add hl, bc
	ld 8 (ix), l
	ld 9 (ix), h
	ld l, 10 (ix)
	ld h, 11 (ix)
	or a
	sbc hl, bc
	ld 10 (ix), l
	ld 11 (ix), h
	jp nextchunk
done:
	pop af
	pop ix
	ld hl, #0
	ret

; ---------------------------------------------------------------------------
; _uzero(user, count)
; ---------------------------------------------------------------------------
__uzero:
	push ix
	ld ix, #0
	add ix, sp		; +2 ret, +4 user, +6 count
zloop:
	ld l, 6 (ix)
	ld h, 7 (ix)
	ld a, h
	or l
	jr z, zdone
	ld e, 4 (ix)
	ld d, 5 (ix)
	ld a, d
	cp #0xE0
	jr nc, zdirect
	and #0x1F
	ld b, a
	ld c, e
	push hl
	ld hl, #0x2000
	or a
	sbc hl, bc
	ld b, h
	ld c, l
	pop hl
	ld a, b
	or a
	jr z, 1$
	ld bc, #0x0100
1$:	push hl
	or a
	sbc hl, bc
	pop hl
	jr nc, 2$
	ld b, h
	ld c, l
2$:	push bc
	call umap
	pop bc
	push bc
	jr zfill
zdirect:
	ld a, h
	or a
	jr z, 3$
	ld hl, #0x0100
3$:	ld b, h
	ld c, l
	push bc
	ex de, hl
	call zfill2
	jr zadv
zfill:
	call zfill2
	call uunmap
zadv:
	pop bc
	ld l, 4 (ix)
	ld h, 5 (ix)
	add hl, bc
	ld 4 (ix), l
	ld 5 (ix), h
	ld l, 6 (ix)
	ld h, 7 (ix)
	or a
	sbc hl, bc
	ld 6 (ix), l
	ld 7 (ix), h
	jr zloop
zdone:
	pop ix
	ld hl, #0
	ret

; zfill2: HL = destination, BC = count (>0): store zero
zfill2:
	ld (hl), #0
	dec bc
	ld a, b
	or c
	ret z
	ld d, h
	ld e, l
	inc de
	ldir
	ret
