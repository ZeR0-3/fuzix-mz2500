;
;	Disk buffer cache in assembler (replaces the buffer part of devio.c):
;	bread, brelse, bawrite, bfree, zerobuf, tmpbuf, tmpfree, bufsync,
;	bfind, bdrop, freebuf.
;
;	struct blkbuf (kernel.h, no external data), 520 bytes:
;	  0..511 data, 512 bf_dev (2), 514 bf_blk (2), 516 bf_dirty,
;	  517 bf_busy, 518 bf_time (2)
;	Index displacements reach only +-127, so IX is kept at buffer + 512
;	(the tail of the structure) and the fields are 0..6 from there.
;
;	C callable (SDCC stack args, caller cleans up, result HL). IX is saved
;	and restored. Still in C: bdread, bdwrite, d_flush, panic, blkzero.
;
	.module bufcache

	.include "kernel.def"
	.include "../../cpu-z80/kernel-z80.def"

	.globl _bread
	.globl _brelse
	.globl _bawrite
	.globl _bfree
	.globl _zerobuf
	.globl _tmpbuf
	.globl _tmpfree
	.globl _bufsync
	.globl _bfind
	.globl _bdrop
	.globl _freebuf
	.globl _bufclock
	.globl _bufpool
	.globl _bdread
	.globl _bdwrite
	.globl _d_flush
	.globl _panic
	.globl _udata

BF_DEV		.equ 0
BF_BLK		.equ 2
BF_DIRTY	.equ 4
BF_BUSY		.equ 5
BF_TIME		.equ 6
BUFSZ		.equ 520
TAIL		.equ 512
EIO		.equ 5

	.area _COMMONMEM

; ixend: carry set while IX is still inside the pool. Destroys AF, HL
ixend:
	push ix
	pop hl
	ld a, l
	sub #<(_bufpool + TAIL + NBUFS * BUFSZ)
	ld a, h
	sbc a, #>(_bufpool + TAIL + NBUFS * BUFSZ)
	ret

; ixnext: IX += BUFSZ. Preserves BC, DE. Destroys HL
ixnext:
	push de
	ld de, #BUFSZ
	add ix, de
	pop de
	ret

; ixtohl: HL = buffer address of IX. Destroys DE
ixtohl:
	push ix
	pop hl
	ld de, #-TAIL
	add hl, de
	ret

; stamp: IX->bf_time = ++bufclock. Destroys HL
stamp:
	ld hl, (_bufclock)
	inc hl
	ld (_bufclock), hl
	ld BF_TIME (ix), l
	ld BF_TIME + 1 (ix), h
	ret

; bfind_r: DE = dev, BC = blk -> HL = locked buffer or 0. Preserves BC, DE.
; Destroys IX.
bfind_r:
	ld ix, #_bufpool + TAIL
1$:	call ixend
	jr nc, 5$
	ld a, BF_DEV (ix)
	cp e
	jr nz, 4$
	ld a, BF_DEV + 1 (ix)
	cp d
	jr nz, 4$
	ld a, BF_BLK (ix)
	cp c
	jr nz, 4$
	ld a, BF_BLK + 1 (ix)
	cp b
	jr z, 2$
4$:	call ixnext
	jr 1$
2$:	ld a, BF_BUSY (ix)
	or a
	jr z, 3$
	ld hl, #wantbusy
	push hl
	call _panic		; never returns
3$:	ld BF_BUSY (ix), #1
	push de
	call ixtohl
	pop de
	ret
5$:	ld hl, #0
	ret

_bfind:
	ld hl, #2
	add hl, sp
	ld e, (hl)
	inc hl
	ld d, (hl)
	inc hl
	ld c, (hl)
	inc hl
	ld b, (hl)
	push ix
	call bfind_r
	pop ix
	ret

; freebuf: oldest idle buffer, locked, written back if dirty -> HL
_freebuf:
	push ix
	ld ix, #_bufpool + TAIL
	ld de, #0		; best age so far
	ld bc, #0		; best buffer (IX value)
1$:	call ixend
	jr nc, 3$
	ld a, BF_BUSY (ix)
	cp #1
	jr z, 2$
	ld hl, (_bufclock)
	ld a, l
	sub BF_TIME (ix)
	ld l, a
	ld a, h
	sbc a, BF_TIME + 1 (ix)
	ld h, a			; HL = age
	push hl
	or a
	sbc hl, de
	pop hl
	jr c, 2$		; younger than the best so far
	ex de, hl
	push ix
	pop bc
2$:	call ixnext
	jr 1$
3$:	ld a, b
	or c
	jr nz, 4$
	ld hl, #nofree
	push hl
	call _panic		; never returns
4$:	push bc
	pop ix
	ld BF_BUSY (ix), #1
	ld a, BF_DIRTY (ix)
	or a
	jr z, 5$
	call ixtohl
	push hl
	call _bdwrite
	pop af
	ld BF_DIRTY (ix), #0
5$:	call ixtohl
	pop ix
	ret

