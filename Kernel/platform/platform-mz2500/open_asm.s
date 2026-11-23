;--------------------------------------------------------
; File Created by SDCC : free open source ANSI-C Compiler
; Version 3.9.1 #0 (Linux)
;--------------------------------------------------------
	.module open_asm
	.optsdcc -mz80
	
;--------------------------------------------------------
; Public variables in this module
;--------------------------------------------------------
	.globl _pagemap_mem_used
	.globl _lastname, _of_tab, _udata
	.globl _chksigs
	.globl _wakeup
	.globl _psleep
	.globl _dev_openi
	.globl _getmode
	.globl _setftime
	.globl _getperm
	.globl _getinode
	.globl _f_trunc
	.globl _f_trunc_blocks
	.globl _isdevice
	.globl _wr_inode
	.globl _i_deref
	.globl _uf_alloc_n
	.globl _uf_alloc
	.globl _oft_deref
	.globl _deflock
	.globl _oft_alloc
	.globl _newfile
	.globl _ch_link
	.globl _n_open
	.globl _psleep_flags
	.globl _uput
	.globl _uget
	.globl __open
	.globl __link
	.globl __fcntl
	.globl __uname
	.globl __flock
	.globl __ftruncate
;--------------------------------------------------------
; special function registers
;--------------------------------------------------------
;--------------------------------------------------------
; ram data
;--------------------------------------------------------
	.area _DATA
__open_parent_65536_290:
	.ds 2
;--------------------------------------------------------
; ram data
;--------------------------------------------------------
	.area _INITIALIZED
;--------------------------------------------------------
; absolute external ram data
;--------------------------------------------------------
	.area _DABS (ABS)
;--------------------------------------------------------
; global & static initialisations
;--------------------------------------------------------
	.area _HOME
	.area _GSINIT
	.area _GSFINAL
	.area _GSINIT
;--------------------------------------------------------
; Home
;--------------------------------------------------------
	.area _HOME
	.area _HOME
;--------------------------------------------------------
; code
;--------------------------------------------------------
	.area _CODE2

; arg_t _open(void)  -- hand asm (replaces the SDCC output)
; locals: -1 uindex, -2 oftindex, -4 ino, -6 parent, -7 r, -8 w
; udata: u_argn +0x12 (name), u_argn1 +0x14 (flag), u_argn2 +0x16 (mode)
__open::
	call ___sdcc_enter_ix
	ld hl, #-8
	add hl, sp
	ld sp, hl
	ld hl, #0
	ld -6 (ix), l
	ld -5 (ix), h
	ld hl, (_udata + 0x14)	; flag
	ld a, l
	inc a
	ld c, a
	and #1
	ld -7 (ix), a		; r
	ld a, c
	and #2
	ld -8 (ix), a		; w
	ld a, h
	and #0xe0
	jr nz, op_bad
	ld a, l
	and #0xc0
	jr nz, op_bad
	ld a, l
	and #3
	cp #3
	jr nz, op_1
op_bad:
	ld hl, #22		; EINVAL
	ld (_udata + 0x0c), hl
	jp op_m1
op_1:
	call _uf_alloc
	ld -1 (ix), l
	inc l
	jp z, op_m1
	call _oft_alloc
	ld -2 (ix), l
	inc l
	jp z, op_nooft
	push ix
	pop hl
	ld de, #-6
	add hl, de
	push hl			; &parent
	ld hl, (_udata + 0x12)
	push hl			; name
	call _n_open
	pop af
	pop af
	ld -4 (ix), l
	ld -3 (ix), h
	ld a, h
	or l
	jp z, op_new
	call	ixh_lh_m6
	call	ixh_p1_i_deref
	ld a, (_udata + 0x15)
	and #3
	cp #3			; O_CREAT|O_EXCL
	jr nz, op_perm
	ld hl, #17		; EEXIST
	ld (_udata + 0x0c), hl
	call	ixh_lh_m4
	call	ixh_p1_i_deref
	jp op_idrop
op_perm:
	call op_chk
	jp z, op_have
op_acc:
	ld hl, #13		; EACCES
	ld (_udata + 0x0c), hl
	jp op_ideref
