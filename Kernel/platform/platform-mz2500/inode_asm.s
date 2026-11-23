; Hand written replacements for the small helpers of inode.c (uoff, umove, mapcalc).
; SDCC convention: arguments on the stack (right to left, caller pops), result in HL,
; IX preserved, everything else may be destroyed.
	.module inode_asm
	.globl _udata, _bmap
	.globl _uoff, _umove, _mapcalc

U_BASE	.equ 0x62		; udata offsets (see kernel.def)
U_COUNT	.equ 0x64
U_OFFSET .equ 0x66
U_DONE	.equ 0x99

	.area _CODE

; uint16_t uoff(void): u_offset & 511
_uoff::
	ld hl, (_udata + U_OFFSET)
	ld a, h
	and #1
	ld h, a
	ret

; uint16_t umove(uint16_t n): advance offset, base and done by n, drop count; returns u_done
_umove::
	call	ixh_sp2_cb
	ld hl, (_udata + U_OFFSET)
	add hl, bc
	ld (_udata + U_OFFSET), hl
	jr nc, 1$
	ld hl, (_udata + U_OFFSET + 2)
	inc hl
	ld (_udata + U_OFFSET + 2), hl
1$:	ld hl, (_udata + U_COUNT)
	or a
	sbc hl, bc
	ld (_udata + U_COUNT), hl
	ld hl, (_udata + U_BASE)
	add hl, bc
	ld (_udata + U_BASE), hl
	ld hl, (_udata + U_DONE)
	add hl, bc
	ld (_udata + U_DONE), hl
	ret

; blkno_t mapcalc(inoptr ino, usize_t *size, uint_fast8_t m)
; *size = min(u_count, 512 - (u_offset & 511)); returns bmap(ino, u_offset >> 9, m)
_mapcalc::
	ld a, (_udata + U_OFFSET + 1)
	and #1
	ld d, a
	ld a, (_udata + U_OFFSET)
	ld e, a			; DE = offset within the block
	ld hl, #512
	or a
	sbc hl, de		; HL = room left in the block
	ld de, (_udata + U_COUNT)
	push hl
	or a
	sbc hl, de
	pop hl
	jr c, 1$		; room < count: use room
	ex de, hl		; else count
1$:	ex de, hl		; DE = amount
	call	ixh_sp4_cb
	ld a, e
	ld (bc), a
	inc bc
	ld a, d
	ld (bc), a
	ld a, (_udata + U_OFFSET + 3)	; block = u_offset >> 9 (low 16 bits)
	rra
	ld a, (_udata + U_OFFSET + 2)
	rra
	ld h, a
	ld a, (_udata + U_OFFSET + 1)
	rra
	ld l, a
	ex de, hl		; DE = block
	ld hl, #6
	add hl, sp
	ld c, (hl)
	ld b, #0		; BC = m
	ld hl, #2
	add hl, sp
	ld a, (hl)
	inc hl
	ld h, (hl)
	ld l, a			; HL = ino
	push bc
	push de
	push hl
	call _bmap
	pop af
	pop af
	pop af
	ret

; ---------------------------------------------------------------------------------
; void readi(inoptr ino, uint_fast8_t flag), void writei(inoptr ino, uint_fast8_t flag)
; Frame (IX): 4(ix) ino, 6(ix) flag | -2 dev, -4 amount, -5 ispipe, -6 write flag (1/2),
; -8 pblk, later the buffer pointer.
	.globl _readi, _writei, _getmode, _wait_pipe_read, _wait_pipe_write
	.globl _zerobuf, _bread, _brelse, _bfree, _uputblk, _ugetblk
	.globl _wakeup, _ssig, _cdread, _cdwrite, ___sdcc_enter_ix

U_ERROR	.equ 0x0c

; common entry: allocate the frame, ispipe = 0, u_done = 0, dev = ino->c_dev,
; returns A = getmode(ino)
rw_enter:
	xor a
	ld -5 (ix), a
	ld h, a
	ld l, a
	ld (_udata + U_DONE), hl
	call	ixh_lh_p4
	push hl
	inc hl
	inc hl
	ld a, (hl)
	ld -2 (ix), a
	inc hl
	ld a, (hl)
	ld -1 (ix), a
	call _getmode
	pop af
	ld a, l
	ret

