; blkno_t bmap(inoptr ip, blkno_t bn, unsigned rwflg)   (512 byte blocks)
; Hand written replacement for blk512.c bmap(). Locals live on the stack
; (bread can sleep, so bmap must stay re-entrant).
;	ip 4(ix), bn 6(ix), rwflg 8(ix)
;	-2 nb, -3 sh, -4 j, -6 bp, -8 i
	.module bmap
	.globl _bmap, _getmode, _blk_alloc, _bread, _brelse, _bawrite, _corrupt_fs

	.area _CODE

_bmap::
	push ix
	ld ix, #0
	add ix, sp
	ld hl, #-8
	add hl, sp
	ld sp, hl
	ld l, 4 (ix)
	ld h, 5 (ix)
	push hl
	call _getmode
	pop af
	ld a, l
	cp #0x60		; MODE_R(F_BDEV)
	jr nz, notbdev
	ld l, 6 (ix)
	ld h, 7 (ix)
	jp done
notbdev:
	ld a, 6 (ix)
	sub #18
	ld a, 7 (ix)
	sbc a, #0
	jr nc, indirect
	; direct block
	ld l, 6 (ix)
	ld h, 7 (ix)
	add hl, hl
	ld e, 4 (ix)
	ld d, 5 (ix)
	add hl, de
	ld de, #30		; &c_node.i_addr[0]
	add hl, de
	ld c, (hl)
	inc hl
	ld b, (hl)
	dec hl
	ld a, b
	or c
	jr nz, retbc
	ld a, 8 (ix)
	or 9 (ix)
	jp nz, retnull
	push hl
	call pushdev
	call _blk_alloc
	pop af
	ld c, l
	ld b, h
	pop hl
	ld a, b
	or c
	jp z, retnull
	ld (hl), c
	inc hl
	ld (hl), b
	call setdirty
retbc:
	ld l, c
	ld h, b
	jp done

indirect:
	ld l, 6 (ix)
	ld h, 7 (ix)
	ld de, #-18
	add hl, de
	xor a
	ld -3 (ix), a		; sh = 0
	ld -4 (ix), #2		; j = 2
	ld a, h
	or a
	jr z, 1$
	ld -3 (ix), #8		; double indirect
	dec h			; bn -= 256
	ld -4 (ix), #1
1$:	ld 6 (ix), l
	ld 7 (ix), h
	ld a, -4 (ix)
	add a, a
	ld e, a
	ld a, #70		; 30 + 2 * (20 - j)
	sub e
	ld e, a
	ld d, #0
	ld l, 4 (ix)
	ld h, 5 (ix)
	add hl, de
	ld c, (hl)
	inc hl
	ld b, (hl)
	dec hl
	ld a, b
	or c
	jr nz, haveb
	ld a, 8 (ix)
	or 9 (ix)
	jp nz, retnull
	push hl
	call pushdev
	call _blk_alloc
	pop af
	ld c, l
	ld b, h
	pop hl
	ld a, b
	or c
	jp z, retnull
	ld (hl), c
	inc hl
	ld (hl), b
	call setdirty
haveb:
	ld -2 (ix), c
	ld -1 (ix), b
loop:
	ld a, -4 (ix)
	cp #3
	jp nc, ret_nb
	xor a
	push af
	inc sp
	ld l, -2 (ix)
	ld h, -1 (ix)
	push hl
	call pushdev
	call _bread
	pop af
	pop af
	inc sp
	ld a, h
	or l
	jr nz, 2$
	call pushdev
	call _corrupt_fs
	pop af
	ld hl, #0
	jp done
2$:	ld -6 (ix), l
	ld -5 (ix), h
	ld l, 6 (ix)		; i = (bn >> sh) & 0xff
	ld a, -3 (ix)
	or a
	jr z, 4$
	ld l, 7 (ix)
4$:	ld h, #0
	ld -8 (ix), l
	add hl, hl
	ld e, -6 (ix)
	ld d, -5 (ix)
	add hl, de		; &bp->data[2 * i]
	ld c, (hl)
	inc hl
	ld b, (hl)
	ld -2 (ix), c
	ld -1 (ix), b
	ld a, b
	or c
	jr z, 5$
	call brelsebp
	jr 7$
5$:	ld a, 8 (ix)
	or 9 (ix)
	jr nz, 6$
	call pushdev
	call _blk_alloc
	pop af
	ld a, h
	or l
	jr z, 6$
	ld -2 (ix), l
	ld -1 (ix), h
	ld l, -8 (ix)
	ld h, #0
	add hl, hl
	ld e, -6 (ix)
	ld d, -5 (ix)
	add hl, de
	ld a, -2 (ix)
	ld (hl), a
	inc hl
	ld a, -1 (ix)
	ld (hl), a
	ld l, -6 (ix)
	ld h, -5 (ix)
	push hl
	call _bawrite
	pop af
	jr 7$
6$:	call brelsebp
	jr retnull
7$:	ld a, -3 (ix)
	sub #8
	ld -3 (ix), a
	inc -4 (ix)
	jp loop
ret_nb:
	ld l, -2 (ix)
	ld h, -1 (ix)
	jr done
retnull:
	ld hl, #0xffff		; NULLBLK
done:
	ld sp, ix
	pop ix
	ret

pushdev:			; pushes ip->c_dev below our return address
	pop bc			; return address
	ld l, 4 (ix)
	ld h, 5 (ix)
	inc hl
	inc hl
	ld e, (hl)
	inc hl
	ld d, (hl)
	push de
	push bc
	ret

brelsebp:
	ld l, -6 (ix)
	ld h, -5 (ix)
	push hl
	call _brelse
	pop af
	ret

setdirty:
	ld l, 4 (ix)
	ld h, 5 (ix)
	ld de, #73		; c_flags
	add hl, de
	set 7, (hl)		; CDIRTY
	ret