op_new:
	ld hl, (_udata + 0x0c)
	ld de, #14		; EFAULT
	or a
	sbc hl, de
	jp z, op_pdrop
	ld a, -5 (ix)
	or -6 (ix)
	jp z, op_pdrop
	ld a, (_udata + 0x15)
	bit 0, a		; O_CREAT
	jr nz, op_cr
	ld hl, #2		; ENOENT
	ld (_udata + 0x0c), hl
	jp op_pdrop
op_cr:
	ld hl, #_lastname
	push hl
	call	ixh_lh_m6
	push hl
	call _newfile
	pop af
	pop af
	ld -4 (ix), l
	ld -3 (ix), h
	ld a, h
	or l
	jp z, op_ideref
	push hl
	pop iy
	ld hl, (_udata + 0x6d)	; u_mask
	ld a, l
	cpl
	ld c, a
	ld a, h
	cpl
	ld b, a
	ld hl, (_udata + 0x16)	; mode
	ld a, h
	and #0x0f
	and b
	or #0x80		; F_REG
	ld 7 (iy), a
	ld a, l
	and c
	ld 6 (iy), a
	ld a, #7		; A_TIME|M_TIME|C_TIME
	push af
	inc sp
	call	ixh_lh_m4
	push hl
	call _setftime
	pop af
	inc sp
	call	ixh_lh_m4
	call	ixh_p1_wr_inode
	call op_chk
	jp nz, op_acc
op_have:
	ld a, -2 (ix)		; of_tab[oftindex].o_inode = ino
	call op_oft
	ld de, #4
	add hl, de
	ld a, -4 (ix)
	ld (hl), a
	inc hl
	ld a, -3 (ix)
	ld (hl), a
	ld a, -8 (ix)
	or a
	jr z, op_nw
	call	ixh_lh_m4
	call	ixh_p1_getmode
	ld a, l
	cp #0x40		; F_DIR
	jr nz, op_nd
	ld hl, #21		; EISDIR
	ld (_udata + 0x0c), hl
	jp op_idrop
op_nd:
	call	ixh_lh_m4
	push hl
	call _isdevice
	pop af
	bit 0, l
	jr nz, op_nw
	call	ixh_lh_m4
	ld de, #0x49
	add hl, de
	bit 6, (hl)		; CRDONLY
	jr z, op_nw
	ld hl, #30		; EROFS
	ld (_udata + 0x0c), hl
	jp op_idrop
op_nw:
	call	ixh_lh_m4
	push hl
	call _isdevice
	pop af
	bit 0, l
	jr z, op_nodev
	ld a, -2 (ix)
	call op_oft
	ld de, #4
	add hl, de		; iptr = &o_inode
	ld de, (_udata + 0x14)
	push hl
	push de			; flag
	push hl			; iptr
	call _dev_openi
	pop af
	pop af
	pop de			; de = iptr
	ld a, h
	or l
	jp nz, op_cantopen
	ex de, hl
	ld a, (hl)
	ld -4 (ix), a
	inc hl
	ld a, (hl)
	ld -3 (ix), a
	jr op_link
op_nodev:
	ld a, -8 (ix)
	or a
	jr z, op_link
	ld a, (_udata + 0x15)
	bit 2, a		; O_TRUNC
	jr z, op_link
	call	ixh_lh_m4
	call	ixh_p1_getmode
	ld a, l
	cp #0x80		; F_REG
	jr nz, op_link
	call	ixh_lh_m4
	push hl
	call _f_trunc
	pop af
	ld a, h
	or l
	jp nz, op_idrop
	call	ixh_ed_m4
	ld hl, #_of_tab + 4
	ld b, #32		; OFTSIZE
op_tl:
	ld a, (hl)
	cp e
	jr nz, op_tn
	inc hl
	ld a, (hl)
	dec hl
	cp d
	jr nz, op_tn
	push hl
	ld a, l
	sub #4
	ld l, a
	ld a, h
	sbc a, #0
	ld h, a
	xor a
	ld (hl), a
	inc hl
	ld (hl), a
	inc hl
	ld (hl), a
	inc hl
	ld (hl), a
	pop hl