addr0:				; BC = ino->c_node.i_addr[0]
	call	ixh_lh_p4
	ld de, #0x1e
	add hl, de
	ld c, (hl)
	inc hl
	ld b, (hl)
	ret

rw_epilogue:
	jp	ixh_leave

enodev:
	ld hl, #0x13		; ENODEV
	ld (_udata + U_ERROR), hl
	jp rw_epilogue

fixdone:			; no data and an error: return -1
	ld hl, (_udata + U_DONE)
	ld a, h
	or l
	jp nz, rw_epilogue
	ld hl, (_udata + U_ERROR)
	ld a, h
	or l
	jp z, rw_epilogue
	ld hl, #0xffff
	ld (_udata + U_DONE), hl
	jp rw_epilogue

pipewrap:			; pipe offsets wrap at 18 blocks
	ld a, (_udata + U_OFFSET + 1)
	cp #0x24
	ret c
	ld hl, #0
	ld (_udata + U_OFFSET), hl
	ld (_udata + U_OFFSET + 2), hl
	ret

_readi::
	call ___sdcc_enter_ix
	ld hl, #-8
	add hl, sp
	ld sp, hl
	call rw_enter
	cp #0x10
	jp z, rpipe
	cp #0xC0
	jp z, rpipe
	cp #0x40
	jp z, rfile
	cp #0x80
	jp z, rfile
	cp #0x60
	jp z, rbdev
	cp #0x20
	jp nz, enodev
	call addr0		; character device
	ld a, 6 (ix)
	push af
	inc sp
	push bc
	call _cdread
	pop af
	inc sp
	ld (_udata + U_DONE), hl
	jp rw_epilogue
rbdev:	call addr0
	ld -2 (ix), c
	ld -1 (ix), b
	jp rloop
rpipe:	ld -5 (ix), #1
	ld a, 6 (ix)
	push af
	inc sp
	call	ixh_lh_p4
	push hl
	call _wait_pipe_read
	pop af
	inc sp
	ld a, l
	or a
	jp z, rw_epilogue
	jp rloop
rfile:				; limit the count to what is left in the file
	call	ixh_lh_p4
	ld de, #0x0e
	add hl, de
	ld e, (hl)
	inc hl
	ld d, (hl)
	inc hl
	ld c, (hl)
	inc hl
	ld b, (hl)		; BC:DE = size
	ld hl, (_udata + U_OFFSET)
	ex de, hl		; DE = offset low, HL = size low
	or a
	sbc hl, de
	push hl
	ld hl, (_udata + U_OFFSET + 2)
	ex de, hl
	ld h, b
	ld l, c
	sbc hl, de		; size - offset, high word
	pop de			; DE = low word
	jp c, rzero		; offset beyond the end
	ld a, h
	or l
	jp nz, rloop		; more than 64K left
	ld a, d
	or e
	jp z, rzero		; size == offset
	ld hl, (_udata + U_COUNT)
	or a
	sbc hl, de
	jp c, rloop		; count < left: keep
	ld (_udata + U_COUNT), de
	jp rloop
rzero:	ld hl, #0
	ld (_udata + U_COUNT), hl
rloop:	ld hl, (_udata + U_COUNT)
	ld a, h
	or l
	jp z, fixdone
	ld bc, #1
	push bc
	push ix
	pop hl
	ld de, #-4
	add hl, de
	push hl			; &amount
	call	ixh_lh_p4
	push hl
	call _mapcalc
	pop af
	pop af
	pop af
	ld a, h
	and l
	inc a
	jp nz, 1$
	call _zerobuf		; hole in the file: a block of zeros
	jr 2$
1$:	xor a
	push af
	inc sp
	push hl
	call	ixh_lh_m2
	push hl
	call _bread
	pop af
	pop af
	inc sp