; bfree_r: DE = buffer, C = dirty (0, 1, 2) -> HL = 0 or -1
bfree_r:
	push ix
	ld ix, #TAIL
	add ix, de
	ld b, #0		; error flag
	ld a, c
	or a
	jr z, 1$
	ld BF_DIRTY (ix), #1
1$:	ld a, c
	cp #2
	jr c, 3$
	push bc
	push de
	call _bdwrite
	pop af
	pop bc
	ld a, h
	cp #2
	jr nz, 2$
	ld a, l
	or a
	jr z, 4$
2$:	ld hl, #EIO
	ld (_udata + U_DATA__U_ERROR), hl
	ld b, #1
4$:	ld BF_DIRTY (ix), #0
3$:	call stamp
	ld BF_BUSY (ix), #0
	ld hl, #0
	ld a, b
	or a
	jr z, 5$
	dec hl
5$:	pop ix
	ret

_bfree:
	ld hl, #2
	add hl, sp
	ld e, (hl)
	inc hl
	ld d, (hl)
	inc hl
	ld c, (hl)
	jr bfree_r

_brelse:
_tmpfree:
	ld hl, #2
	add hl, sp
	ld e, (hl)
	inc hl
	ld d, (hl)
	ld c, #0
	jr bfree_r

_bawrite:
	ld hl, #2
	add hl, sp
	ld e, (hl)
	inc hl
	ld d, (hl)
	ld c, #1
	jr bfree_r

; tmpbuf: a free buffer that belongs to no device -> HL
_tmpbuf:
	call _freebuf
	push ix
	push hl
	ex de, hl
	ld ix, #TAIL
	add ix, de
	ld BF_DEV (ix), #0xFF
	ld BF_DEV + 1 (ix), #0xFF
	call stamp
	pop hl
	pop ix
	ret

_zerobuf:
	call _tmpbuf
	push hl
	ld (hl), #0
	ld d, h
	ld e, l
	inc de
	ld bc, #511
	ldir
	pop hl
	ret

_bread:
	ld hl, #2
	add hl, sp
	ld e, (hl)
	inc hl
	ld d, (hl)
	inc hl
	ld c, (hl)
	inc hl
	ld b, (hl)
	inc hl
	ld a, (hl)		; rewrite
	push af
	push de
	push bc
	push ix
	call bfind_r
	pop ix
	ld a, h
	or l
	jr nz, 9$		; cached: HL = buffer
	call _freebuf
	pop bc			; blk
	pop de			; dev
	pop af			; rewrite
	push ix			; caller's IX
	push hl			; [buffer, IX]
	push de
	ex de, hl
	ld ix, #TAIL
	add ix, de		; IX = buffer + 512
	pop de			; DE = dev
	ld BF_DEV (ix), e
	ld BF_DEV + 1 (ix), d
	ld BF_BLK (ix), c
	ld BF_BLK + 1 (ix), b
	or a
	jr nz, 8$		; rewrite: no read needed
	pop hl
	push hl
	push hl
	call _bdread
	pop af
	ld a, h
	cp #2
	jr nz, 6$
	ld a, l
	or a
	jr z, 8$
6$:	ld hl, #EIO
	ld (_udata + U_DATA__U_ERROR), hl
	ld BF_DEV (ix), #0xFF
	ld BF_DEV + 1 (ix), #0xFF
	ld BF_DIRTY (ix), #0
	ld BF_BUSY (ix), #0
	pop hl
	pop ix
	ld hl, #0
	ret
8$:	pop hl			; buffer
	pop ix
	ret
9$:	pop bc
	pop de
	pop af
	ret

; bdput_ix: IX = buffer. Write back when dirty and tell the driver.
bdput_ix:
	ld a, BF_DIRTY (ix)
	or a
	ret z
	call ixtohl
	push hl
	call _bdwrite
	pop af
	ld BF_DIRTY (ix), #0
	ld l, BF_DEV (ix)
	ld h, BF_DEV + 1 (ix)
	push hl
	call _d_flush
	pop af
	ret

_bufsync:
	push ix
	ld ix, #_bufpool + TAIL
1$:	call ixend
	jr nc, 3$
	ld a, BF_DEV (ix)
	and BF_DEV + 1 (ix)
	cp #0xFF
	jr z, 2$		; NO_DEVICE
	call bdput_ix
2$:	call ixnext
	jr 1$
3$:	pop ix
	ret

_bdrop:
	ld hl, #2
	add hl, sp
	ld e, (hl)
	inc hl
	ld d, (hl)
	push ix
	ld ix, #_bufpool + TAIL
1$:	call ixend
	jr nc, 3$
	ld a, BF_DEV (ix)
	cp e
	jr nz, 2$
	ld a, BF_DEV + 1 (ix)
	cp d
	jr nz, 2$
	push de
	call bdput_ix
	pop de
	ld BF_DEV (ix), #0xFF
	ld BF_DEV + 1 (ix), #0xFF
2$:	call ixnext
	jr 1$
3$:	pop ix
	ret

	.area _CONST
wantbusy:
	.asciz "want busy block"
nofree:
	.asciz "no free buffers"

	.area _DATA
_bufclock:
	.dw 0