op_tn:
	ld a, #8
	add a, l
	ld l, a
	jr nc, op_tc
	inc h
op_tc:
	djnz op_tl
op_link:
	ld hl, #_udata + 0x7d	; u_files[uindex] = oftindex
	ld e, -1 (ix)
	ld d, #0
	add hl, de
	ld a, -2 (ix)
	ld (hl), a
	call op_oft
	xor a
	ld (hl), a		; o_ptr = 0
	inc hl
	ld (hl), a
	inc hl
	ld (hl), a
	inc hl
	ld (hl), a
	inc hl
	inc hl
	inc hl
	ld a, (_udata + 0x14)
	ld (hl), a		; o_access
	ld a, (_udata + 0x15)
	bit 4, a		; O_CLOEXEC
	jr z, op_nc
	ld a, -1 (ix)
	ld b, a
	inc b
	ld hl, #1
op_sh:
	dec b
	jr z, op_shd
	add hl, hl
	jr op_sh
op_shd:
	ld de, (_udata + 0x87)
	ld a, e
	or l
	ld e, a
	ld a, d
	or h
	ld d, a
	ld (_udata + 0x87), de
op_nc:
	call	ixh_lh_m4
	ld de, #0x48
	add hl, de		; &c_writers
	ld a, (_udata + 0x14)
	and #3
	jr z, op_nwr
	inc (hl)
op_nwr:
	cp #1
	jr z, op_nrd
	dec hl
	inc (hl)		; c_readers
op_nrd:
	call	ixh_lh_m4
	call	ixh_p1_getmode
	ld a, l
	cp #0x10		; F_PIPE
	jr nz, op_ok
	ld a, -2 (ix)
	call op_oft
	ld de, #7
	add hl, de
	ld a, (hl)		; o_refs
	dec a
	jr nz, op_pw
	ld a, (_udata + 0x14)
	bit 4, a		; O_NDELAY
	jr nz, op_pw
	call	ixh_lh_m4
	push hl
	call _psleep
	pop af
	call _chksigs
	ld a, l
	or a
	jr z, op_pw
	ld hl, #4		; EINTR
	ld (_udata + 0x0c), hl
	jp op_idrop
op_pw:
	call	ixh_lh_m4
	ld de, #0x48
	add hl, de
	ld a, (hl)
	or a
	jr nz, op_ok
	ld a, (_udata + 0x14)
	bit 4, a
	jr z, op_ok
	ld hl, #6		; ENXIO
	ld (_udata + 0x0c), hl
	jp op_idrop
op_ok:
	ld l, -1 (ix)
	ld h, #0
	jr op_out
op_pdrop:
	ld a, -5 (ix)
	or -6 (ix)
	jr z, op_ideref
	call	ixh_lh_m6
	call	ixh_p1_i_deref
op_ideref:
	ld a, -3 (ix)
	or -4 (ix)
	jr z, op_idrop
	call	ixh_lh_m4
	call	ixh_p1_i_deref
op_idrop:
op_cantopen:
	ld a, -2 (ix)
	push af
	inc sp
	call _oft_deref
	inc sp
op_nooft:
	ld hl, #_udata + 0x7d
	ld e, -1 (ix)
	ld d, #0
	add hl, de
	ld (hl), #0xff		; NO_FILE
op_m1:
	ld hl, #0xffff
op_out:
	jp	ixh_leave
; hl = &of_tab[a]
op_oft:
	ld l, a
	call	ixh_oft
	ret
; Z if the requested access is allowed on ino (-4)
op_chk:
	call	ixh_lh_m4
	push hl
	call _getperm
	pop af
	ld a, -7 (ix)
	or a
	jr z, op_c1
	bit 2, l		; OTH_RD
	jr z, op_cf
op_c1:
	ld a, -8 (ix)
	or a
	ret z
	bit 1, l		; OTH_WR
	jr z, op_cf
	xor a
	ret
op_cf:
	or #1			; NZ
	ret
	.area _CODE
	.area _CONST
	.area _INITIALIZER
	.area _CABS (ABS)