2$:	ld a, h
	or l
	jp z, fixdone
	ld -8 (ix), l
	ld -7 (ix), h
	call _uoff
	call	ixh_cb_m4
	push bc
	push hl
	call	ixh_lh_m8
	push hl
	call _uputblk
	pop af
	pop af
	pop af
	call	ixh_lh_m8
	call	ixh_p1_brelse
	call	ixh_lh_m4
	push hl
	call _umove
	pop af
	ld a, -5 (ix)
	or a
	jp z, rloop
	call pipewrap
	call	ixh_lh_p4
	ld de, #0x0e
	add hl, de
	call	ixh_ed_m4
	ld a, (hl)
	sub e
	ld (hl), a
	inc hl
	ld a, (hl)
	sbc a, d
	ld (hl), a
	inc hl
	ld a, (hl)
	sbc a, #0
	ld (hl), a
	inc hl
	ld a, (hl)
	sbc a, #0
	ld (hl), a
	call	ixh_lh_p4
	call	ixh_p1_wakeup
	jp rloop

_writei::
	call ___sdcc_enter_ix
	ld hl, #-8
	add hl, sp
	ld sp, hl
	call rw_enter
	cp #0x10
	jp z, wpipe
	cp #0x20
	jp z, wcdev
	cp #0x40
	jp z, wloop0
	cp #0x80
	jp z, wloop0
	cp #0x60
	jp nz, enodev
	call addr0		; block device
	ld -2 (ix), c
	ld -1 (ix), b
	jp wloop0
wcdev:	call addr0
	ld a, 6 (ix)
	push af
	inc sp
	push bc
	call _cdwrite
	pop af
	inc sp
	ld (_udata + U_DONE), hl
	jp rw_epilogue
wpipe:	ld -5 (ix), #1
wloop0:	ld a, 6 (ix)		; O_SYNC (8) -> flag 2, else 1
	and #8
	ld a, #1
	jp z, 1$
	inc a
1$:	ld -6 (ix), a
wloop:	ld hl, (_udata + U_COUNT)
	ld a, h
	or l
	jp z, wfin
	ld a, -5 (ix)
	or a
	jp z, 2$
	ld a, -6 (ix)
	push af
	inc sp
	call	ixh_lh_p4
	push hl
	call _wait_pipe_write
	pop af
	inc sp
	ld a, l
	or a
	jp nz, rw_epilogue
2$:	ld bc, #0
	push bc
	push ix
	pop hl
	ld de, #-4
	add hl, de
	push hl			; &amount
	call	ixh_lh_p4
	push hl
	call _mapcalc
	pop af
	pop af
	pop af
	ld -8 (ix), l
	ld -7 (ix), h
	ld a, (_udata + U_OFFSET + 3)
	and #0xfe
	jp z, 3$
	ld hl, #0x1b		; EFBIG
	ld (_udata + U_ERROR), hl
	ld hl, (_udata)		; u_ptab
	ld a, #0x19		; SIGXFSZ
	push af
	inc sp
	push hl
	call _ssig
	pop af
	inc sp
	jp wfin
3$:	ld a, -8 (ix)
	and -7 (ix)
	inc a
	jp z, wfin		; no space for a new block
	ld a, -4 (ix)		; reading the old contents is pointless for a whole block
	or a
	jp nz, 4$
	ld a, -3 (ix)
	cp #2
	ld a, #1
	jp z, 5$
4$:	xor a
5$:	push af
	inc sp
	call	ixh_lh_m8
	push hl
	call	ixh_lh_m2
	push hl
	call _bread
	pop af
	pop af
	inc sp
	ld a, h
	or l
	jp z, wfin
	ld -8 (ix), l
	ld -7 (ix), h
	call _uoff
	call	ixh_cb_m4
	push bc
	push hl
	call	ixh_lh_m8
	push hl
	call _ugetblk
	pop af
	pop af
	pop af
	ld a, -6 (ix)
	push af
	inc sp
	call	ixh_lh_m8
	push hl
	call _bfree
	pop af
	inc sp
	ld a, h
	or l
	jp nz, wfin
	call	ixh_lh_m4
	push hl
	call _umove
	pop af
	ld a, -5 (ix)
	or a
	jp z, wloop
	call pipewrap
	call	ixh_lh_p4
	ld de, #0x0e
	add hl, de
	call	ixh_ed_m4
	ld a, (hl)
	add a, e
	ld (hl), a
	inc hl
	ld a, (hl)
	adc a, d
	ld (hl), a
	inc hl
	ld a, (hl)
	adc a, #0
	ld (hl), a
	inc hl
	ld a, (hl)
	adc a, #0
	ld (hl), a
	call	ixh_lh_p4
	call	ixh_p1_wakeup
	jp wloop
wfin:	ld a, -5 (ix)
	or a
	jp nz, fixdone
	call	ixh_lh_p4
	ld de, #0x0e
	add hl, de
	ex de, hl		; DE = &size
	ld hl, #_udata + U_OFFSET
	ld a, (de)
	sub (hl)
	inc de
	inc hl
	ld a, (de)
	sbc a, (hl)
	inc de
	inc hl
	ld a, (de)
	sbc a, (hl)
	inc de
	inc hl
	ld a, (de)
	sbc a, (hl)
	jp nc, fixdone		; size >= offset
	call	ixh_lh_p4
	ld de, #0x0e
	add hl, de
	ex de, hl
	ld hl, #_udata + U_OFFSET
	ld bc, #4
	ldir
	call	ixh_lh_p4
	ld de, #0x49
	add hl, de
	set 7, (hl)		; CDIRTY
	jp fixdone

; ---- rwsetup(bool is_read, uint_fast8_t *flag) -> inoptr ----
	.globl _rwsetup, _getinode, _setftime, _of_tab
_rwsetup::
	call ___sdcc_enter_ix
	xor a
	ld (_udata + 0x6c), a
	ld hl, (_udata + 20)
	ld (_udata + 0x62), hl
	ld hl, (_udata + 22)
	ld (_udata + 0x64), hl
	call	ixh_getinode_argn
	ld a, h
	or l
	jp z, rs_out
	push hl			; -2(ix) = ino
	ld hl, (_udata + 0x12)
	ld de, #_udata + 0x7d
	add hl, de
	ld l, (hl)
	call	ixh_oft
	push hl			; -4(ix) = oftp
	push hl
	pop iy
	ld a, 6 (iy)
	ld e, 5 (ix)
	ld d, 6 (ix)
	ld (de), a
	and #3
	ld c, a
	ld a, 4 (ix)
	and #1
	cp c
	jr nz, rs_ok
	ld hl, #9		; EBADF
	ld (_udata + 0x0c), hl
	ld hl, #0
	jp rs_out
rs_ok:
	bit 0, 4 (ix)
	ld a, #1
	jr nz, rs_t
	ld a, #7
rs_t:
	push af
	inc sp
	call	ixh_lh_m2
	push hl
	call _setftime
	pop af
	inc sp
	call	ixh_lh_m2
	call	ixh_p1_getmode
	ld a, l
	cp #0x80
	jp nz, rs_off
	bit 0, 4 (ix)
	jp nz, rs_off
	call	ixh_ed_m4
	push de
	pop iy
	bit 2, 6 (iy)		; O_APPEND
	jp z, rs_off
	call	ixh_lh_m2
	ld bc, #0x0e		; ino->c_node.i_size
	add hl, bc
	ld bc, #4
	ldir			; de = oftp (o_ptr)
rs_off:
	call	ixh_lh_m4
	ld de, #_udata + 0x66
	ld bc, #4
	ldir
	call	ixh_lh_m2
rs_out:
	jp	ixh_leave

; ---- int dev_openi(inoptr *ino, uint16_t flag) ----
	.globl _dev_openi, _i_deref, _d_open, _tty_post
_dev_openi::
	call ___sdcc_enter_ix
	call	ixh_lh_p4
	ld e, (hl)
	inc hl
	ld d, (hl)		; de = *ino
	ld hl, #0x1e
	add hl, de
	ld c, (hl)
	inc hl
	ld b, (hl)		; bc = da
	ld a, b
	cp #2
	jp nz, do_open
	ld a, c
	or a
	jp nz, do_open
	ld hl, (_udata + 0x8f)	; u_ctty
	ld a, h
	or l
	jp nz, have_ctty
	ld hl, #0x13		; ENODEV
	ld (_udata + 0x0c), hl
	ld hl, #0xffff
	jp do_out
have_ctty:
	push de
	call _i_deref
	pop af
	ld de, (_udata + 0x8f)
	call	ixh_lh_p4
	ld (hl), e
	inc hl
	ld (hl), d		; *ino = u_ctty
	ld hl, #0x1e
	add hl, de
	ld c, (hl)
	inc hl
	ld b, (hl)		; da = i_addr[0]
	ld hl, #0x46
	add hl, de
	inc (hl)		; i_ref
do_open:
	push bc
	ld a, 6 (ix)
	push af
	inc sp
	push bc
	call _d_open
	pop af
	inc sp
	pop bc
	ld a, h
	or l
	jp nz, do_out
	ld a, b
	cp #2
	jp nz, do_out
	call	ixh_lh_p6
	push hl
	ld a, c
	push af
	inc sp
	call	ixh_lh_p4
	ld e, (hl)
	inc hl
	ld d, (hl)
	push de
	call _tty_post
	pop af
	inc sp
	pop af
	ld hl, #0
do_out:
	jp	ixh_leave

; ---- wait_pipe_read / wait_pipe_write (inoptr ino, uint8 flag) ----
	.globl _psleep_flags
_wait_pipe_read::
	call ___sdcc_enter_ix
wr_loop:
	call	ixh_lh_p4
	ld de, #0x0e
	add hl, de
	ld c, (hl)
	inc hl
	ld b, (hl)
	ld a, b
	or c
	jp nz, wr_have
	call	ixh_lh_p4
	ld de, #0x48		; c_writers
	add hl, de
	ld a, (hl)
	or a
	jp z, wr_eof
	ld a, 6 (ix)
	push af
	inc sp
	call	ixh_lh_p4
	push hl
	call _psleep_flags
	pop af
	inc sp
	ld a, h
	or l
	jp z, wr_loop
wr_eof:
	ld hl, #0
	ld (_udata + 0x64), hl
	jp wr_out
wr_have:
	ld hl, (_udata + 0x64)
	ld a, l
	sub c
	ld a, h
	sbc a, b
	jr nc, wr_keep
	ld c, l
	ld b, h
wr_keep:
	ld (_udata + 0x64), bc
	ld hl, #1
wr_out:
	jp	ixh_leave

_wait_pipe_write::
	call ___sdcc_enter_ix
ww_loop:
	call	ixh_lh_p4
	ld de, #0x47		; c_readers: no reader -> EPIPE even if there is room
	add hl, de
	ld a, (hl)
	or a
	jp z, ww_epipe
	call	ixh_lh_p4
	ld de, #0x0e
	add hl, de
	ld e, (hl)
	inc hl
	ld d, (hl)
	ld hl, #0x1000
	or a
	sbc hl, de
	jp nc, ww_ok
ww_sleep:
	ld a, 6 (ix)
	push af
	inc sp
	call	ixh_lh_p4
	push hl
	call _psleep_flags
	pop af
	inc sp
	ld a, h
	or l
	jp z, ww_loop
	ld hl, #1
	jp ww_out
ww_epipe:
	ld hl, #0xffff
	ld (_udata + 0x99), hl
	ld hl, #0x20		; EPIPE
	ld (_udata + 0x0c), hl
	ld hl, (_udata)
	ld a, #13		; SIGPIPE
	push af
	inc sp
	push hl
	call _ssig
	pop af
	inc sp
	ld hl, #1
	jp ww_out
ww_ok:
	ld hl, #0
ww_out:
	jp	ixh_leave

; ---- int16_t doclose(uint8 uindex) ----
	.globl _doclose, _sync, _isdevice, _d_close, _d_flush, _oft_deref
	.globl _wr_inode, _bufsync, _i_tab, _fs_tab
_doclose::
	call ___sdcc_enter_ix
	ld a, 4 (ix)
	push af
	inc sp
	call _getinode
	inc sp
	ld a, h
	or l
	jr nz, dc_ok
	ld hl, #0xffff
	jp dc_out
dc_ok:
	push hl			; -2(ix) = ino
	ld bc, #0xffff
	push bc			; -4(ix) = flush_dev
	ld e, 4 (ix)
	ld d, #0
	ld hl, #_udata + 0x7d
	add hl, de
	ld a, (hl)
	push af			; -5(ix) = oftindex
	ld l, a
	call	ixh_oft
	push hl
	pop iy
	ld a, 6 (iy)
	and #3
	ld c, a			; c = m
	ld a, 7 (iy)
	dec a
	jp nz, dc_skip
	push bc
	call	ixh_lh_m2
	push hl
	call _isdevice
	pop af
	pop bc
	bit 0, l
	jr z, dc_nodev
	call	ixh_lh_m2
	ld de, #0x1e
	add hl, de
	ld e, (hl)
	inc hl
	ld d, (hl)
	push bc
	push de
	call _d_close
	pop af
	pop bc
dc_nodev:
	push bc
	call	ixh_lh_m2
	call	ixh_p1_getmode
	pop bc
	ld a, l
	cp #0x80
	jr nz, dc_nf
	ld a, c
	or a
	jr z, dc_nf
	call	ixh_lh_m2
	inc hl
	inc hl
	ld a, (hl)
	ld -4 (ix), a
	inc hl
	ld a, (hl)
	ld -3 (ix), a
dc_nf:
	ld a, c
	or a
	jr z, dc_nw
	call	ixh_lh_m2
	ld de, #0x48
	add hl, de
	dec (hl)		; c_writers--
dc_nw:
	ld a, c
	cp #1
	jr z, dc_skip
	call	ixh_lh_m2
	ld de, #0x47
	add hl, de
	dec (hl)		; c_readers--
dc_skip:
	ld e, 4 (ix)
	ld d, #0
	ld hl, #_udata + 0x7d
	add hl, de
	ld (hl), #0xff
	ld b, 4 (ix)
	ld hl, #1
	ld a, b
	or a
	jr z, cl_done
cl_lp:
	add hl, hl
	djnz cl_lp
cl_done:
	ld a, l
	cpl
	ld l, a
	ld a, h
	cpl
	ld h, a
	ld de, (_udata + 0x87)
	ld a, e
	and l
	ld e, a
	ld a, d
	and h
	ld d, a
	ld (_udata + 0x87), de
	ld a, -5 (ix)
	push af
	inc sp
	call _oft_deref
	inc sp
	ld a, -4 (ix)
	cp #0xff
	jr nz, dc_flush
	ld a, -3 (ix)
	cp #0xff
	jr z, dc_ret0
dc_flush:
	call	ixh_lh_m4
	push hl
	call _d_flush
	pop af
dc_ret0:
	ld hl, #0
dc_out:
	jp	ixh_leave

; ---- void sync(void) ----
_sync::
	call ___sdcc_enter_ix
	ld de, #_i_tab
sy_lp:
	ld a, e
	sub #<(_i_tab + 0x05dc)
	ld a, d
	sbc a, #>(_i_tab + 0x05dc)
	jp nc, sy_m
	push de
	pop iy
	ld a, 70 (iy)
	or a
	jr z, sy_next
	ld hl, #0x49
	add hl, de
	ld a, (hl)
	rlca
	jr nc, sy_next
	push hl
	push de
	push de
	call _wr_inode
	pop af
	pop de
	pop hl
	res 7, (hl)
sy_next:
	ld hl, #0x4b
	add hl, de
	ex de, hl
	jp sy_lp
sy_m:
	ld bc, #_fs_tab
sm_lp:
	ld a, c
	sub #<(_fs_tab + 0x038c)
	ld a, b
	sbc a, #>(_fs_tab + 0x038c)
	jp nc, sm_end
	ld l, c
	ld h, b
	ld e, (hl)
	inc hl
	ld d, (hl)
	ld a, e
	and d
	inc a
	jr z, sm_next
	ld hl, #0xd8		; m_fs.s_fmod
	add hl, bc
	ld a, (hl)
	cp #2
	jr z, sm_next
	or a
	jr nz, sm_nc
	ld (hl), #2
sm_nc:
	push bc
	ld a, #1
	push af
	inc sp
	ld hl, #1
	push hl
	push de
	call _bread
	pop af
	pop af
	inc sp
	pop bc
	ld a, h
	or l
	jr z, sm_next
	push hl
	push bc
	ld e, l
	ld d, h
	ld hl, #6
	add hl, bc
	ld bc, #0xdd
	ldir
	pop bc
	pop hl
	push bc
	ld a, #2
	push af
	inc sp
	push hl
	call _bfree
	pop af
	inc sp
	pop bc
sm_next:
	ld hl, #0xe3
	add hl, bc
	ld c, l
	ld b, h
	jp sm_lp
sm_end:
	call _bufsync
	jp	ixh_leave
