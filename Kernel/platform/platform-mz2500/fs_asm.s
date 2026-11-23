; Hand written replacements for small filesys.c functions.
	.module fs_asm
	.globl _udata, _of_tab, _int_disabled
	.globl _i_open, _validchk, _i_alloc, _fs_tab_get, _breadi, _kputs, __divsint, _i_tab, _fs_tab
	.globl _i_deref, _getmode, _magic, _panic, _wakeup, _f_trunc, _i_free, _wr_inode
	.globl _n_open, _valaddr_r, _getperm, _lastname, _root_dev, __ugetc
	.globl _ch_link, _readi, _writei
	.globl _blk_alloc, _blk_free, _getdev, _validblk, _bawrite
	.globl _i_alloc, _i_free, _sync
	.globl _getinode, _getperm, _setftime, _rdtime32, _panic, _magic
	.globl _deflock, _oft_deref, _of_tab
	.globl _newfile, _getperm
	.globl _getdev, _rdtime
	.globl _unlinki, _getmode, _ch_link, _setftime, _kprintf
	.globl _corrupt_fs, _wr_inode, _f_trunc_blocks, _f_trunc, _freeblk, _validblk, _bwritei
	.globl _srch_dir, _bmap, _bread, _brelse, _i_open, _inode_blocks, ___sdcc_enter_ix
	.globl _oft_alloc, _uf_alloc, _uf_alloc_n, _namecomp, _isdevice, _devnum

	.area _CODE

; int_fast8_t oft_alloc(void): first free open-file slot (8 byte entries),
; refs=1, inode=NULL. -1 and u_error=ENFILE if none.
_oft_alloc::
	ld hl, #_of_tab + 7	; o_refs of slot 0
	ld de, #8
	ld bc, #0x2000		; B = OFTSIZE, C = index
1$:	ld a, (hl)
	or a
	jr z, 2$
	add hl, de
	inc c
	djnz 1$
	ld hl, #23		; ENFILE
	ld (_udata + 12), hl
	ld l, #0xff
	ret
2$:	ld (hl), #1
	dec hl
	dec hl
	dec hl			; o_inode
	xor a
	ld (hl), a
	inc hl
	ld (hl), a
	ld l, c
	ret

; int_fast8_t uf_alloc(void) / uf_alloc_n(uint8_t base)
_uf_alloc::
	ld c, #0
	jr ufbody
_uf_alloc_n::
	ld hl, #2
	add hl, sp
	ld c, (hl)
ufbody:
	ld a, c
	cp #10			; UFTSIZE
	jr nc, 3$
	ld hl, #_udata + 125	; u_files
	ld e, a
	ld d, #0
	add hl, de
1$:	ld a, (hl)
	inc a			; NO_FILE = 0xFF
	jr z, 2$
	inc hl
	inc c
	ld a, c
	cp #10
	jr c, 1$
3$:	ld hl, #24		; EMFILE
	ld (_udata + 12), hl
	ld l, #0xff
	ret
2$:	ld l, c
	ret

; bool namecomp(uint8_t *n1, uint8_t *n2): equal up to FILENAME_LEN (30)
; chars, n1 terminated by NUL or '/', n2 likewise at the end.
_namecomp::
	call	ixh_sp2_ed
	inc hl
	ld a, (hl)
	inc hl
	ld h, (hl)
	ld l, a			; HL = n2
	ld b, #30
1$:	ld a, (de)
	or a
	jr z, 3$
	cp #'/'
	jr z, 3$
	cp (hl)
	jr nz, 9$
	inc de
	inc hl
	djnz 1$
	jr 8$
3$:	ld a, (hl)
	or a
	jr z, 8$
	cp #'/'
	jr z, 8$
9$:	ld l, #0
	ret
8$:	ld l, #1
	ret

; bool isdevice(inoptr ino): ino->c_node.i_mode & F_CDEV (0x2000)
_isdevice::
	ld hl, #2
	add hl, sp
	ld a, (hl)
	inc hl
	ld h, (hl)
	ld l, a
	ld de, #7		; c_node(6) + high byte of i_mode
	add hl, de
	ld a, (hl)
	and #0x20
	ld l, #0
	ret z
	inc l
	ret

; uint16_t devnum(inoptr ino): ino->c_node.i_addr[0]
_devnum::
	ld hl, #2
	add hl, sp
	ld a, (hl)
	inc hl
	ld h, (hl)
	ld l, a
	ld de, #30		; c_node(6) + i_addr offset (24)
	add hl, de
	ld e, (hl)
	inc hl
	ld d, (hl)
	ex de, hl
	ret

; inoptr srch_dir(inoptr wd, uint8_t *compname)
; locals: -2 nblocks, -4 curblock, -6 buf, -7 count, -9 cur entry
_srch_dir::
	call ___sdcc_enter_ix
	ld hl, #-10
	add hl, sp
	ld sp, hl
	call	ixh_lh_p4
	push hl
	call _inode_blocks
	pop af
	ld -2 (ix), l
	ld -1 (ix), h
	xor a
	ld -4 (ix), a
	ld -3 (ix), a
sd_blk:
	call	ixh_lh_m4
	call	ixh_ed_m2
	or a
	sbc hl, de
	jp nc, sd_none
	ld hl, #1
	push hl
	call	ixh_lh_m4
	push hl
	call	ixh_lh_p4
	push hl
	call _bmap
	pop af
	pop af
	pop af
	ex de, hl		; de = physical block
	call	ixh_lh_p4
	inc hl
	inc hl
	ld c, (hl)
	inc hl
	ld b, (hl)		; bc = c_dev
	xor a
	push af
	inc sp
	push de
	push bc
	call _bread
	pop af
	pop af
	inc sp
	ld a, h
	or l
	jp z, sd_none
	ld -6 (ix), l
	ld -5 (ix), h
	ld -9 (ix), l
	ld -8 (ix), h
	ld -7 (ix), #16
sd_ent:
	ld l, -9 (ix)
	ld h, -8 (ix)
	inc hl
	inc hl			; n2 = d_name
	call	ixh_ed_p6
	ld b, #30
sd_c1:
	ld a, (de)
	or a
	jr z, sd_c3
	cp #'/'
	jr z, sd_c3
	cp (hl)
	jr nz, sd_next
	inc de
	inc hl
	djnz sd_c1
	jr sd_match
sd_c3:
	ld a, (hl)
	or a
	jr z, sd_match
	cp #'/'
	jr nz, sd_next
sd_match:
	ld l, -9 (ix)
	ld h, -8 (ix)
	ld c, (hl)
	inc hl
	ld b, (hl)		; inum
	push bc
	call	ixh_lh_m6
	call	ixh_p1_brelse
	pop bc
	call	ixh_lh_p4
	inc hl
	inc hl
	ld e, (hl)
	inc hl
	ld d, (hl)
	push bc
	push de
	call _i_open
	pop af
	pop af
	jp sd_out
sd_next:
	ld l, -9 (ix)
	ld h, -8 (ix)
	ld de, #32
	add hl, de
	ld -9 (ix), l
	ld -8 (ix), h
	dec -7 (ix)
	jp nz, sd_ent
	call	ixh_lh_m6
	call	ixh_p1_brelse
	inc -4 (ix)
	jp nz, sd_blk
	inc -3 (ix)
	jp sd_blk
sd_none:
	ld hl, #0
sd_out:
	jp	ixh_leave

; inoptr i_open(uint16_t dev, uint16_t ino)
; locals: -2 m, -4 nindex, -5 isnew
_i_open::
	call ___sdcc_enter_ix
	ld hl, #-6
	add hl, sp
	ld sp, hl
	xor a
	ld -5 (ix), a
	ld hl, #io_s0
	push hl
	call	ixh_lh_p4
	push hl
	call _validchk
	pop af
	pop af
	ld a, 7 (ix)
	or 6 (ix)
	jr nz, io_have
	ld -5 (ix), #1
	call	ixh_lh_p4
	push hl
	call _i_alloc
	pop af
	ld 6 (ix), l
	ld 7 (ix), h
	ld a, h
	or l
	jr nz, io_have
	ld hl, #0x1c		; ENOSPC
	ld (_udata + 0x0c), hl
	jp io_null
io_have:
	call	ixh_lh_p4
	push hl
	call _fs_tab_get
	pop af
	ld -2 (ix), l
	ld -1 (ix), h
	ld a, 6 (ix)
	sub #1
	ld a, 7 (ix)
	sbc a, #0
	jp c, io_badnum
	ld de, #8
	add hl, de
	ld a, (hl)
	inc hl
	ld h, (hl)
	ld l, a
	dec hl
	dec hl
	add hl, hl
	add hl, hl
	add hl, hl
	ld a, 6 (ix)
	sub l
	ld a, 7 (ix)
	sbc a, h
	jp nc, io_badnum
	ld bc, #0		; bc = nindex (last free slot)
	ld de, #_i_tab
io_scan:
	push de
	pop iy
	ld a, 70 (iy)
	or a
	jr nz, io_used
	ld b, d
	ld c, e
io_used:
	ld l, e
	ld h, d
	inc hl
	inc hl
	ld a, (hl)
	cp 4 (ix)
	jr nz, io_next
	inc hl
	ld a, (hl)
	cp 5 (ix)
	jr nz, io_next
	inc hl
	ld a, (hl)
	cp 6 (ix)
	jr nz, io_next
	inc hl
	ld a, (hl)
	cp 7 (ix)
	jr nz, io_next
	ld -4 (ix), e		; found in table
	ld -3 (ix), d
	jp io_found
io_next:
	ld hl, #0x4b
	add hl, de
	ex de, hl
	ld a, e
	sub #<(_i_tab + 0x05dc)
	ld a, d
	sbc a, #>(_i_tab + 0x05dc)
	jp c, io_scan
	ld a, b
	or c
	jr nz, io_slot
	ld hl, #0x17		; ENFILE
	ld (_udata + 0x0c), hl
	jp io_null
io_slot:
	ld -4 (ix), c
	ld -3 (ix), b
	ld hl, #6
	add hl, bc
	push hl
	call	ixh_lh_p6
	push hl
	call	ixh_lh_p4
	push hl
	call _breadi
	pop af
	pop af
	pop af
	ld a, l
	or a
	jp nz, io_null
	call	ixh_lh_m4
	ld (hl), #0x91		; c_magic
	inc hl
	ld (hl), #0x60
	inc hl
	ld a, 4 (ix)
	ld (hl), a		; c_dev
	inc hl
	ld a, 5 (ix)
	ld (hl), a
	inc hl
	ld a, 6 (ix)
	ld (hl), a		; c_num
	inc hl
	ld a, 7 (ix)
	ld (hl), a
	call	ixh_lh_m2
	ld de, #_fs_tab
	or a
	sbc hl, de
	ld de, #0xe3
	push de
	push hl
	call __divsint
	pop af
	pop af
	call	ixh_ed_m4
	ld a, l
	ld hl, #0x4a
	add hl, de
	ld (hl), a		; c_super
	call	ixh_lh_m2
	inc hl
	inc hl
	ld a, #0x40
	bit 0, (hl)		; MS_RDONLY
	jr nz, io_fl
	xor a
io_fl:
	ld hl, #0x49
	add hl, de
	ld (hl), a		; c_flags
io_found:
	call	ixh_ed_m4
	ld hl, #8
	add hl, de
	ld c, (hl)
	inc hl
	ld b, (hl)		; bc = i_nlink
	ld hl, #7
	add hl, de
	ld a, (hl)
	and #0xf0		; F_MASK
	bit 0, -5 (ix)
	jr z, io_old
	or c
	or b
	jp nz, io_baddisk	; new: must be unused
	jr io_ok
io_old:
	ld l, a
	ld a, b
	or c
	jp z, io_baddisk
	ld a, l
	or a
	jp z, io_baddisk
io_ok:
	ld hl, #0x46
	add hl, de
	inc (hl)		; c_refs++
	ex de, hl
	call	ixh_lh_m4
	jp io_out
io_badnum:
	ld hl, #io_s1
	jr io_kp
io_baddisk:
	ld hl, #io_s2
io_kp:
	call	ixh_p1_kputs
io_null:
	ld hl, #0
io_out:
	jp	ixh_leave
io_s0:	.ascii "i_open"
	.db 0
io_s1:	.ascii "i_open: bad inode number"
	.db 10, 0
io_s2:	.ascii "i_open: bad disk inode"
	.db 10, 0

; void i_deref(inoptr ino)
_i_deref::
	call ___sdcc_enter_ix
	push af			; -1(ix) = mode
	call	ixh_lh_p4
	call	ixh_p1_getmode
	ld -1 (ix), l
	call	ixh_lh_p4
	ld a, (hl)
	cp #0x91		; CMAGIC low
	jr nz, id_mg
	inc hl
	ld a, (hl)
	cp #0x60
	jr z, id_mok
id_mg:
	call	ixh_lh_p4
	push hl
	call _magic		; panics
	pop af
id_mok:
	call	ixh_cb_p4
	ld hl, #0x46
	add hl, bc
	ld a, (hl)
	or a
	jr nz, id_r1
	ld hl, #id_s8
	call	ixh_p1_panic
id_r1:
	ld a, -1 (ix)
	cp #0x10		; pipe
	jr nz, id_np
	push bc
	push bc
	call _wakeup
	pop af
	pop bc
id_np:
	ld hl, #0x46
	add hl, bc
	dec (hl)
	jr nz, id_nt
	ld hl, #8
	add hl, bc
	ld a, (hl)
	inc hl
	or (hl)
	jr nz, id_nt
	ld a, -1 (ix)
	cp #0x80
	jr z, id_tr
	cp #0x40
	jr z, id_tr
	cp #0x10
	jr nz, id_nt
id_tr:
	push bc
	push bc
	call _f_trunc
	pop af
	pop bc
id_nt:
	ld hl, #0x46
	add hl, bc
	ld a, (hl)
	or a
	jr nz, id_out
	ld hl, #0x49
	add hl, bc
	bit 7, (hl)
	jr z, id_out
	ld hl, #8
	add hl, bc
	ld a, (hl)
	inc hl
	or (hl)
	jr nz, id_wr
	ld hl, #6
	add hl, bc
	ld (hl), #0
	inc hl
	ld (hl), #0		; i_mode = 0
	ld hl, #4
	add hl, bc
	ld e, (hl)
	inc hl
	ld d, (hl)		; c_num
	ld hl, #2
	add hl, bc
	ld a, (hl)
	inc hl
	ld h, (hl)
	ld l, a			; c_dev
	push bc
	push de
	push hl
	call _i_free
	pop af
	pop af
	pop bc
id_wr:
	push bc
	call _wr_inode
	pop af
id_out:
	jp	ixh_leave
id_s8:	.ascii "inode freed."
	.db 0

; inoptr srch_mt(inoptr ino): if ino is a mount point, deref it and
; return the root inode of the mounted fs, else ino.
	.globl _srch_mt
_srch_mt::
	call	ixh_sp2_ed
	ld hl, #_fs_tab
	ld b, #4		; NMOUNTS
sm_lp:
	ld a, (hl)
	inc hl
	and (hl)
	dec hl
	inc a
	jr z, sm_next		; m_dev == NO_DEVICE
	push hl
	pop iy
	ld a, 4 (iy)
	cp e
	jr nz, sm_next
	ld a, 5 (iy)
	cp d
	jr z, sm_hit
sm_next:
	ld a, l
	add a, #0xe3
	ld l, a
	jr nc, sm_nc
	inc h
sm_nc:
	djnz sm_lp
	ex de, hl		; not a mount point: return ino
	ret
sm_hit:
	ld c, (hl)
	inc hl
	ld b, (hl)		; bc = m_dev
	push bc
	push de
	call _i_deref
	pop af
	pop bc
	ld hl, #1		; ROOTINODE
	push hl
	push bc
	call _i_open
	pop af
	pop af
	ret

; ---- uint8 nm_getcf(void): next path char (A), with fault handling ----
nm_getcf:
	ld hl, (nm_name)
	ld de, (nm_end)
	ld a, l
	cp e
	jr nz, ng_go
	ld a, h
	cp d
	jr nz, ng_go
	ld a, (nm_ftype)
	ld l, a
	ld h, #0
	ld (_udata + 0x0c), hl
	ld a, #1
	ld (nm_fault), a
	xor a
	ret
ng_go:
	call __ugetc
	ld a, l
	ret

; ---- inoptr n_open(uint8_t *namep, inoptr *parent) ----
; locals: -2 wd, -4 ninode
_n_open::
	call ___sdcc_enter_ix
	ld hl, #-4
	add hl, sp
	ld sp, hl
	ld a, 6 (ix)
	or 7 (ix)
	jr z, no_p0
	call	ixh_lh_p6
	xor a
	ld (hl), a
	inc hl
	ld (hl), a
no_p0:
	ld hl, #0x200
	push hl
	call	ixh_lh_p4
	push hl
	call _valaddr_r
	pop af
	pop af
	ld a, h
	or l
	jp z, no_out
	ld c, l
	ld b, h			; bc = len
	ld e, 4 (ix)
	ld d, 5 (ix)
	ld (nm_name), de
	ex de, hl
	add hl, bc
	ld (nm_end), hl
	xor a
	ld (nm_fault), a
	ld a, b
	cp #2
	jr nz, no_acc
	ld a, c
	or a
	jr nz, no_acc
	ld a, #0x25		; ENAMETOOLONG
	jr no_ft
no_acc:
	ld a, #0x0d		; EACCES
no_ft:
	ld (nm_ftype), a
	call nm_getcf
	cp #'/'
	jr nz, no_cwd
	ld hl, (_udata + 0x8b)	; u_root
	jr no_wd
no_cwd:
	ld hl, (_udata + 0x89)	; u_cwd
no_wd:
	ld -2 (ix), l
	ld -1 (ix), h
	ld -4 (ix), l
	ld -3 (ix), h
	ld de, #0x46
	add hl, de
	inc (hl)
	inc (hl)		; two references
no_top:
	ld a, -3 (ix)
	or -4 (ix)
	jr z, no_n1
	call	ixh_lh_m4
	ld a, (hl)
	cp #0x91
	jr nz, no_mg
	inc hl
	ld a, (hl)
	cp #0x60
	jr z, no_n1
no_mg:
	call	ixh_lh_m4
	push hl
	call _magic
	pop af
no_n1:
	ld hl, (_udata + 0x8d)	; u_rename
	call	ixh_ed_m4
	or a
	sbc hl, de
	jr nz, no_n2
	ld (_udata + 0x8d), hl	; hl == 0
no_n2:
	ld a, -3 (ix)
	or -4 (ix)
	jr z, no_n3
	call	ixh_lh_m4
	push hl
	call _srch_mt
	pop af
	ld -4 (ix), l
	ld -3 (ix), h
no_n3:
	call nm_getcf
	cp #'/'
	jr nz, no_n4
	ld hl, (nm_name)
	inc hl
	ld (nm_name), hl
	jr no_n3
no_n4:
	or a
	jp z, no_done
	ld a, (nm_fault)
	or a
	jp nz, no_done
	ld a, -3 (ix)
	or -4 (ix)
	jr nz, no_n5
	ld hl, #2		; ENOENT
	ld (_udata + 0x0c), hl
	jp no_nodir
no_n5:
	call	ixh_lh_m2
	call	ixh_p1_i_deref
	call	ixh_lh_m4
	ld -2 (ix), l
	ld -1 (ix), h
	call	ixh_p1_getmode
	ld a, l
	cp #0x40
	jr z, no_n6
	ld hl, #0x14		; ENOTDIR
	ld (_udata + 0x0c), hl
	jp no_nodir
no_n6:
	call	ixh_lh_m2
	push hl
	call _getperm
	pop af
	ld a, l
	rrca
	jr c, no_n7
	ld hl, #0x0d		; EACCES
	ld (_udata + 0x0c), hl
	jp no_nodir
no_n7:
	ld hl, #_lastname
	ld (nm_fp), hl
no_cp:
	call nm_getcf
	or a
	jr z, no_cpend
	cp #'/'
	jr z, no_cpend
	ld c, a
	ld hl, (nm_fp)
	ld a, l
	cp #<(_lastname + 30)
	jr nz, no_st
	ld a, h
	cp #>(_lastname + 30)
	jr z, no_adv
no_st:
	ld (hl), c
	inc hl
	ld (nm_fp), hl
no_adv:
	ld hl, (nm_name)
	inc hl
	ld (nm_name), hl
	jr no_cp
no_cpend:
	ld hl, (nm_fp)
	ld (hl), #0
	ld a, (_lastname)
	cp #'.'
	jp nz, no_srch
	ld a, (_lastname + 1)
	cp #'.'
	jp nz, no_srch
	ld a, (_lastname + 2)
	or a
	jp nz, no_srch
	ld hl, (_udata + 0x8b)
	call	ixh_ed_m2
	or a
	sbc hl, de
	jr z, no_isroot
	call	ixh_lh_m2
	push hl
	pop iy
	ld a, 4 (iy)		; c_num == ROOTINODE ?
	dec a
	or 5 (iy)
	jp nz, no_srch
	ld l, 2 (iy)
	ld h, 3 (iy)
	ld de, (_root_dev)
	or a
	sbc hl, de
	jp z, no_srch
	ld a, 74 (iy)		; c_super
	ld hl, #_fs_tab + 4
	ld de, #0xe3
	or a
	jr z, no_mt
no_ml:
	add hl, de
	dec a
	jr nz, no_ml
no_mt:
	ld c, (hl)
	inc hl
	ld b, (hl)		; temp = m_mntpt
	ld hl, #0x46
	add hl, bc
	inc (hl)
	push bc
	call	ixh_lh_m2
	call	ixh_p1_i_deref
	pop bc
	ld -2 (ix), c
	ld -1 (ix), b
	jp no_srch
no_isroot:
	call	ixh_lh_m2
	ld de, #0x46
	add hl, de
	inc (hl)
	jp no_top
no_srch:
	ld hl, #_lastname
	push hl
	call	ixh_lh_m2
	push hl
	call _srch_dir
	pop af
	pop af
	ld -4 (ix), l
	ld -3 (ix), h
	jp no_top
no_done:
	ld a, (nm_fault)
	or a
	jr z, no_d1
	ld a, (nm_ftype)
	ld l, a
	ld h, #0
	ld (_udata + 0x0c), hl
	jp no_nodir
no_d1:
	ld a, 6 (ix)
	or 7 (ix)
	jr z, no_d2
	call	ixh_lh_p6
	call	ixh_ed_m2
	ld (hl), e
	inc hl
	ld (hl), d
	jr no_d3
no_d2:
	call	ixh_lh_m2
	call	ixh_p1_i_deref
no_d3:
	ld a, 6 (ix)
	or 7 (ix)
	jr nz, no_d4
	ld a, -3 (ix)
	or -4 (ix)
	jr nz, no_d4
	ld hl, #2		; ENOENT
	ld (_udata + 0x0c), hl
no_d4:
	call	ixh_lh_m4
	jp no_out
no_nodir:
	ld a, 6 (ix)
	or 7 (ix)
	jr z, no_nd1
	call	ixh_lh_p6
	xor a
	ld (hl), a
	inc hl
	ld (hl), a
no_nd1:
	call	ixh_lh_m2
	call	ixh_p1_i_deref
	ld hl, #0
no_out:
	jp	ixh_leave

	.area _DATA
nm_name:	.ds 2
nm_end:		.ds 2
nm_fp:		.ds 2
nm_fault:	.ds 1
nm_ftype:	.ds 1
	.area _CODE

	.area _CODE
; bool ch_link(inoptr wd, uint8 *oldname, uint8 *newname, inoptr nindex)
; curentry (struct direct, 32 bytes) lives at -32(ix): d_ino, d_name[30]
_ch_link::
	call ___sdcc_enter_ix
	ld hl, #-32
	add hl, sp
	ld sp, hl
	call	ixh_lh_p4
	ld de, #0x49
	add hl, de
	bit 6, (hl)		; CRDONLY
	jr z, cl_1
	ld hl, #0x1e		; EROFS
	jp cl_err
cl_1:
	call	ixh_lh_p4
	push hl
	call _getperm
	pop af
	bit 1, l		; OTH_WR
	jr nz, cl_2
	ld hl, #0x0d		; EACCES
	jp cl_err
cl_2:
	call	ixh_lh_p8
	ld a, (hl)
	or a
	jr nz, cl_3
	ld a, 10 (ix)
	or 11 (ix)
	jr z, cl_3
	ld hl, #0x11		; EEXIST
	jp cl_err
cl_3:
	ld hl, #0
	ld (_udata + 0x66), hl
	ld (_udata + 0x68), hl
cl_loop:
	ld hl, #32
	ld (_udata + 0x64), hl
	push ix
	pop hl
	ld de, #-32
	add hl, de
	ld (_udata + 0x62), hl
	ld a, #1
	ld (_udata + 0x6c), a	; u_sysio
	xor a
	push af
	inc sp
	call	ixh_lh_p4
	push hl
	call _readi
	pop af
	inc sp
	ld hl, (_udata + 0x99)
	ld a, h
	or l
	jr z, cl_brk
	push ix
	pop hl
	ld de, #-30
	add hl, de
	push hl
	call	ixh_lh_p6
	push hl
	call _namecomp
	pop af
	pop af
	bit 0, l
	jr z, cl_loop
cl_brk:
	ld hl, (_udata + 0x99)
	ld a, h
	or l
	jr nz, cl_4
	call	ixh_lh_p6
	ld a, (hl)
	or a
	jr z, cl_4
	ld hl, #2		; ENOENT
	jp cl_err
cl_4:
	push ix
	pop hl
	ld de, #-30
	add hl, de
	ex de, hl		; de = curentry.d_name
	call	ixh_lh_p8
	ld b, #30
cp_lp:
	ld a, (hl)
	ld (de), a
	inc de
	or a
	jr z, cp_pad
	inc hl
	djnz cp_lp
	jr cp_done
cp_pad:
	dec b
	jr z, cp_done
cp_z:
	xor a
	ld (de), a
	inc de
	djnz cp_z
cp_done:
	ld bc, #0
	ld a, 10 (ix)
	or 11 (ix)
	jr z, cl_ino
	ld l, 10 (ix)
	ld h, 11 (ix)
	ld de, #4
	add hl, de
	ld c, (hl)
	inc hl
	ld b, (hl)
cl_ino:
	ld -32 (ix), c
	ld -31 (ix), b
	ld hl, (_udata + 0x99)
	ld a, h
	or l
	jr z, cl_5
	ld hl, (_udata + 0x66)	; u_offset -= DIR_LEN
	ld de, #32
	or a
	sbc hl, de
	ld (_udata + 0x66), hl
	jr nc, cl_5
	ld hl, (_udata + 0x68)
	dec hl
	ld (_udata + 0x68), hl
cl_5:
	ld hl, #32
	ld (_udata + 0x64), hl
	push ix
	pop hl
	ld de, #-32
	add hl, de
	ld (_udata + 0x62), hl
	ld a, #1
	ld (_udata + 0x6c), a
	xor a
	push af
	inc sp
	call	ixh_lh_p4
	push hl
	call _writei
	pop af
	inc sp
	ld hl, (_udata + 0x0c)
	ld a, h
	or l
	jr z, cl_6
	ld hl, #0
	jp cl_out
cl_6:
	ld a, #7
	push af
	inc sp
	call	ixh_lh_p4
	push hl
	call _setftime
	pop af
	inc sp
	call	ixh_lh_p4
	ld de, #0x0e
	add hl, de		; hl -> i_size
	ld e, (hl)
	inc hl
	ld a, (hl)
	dec hl
	and #1
	ld d, a			; de = BLKOFF(i_size)
	or e
	jr z, cl_7
	push hl
	ld hl, #0x200
	or a
	sbc hl, de
	ex de, hl		; de = 512 - off
	pop hl
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
cl_7:
	ld hl, #1
	jp cl_out
cl_err:
	ld (_udata + 0x0c), hl
	ld hl, #0
cl_out:
	jp	ixh_leave

	.area _CODE
; blkno_t blk_alloc(uint16_t devno)   (dev = -2(ix); fs: +0 magic 0x31c6,
; +6 s_nfree, +8 s_free[50], +0xd8 s_tfree)
_blk_alloc::
	call ___sdcc_enter_ix
	call	ixh_lh_p4
	push hl
	call _getdev
	pop af
	push hl			; -2(ix) = dev
	ld a, (hl)
	cp #0xc6
	jp nz, ba_c2
	inc hl
	ld a, (hl)
	cp #0x31
	jp nz, ba_c2
	call	ixh_ed_m2
	ld hl, #6
	add hl, de
	ld c, (hl)
	inc hl
	ld b, (hl)
	dec hl
	ld a, b
	or c
	jp z, ba_corrupt
	ld a, #50
	cp c
	ld a, #0
	sbc a, b
	jp c, ba_corrupt
	dec bc
	ld (hl), c
	inc hl
	ld (hl), b		; --s_nfree
	sla c
	rl b
	ld hl, #8
	add hl, de
	add hl, bc
	ld c, (hl)
	inc hl
	ld b, (hl)		; bc = newno
	ld a, b
	or c
	jr nz, ba_09
	ld hl, #0xd8
	add hl, de
	ld a, (hl)
	inc hl
	or (hl)
	jp nz, ba_corrupt
	ld hl, #0x1c		; ENOSPC
	ld (_udata + 0x0c), hl
	ld hl, #6
	add hl, de
	ld a, (hl)
	inc a
	ld (hl), a
	jr nz, ba_z1
	inc hl
	inc (hl)
ba_z1:
	ld hl, #0
	jp ba_out
ba_09:
	ld hl, #6
	add hl, de
	ld a, (hl)
	inc hl
	or (hl)
	jr nz, ba_13		; s_nfree != 0: no refill
	push bc
	xor a
	push af
	inc sp
	push bc
	call	ixh_lh_p4
	push hl
	call _bread
	pop af
	pop af
	inc sp
	pop bc
	ld a, h
	or l
	jp z, ba_corrupt
	push hl
	pop iy			; iy = buf
	push bc
	call	ixh_ed_m2
	ld hl, #6
	add hl, de
	ex de, hl		; de = &dev->s_nfree
	push iy
	pop hl
	ld bc, #0x66
	ldir
	pop bc
	push bc
	push iy
	call _brelse
	pop af
	pop bc
ba_13:
	push bc
	push bc
	call	ixh_lh_p4
	push hl
	call _validblk
	pop af
	pop af
	pop bc
	call	ixh_ed_m2
	ld hl, #0xd8
	add hl, de
	ld a, (hl)
	inc hl
	or (hl)
	jp z, ba_corrupt
	ld a, (hl)
	dec hl
	ld e, a			; save high
	ld a, (hl)
	sub #1
	ld (hl), a
	inc hl
	ld a, e
	sbc a, #0
	ld (hl), a		; --s_tfree
	push bc
	ld a, #1
	push af
	inc sp
	push bc
	call	ixh_lh_p4
	push hl
	call _bread
	pop af
	pop af
	inc sp
	pop bc
	ld a, h
	or l
	jp z, ba_corrupt
	push bc			; newno
	push hl			; buf
	; zero 512 bytes with PUSH (2 bytes per 11 cycles), interrupts off
	di
	ld (ba_zsp), sp
	ld de, #0x200
	add hl, de
	ld sp, hl
	ld hl, #0
	ld b, #32
ba_zl:	push hl
	push hl
	push hl
	push hl
	push hl
	push hl
	push hl
	push hl
	djnz ba_zl
	ld sp, (ba_zsp)
	ld a, (_int_disabled)
	or a
	jr nz, ba_zd
	ei
ba_zd:	pop hl
	pop bc
	push bc
	push hl
	call _bawrite
	pop af
	pop hl			; hl = newno
	jp ba_out
ba_corrupt:
	ld hl, #ba_s
	call	ixh_p1_kputs
	call	ixh_lh_m2
	ld (hl), #1
	inc hl
	ld (hl), #0		; s_mounted = 1
ba_c2:
	ld hl, #0x1c		; ENOSPC
	ld (_udata + 0x0c), hl
	ld hl, #0
ba_out:
	jp	ixh_leave
ba_zsp:	.dw 0
ba_s:	.ascii "blk_alloc: corrupt"
	.db 10, 0

; void blk_free(uint16_t devno, blkno_t blk)
_blk_free::
	call ___sdcc_enter_ix
	ld a, 7 (ix)
	or 6 (ix)
	jp z, bf_out
	call	ixh_lh_p4
	push hl
	call _getdev
	pop af
	push hl			; -2(ix) = dev
	ld a, (hl)
	cp #0xc6
	jp nz, bf_out
	inc hl
	ld a, (hl)
	cp #0x31
	jp nz, bf_out
	call	ixh_lh_p6
	push hl
	call	ixh_lh_p4
	push hl
	call _validblk
	pop af
	pop af
	call	ixh_ed_m2
	ld hl, #6
	add hl, de
	ld a, (hl)
	cp #50
	jr nz, bf_09
	inc hl
	ld a, (hl)
	or a
	jr nz, bf_09
	ld a, #1
	push af
	inc sp
	call	ixh_lh_p6
	push hl
	call	ixh_lh_p4
	push hl
	call _bread
	pop af
	pop af
	inc sp
	ld a, h
	or l
	jr z, bf_bad
	push hl			; buf
	ld e, l
	ld d, h
	call	ixh_lh_m2
	ld bc, #6
	add hl, bc
	ld bc, #0x66
	ldir
	pop hl
	push hl
	call _bawrite
	pop af
	call	ixh_lh_m2
	ld bc, #6
	add hl, bc
	xor a
	ld (hl), a
	inc hl
	ld (hl), a		; s_nfree = 0
	jr bf_09
bf_bad:
	call	ixh_lh_m2
	ld (hl), #1
	inc hl
	ld (hl), #0
bf_09:
	call	ixh_lh_m2
	ld de, #0xd8
	add hl, de
	ld a, (hl)
	inc a
	ld (hl), a
	jr nz, bf_t
	inc hl
	inc (hl)
bf_t:
	call	ixh_lh_m2
	ld de, #6
	add hl, de
	ld c, (hl)
	inc hl
	ld b, (hl)		; bc = s_nfree
	ld e, c
	ld d, b
	inc de
	ld (hl), d
	dec hl
	ld (hl), e		; s_nfree++
	sla c
	rl b
	call	ixh_lh_m2
	ld de, #8
	add hl, de
	add hl, bc
	ld a, 6 (ix)
	ld (hl), a
	inc hl
	ld a, 7 (ix)
	ld (hl), a
bf_out:
	jp	ixh_leave

	.area _CODE
; uint16_t i_alloc(uint16_t devno)
; fs: +2 s_isize, +0x6c s_ninode, +0x6e s_inode[50], +0xda s_tinode
; locals: -2 dev, -4 k, -6 blk, -8 j, -10 buf, -12 di
_i_alloc::
	call ___sdcc_enter_ix
	ld hl, #-12
	add hl, sp
	ld sp, hl
	call	ixh_lh_p4
	push hl
	call _getdev
	pop af
	ld -2 (ix), l
	ld -1 (ix), h
	ld a, (hl)
	cp #0xc6
	jp nz, ia_corrupt
	inc hl
	ld a, (hl)
	cp #0x31
	jp nz, ia_corrupt
ia_again:
	call	ixh_ed_m2
	ld hl, #0x6c
	add hl, de
	ld c, (hl)
	inc hl
	ld b, (hl)
	ld a, b
	or c
	jp z, ia_scan
	ld hl, #0xda
	add hl, de
	ld a, (hl)
	inc hl
	or (hl)
	jp z, ia_corrupt
	dec bc
	ld hl, #0x6c
	add hl, de
	ld (hl), c
	inc hl
	ld (hl), b		; --s_ninode
	sla c
	rl b
	ld hl, #0x6e
	add hl, de
	add hl, bc
	ld c, (hl)
	inc hl
	ld b, (hl)		; bc = ino
	ld a, c
	sub #2
	ld a, b
	sbc a, #0
	jp c, ia_corrupt
	ld hl, #2
	add hl, de
	ld a, (hl)
	inc hl
	ld h, (hl)
	ld l, a
	dec hl
	dec hl
	add hl, hl
	add hl, hl
	add hl, hl
	ld a, c
	sub l
	ld a, b
	sbc a, h
	jp nc, ia_corrupt
	ld hl, #0xda
	add hl, de
	ld a, (hl)
	sub #1
	ld (hl), a
	inc hl
	ld a, (hl)
	sbc a, #0
	ld (hl), a		; --s_tinode
	ld l, c
	ld h, b
	jp ia_out
ia_scan:
	call _sync
	ld hl, #0
	ld -4 (ix), l
	ld -3 (ix), h		; k = 0
	ld -6 (ix), #2
	ld -5 (ix), #0		; blk = 2
ia_blk:
	call	ixh_ed_m2
	ld hl, #2
	add hl, de
	ld a, (hl)
	inc hl
	ld h, (hl)
	ld l, a			; hl = s_isize
	ld c, -6 (ix)
	ld b, -5 (ix)
	ld a, c
	sub l
	ld a, b
	sbc a, h
	jp nc, ia_done		; blk >= isize
	xor a
	push af
	inc sp
	push bc
	call	ixh_lh_p4
	push hl
	call _bread
	pop af
	pop af
	inc sp
	ld a, h
	or l
	jp z, ia_corrupt
	ld -10 (ix), l
	ld -9 (ix), h
	ld -12 (ix), l
	ld -11 (ix), h		; di = buf
	ld -8 (ix), #0		; j = 0
ia_j:
	call	ixh_lh_m12
	ld a, (hl)		; i_mode
	inc hl
	or (hl)
	inc hl
	or (hl)			; i_nlink
	inc hl
	or (hl)
	jr nz, ia_nx
	ld c, -6 (ix)
	ld b, -5 (ix)
	dec bc
	dec bc
	sla c
	rl b
	sla c
	rl b
	sla c
	rl b			; 8 * (blk - 2)
	ld a, c
	add a, -8 (ix)
	ld c, a
	jr nc, ia_c1
	inc b
ia_c1:
	call	ixh_ed_m2
	ld hl, #0x6e
	add hl, de
	call	ixh_ed_m4
	add hl, de
	add hl, de
	ld (hl), c
	inc hl
	ld (hl), b
	inc de
	ld -4 (ix), e
	ld -3 (ix), d		; ++k
ia_nx:
	ld a, -4 (ix)
	cp #50
	jr nz, ia_nk
	ld a, -3 (ix)
	or a
	jr nz, ia_nk
	call	ixh_lh_m10
	call	ixh_p1_brelse
	jp ia_done
ia_nk:
	call	ixh_lh_m12
	ld de, #64		; sizeof(struct dinode)
	add hl, de
	ld -12 (ix), l
	ld -11 (ix), h
	inc -8 (ix)
	ld a, -8 (ix)
	cp #8
	jp c, ia_j
	call	ixh_lh_m10
	call	ixh_p1_brelse
	inc -6 (ix)
	jp nz, ia_blk
	inc -5 (ix)
	jp ia_blk
ia_done:
	ld a, -4 (ix)
	or -3 (ix)
	jr nz, ia_have
	call	ixh_ed_m2
	ld hl, #0xda
	add hl, de
	ld a, (hl)
	inc hl
	or (hl)
	jp nz, ia_corrupt
	ld hl, #0x1c		; ENOSPC
	ld (_udata + 0x0c), hl
	ld hl, #0
	jp ia_out
ia_have:
	call	ixh_ed_m2
	ld hl, #0x6c
	add hl, de
	ld a, -4 (ix)
	ld (hl), a
	inc hl
	ld a, -3 (ix)
	ld (hl), a		; s_ninode = k
	jp ia_again
ia_corrupt:
	ld hl, #ia_s
	call	ixh_p1_kputs
	call	ixh_lh_m2
	ld (hl), #1
	inc hl
	ld (hl), #0		; s_mounted = 1
	ld hl, #0x1c
	ld (_udata + 0x0c), hl
	ld hl, #0
ia_out:
	jp	ixh_leave
ia_s:	.ascii "i_alloc: corrupt superblock"
	.db 10, 0

; void i_free(uint16_t devno, uint16_t ino)
_i_free::
	call ___sdcc_enter_ix
	call	ixh_lh_p4
	push hl
	call _getdev
	pop af
	ld c, l
	ld b, h			; bc = dev
	ld a, (hl)
	cp #0xc6
	jp nz, if_out
	inc hl
	ld a, (hl)
	cp #0x31
	jp nz, if_out
	ld a, 6 (ix)
	sub #2
	ld a, 7 (ix)
	sbc a, #0
	jr c, if_bad
	ld hl, #2
	add hl, bc
	ld a, (hl)
	inc hl
	ld h, (hl)
	ld l, a
	dec hl
	dec hl
	add hl, hl
	add hl, hl
	add hl, hl
	ld a, 6 (ix)
	sub l
	ld a, 7 (ix)
	sbc a, h
	jr c, if_ok
if_bad:
	push bc
	ld hl, #if_s
	call	ixh_p1_panic
	pop bc
if_ok:
	ld hl, #0xda
	add hl, bc
	ld a, (hl)
	inc a
	ld (hl), a
	jr nz, if_t
	inc hl
	inc (hl)		; ++s_tinode
if_t:
	ld hl, #0x6c
	add hl, bc
	ld e, (hl)
	inc hl
	ld d, (hl)
	dec hl			; hl = &s_ninode
	ld a, e
	sub #50
	ld a, d
	sbc a, #0
	jp nc, if_out		; table full: drop it
	push de
	inc de
	ld (hl), e
	inc hl
	ld (hl), d		; s_ninode++
	pop de
	sla e
	rl d
	ld hl, #0x6e
	add hl, bc
	add hl, de
	ld a, 6 (ix)
	ld (hl), a
	inc hl
	ld a, 7 (ix)
	ld (hl), a
if_out:
	jp	ixh_leave
if_s:	.ascii "i_free: bad ino"
	.db 0

	.area _CODE
; inoptr getinode(uint8 uindex): inode behind descriptor uindex, or NULL+EBADF
_getinode::
	ld hl, #2
	add hl, sp
	ld a, (hl)
	cp #10			; UFTSIZE
	jr nc, gi_bad
	ld e, a
	ld d, #0
	ld hl, #_udata + 0x7d	; u_files
	add hl, de
	ld a, (hl)
	cp #0xff
	jr z, gi_bad
	cp #0x20		; OFTSIZE
	jr c, gi_o1
	ld hl, #gi_s0
	call	ixh_p1_panic
gi_o1:
	ld l, a
	ld h, #0
	add hl, hl
	add hl, hl
	add hl, hl
	ld de, #_of_tab + 4	; o_inode
	add hl, de
	ld e, (hl)
	inc hl
	ld d, (hl)
	ld a, e
	sub #<(_i_tab)
	ld a, d
	sbc a, #>(_i_tab)
	jr c, gi_o2
	ld a, e
	sub #<(_i_tab + 0x05dc)
	ld a, d
	sbc a, #>(_i_tab + 0x05dc)
	jr c, gi_o3
gi_o2:
	push de
	ld hl, #gi_s1
	call	ixh_p1_panic
	pop de
gi_o3:
	ld l, e
	ld h, d
	ld a, (hl)
	cp #0x91
	jr nz, gi_mg
	inc hl
	ld a, (hl)
	cp #0x60
	jr z, gi_ok
gi_mg:
	push de
	push de
	call _magic
	pop af
	pop de
gi_ok:
	ex de, hl
	ret
gi_bad:
	ld hl, #9		; EBADF
	ld (_udata + 0x0c), hl
	ld hl, #0
	ret
gi_s0:	.ascii "getinode: bad desc table"
	.db 0
gi_s1:	.ascii "getinode: bad OFT"
	.db 0

; uint8 getperm(inoptr ino): rwx bits (0-7) for the current euid/egid
_getperm::
	ld hl, (_udata + 0x71)	; u_euid
	ld a, h
	or l
	jr nz, gp_1
	ld l, #7		; superuser
	ret
gp_1:
	call	ixh_sp2_ed
	push de
	pop iy
	ld c, 6 (iy)		; i_mode
	ld b, 7 (iy)
	ld hl, (_udata + 0x71)
	ld a, 10 (iy)		; i_uid
	cp l
	jr nz, gp_g
	ld a, 11 (iy)
	cp h
	jr nz, gp_g
	ld a, c			; mode >> 6
	rlca
	rlca
	and #3
	ld c, a
	ld a, b
	and #1
	add a, a
	add a, a
	or c
	and #7
	ld l, a
	ret
gp_g:
	ld hl, (_udata + 0x73)	; u_egid
	ld a, 12 (iy)		; i_gid
	cp l
	jr nz, gp_o
	ld a, 13 (iy)
	cp h
	jr nz, gp_o
	ld a, c			; mode >> 3
	rrca
	rrca
	rrca
	and #7
	ld l, a
	ret
gp_o:
	ld a, c
	and #7
	ld l, a
	ret

; void setftime(inoptr ino, uint8 flag)
_setftime::
	call ___sdcc_enter_ix
	call	ixh_cb_p4
	ld hl, #0x49
	add hl, bc
	bit 6, (hl)		; CRDONLY
	jr nz, sf_out
	ld e, 6 (ix)
	ld a, e
	cp #1
	jr nz, sf_1
	ld hl, #0x4a		; c_super
	add hl, bc
	ld a, (hl)
	ld hl, #_fs_tab + 2	; m_flags
	ld de, #0xe3
	or a
	jr z, sf_f
sf_l:
	add hl, de
	dec a
	jr nz, sf_l
sf_f:
	ld e, 6 (ix)
	bit 3, (hl)		; MS_NOATIME
	jr nz, sf_out
sf_1:
	ld hl, #0x49
	add hl, bc
	set 7, (hl)		; CDIRTY
	bit 0, e
	jr z, sf_m
	ld hl, #0x12
	add hl, bc
	push bc
	push de
	push hl
	call _rdtime32
	pop af
	pop de
	pop bc
sf_m:
	bit 1, e
	jr z, sf_c
	ld hl, #0x16
	add hl, bc
	push bc
	push de
	push hl
	call _rdtime32
	pop af
	pop de
	pop bc
sf_c:
	bit 2, e
	jr z, sf_out
	ld hl, #0x1a
	add hl, bc
	push hl
	call _rdtime32
	pop af
sf_out:
	jp	ixh_leave

	.area _CODE
; void corrupt_fs(uint16_t devno): mark the fs as corrupt
_corrupt_fs::
	call	ixh_sp2_ed
	push de
	call _fs_tab_get
	pop af
	ld de, #6
	add hl, de
	ld (hl), #1
	inc hl
	ld (hl), #0		; m_fs.s_mounted = 1
	ld hl, #cf_s
	call	ixh_p1_kputs
	ret
cf_s:	.ascii "filesystem corrupt."
	.db 10, 0

; void wr_inode(inoptr ino)
_wr_inode::
	call ___sdcc_enter_ix
	call	ixh_lh_p4
	ld a, (hl)
	cp #0x91
	jr nz, wi_mg
	inc hl
	ld a, (hl)
	cp #0x60
	jr z, wi_ok
wi_mg:
	call	ixh_lh_p4
	push hl
	call _magic
	pop af
wi_ok:
	call	ixh_lh_p4
	push hl
	call _bwritei
	pop af
	ld a, l
	or a
	call	ixh_lh_p4
	jr z, wi_clean
	inc hl
	inc hl
	ld e, (hl)
	inc hl
	ld d, (hl)		; c_dev
	push de
	call _corrupt_fs
	pop af
	jr wi_out
wi_clean:
	ld de, #0x49
	add hl, de
	res 7, (hl)		; ~CDIRTY
wi_out:
	jp	ixh_leave

; int f_trunc(inoptr ino): free all blocks, size = 0 (0 ok, -1 error)
_f_trunc::
	call	ixh_sp2_cb
	ld hl, #0
	push hl
	push bc
	call _f_trunc_blocks
	pop af
	pop af
	ld a, h
	or l
	jr z, ft_ok
	ld hl, #0xffff
	ret
ft_ok:
	call	ixh_sp2_ed
	ld hl, #0x0e
	add hl, de
	xor a
	ld (hl), a
	inc hl
	ld (hl), a
	inc hl
	ld (hl), a
	inc hl
	ld (hl), a		; i_size = 0
	ld hl, #0
	ret

; void validblk(uint16_t dev, blkno_t num)
_validblk::
	call	ixh_sp2_ed
	push de
	call _fs_tab_get
	pop af
	ld a, h
	or l
	jr z, vb_nm
	push hl
	pop iy
	ld a, 6 (iy)		; m_fs.s_mounted
	or 7 (iy)
	jr nz, vb_1
vb_nm:
	ld hl, #vb_s0
	call	ixh_p1_panic
	ret
vb_1:
	call	ixh_sp4_cb
	ld a, c
	sub 8 (iy)		; num < s_isize ?
	ld a, b
	sbc a, 9 (iy)
	jr c, vb_bad
	ld a, c
	sub 10 (iy)		; num < s_fsize ?
	ld a, b
	sbc a, 11 (iy)
	ret c
vb_bad:
	ld hl, #vb_s1
	call	ixh_p1_panic
	ret
vb_s0:	.ascii "validblk: not mounted"
	.db 0
vb_s1:	.ascii "validblk: invalid blk"
	.db 0

; void freeblk(uint16_t dev, blkno_t blk, uint8 level, uint16_t nblock)
; locals: -2 buf, -4 j
_freeblk::
	call ___sdcc_enter_ix
	ld hl, #-4
	add hl, sp
	ld sp, hl
	ld a, 7 (ix)
	or 6 (ix)
	jp z, fb_out
	ld a, 8 (ix)
	or a
	jp z, fb_free
	xor a
	push af
	inc sp
	call	ixh_lh_p6
	push hl
	call	ixh_lh_p4
	push hl
	call _bread
	pop af
	pop af
	inc sp
	ld a, h
	or l
	jr nz, fb_ok
	call	ixh_lh_p4
	push hl
	call _corrupt_fs
	pop af
	jp fb_out
fb_ok:
	ld -2 (ix), l
	ld -1 (ix), h
	ld -4 (ix), #0xff
	ld -3 (ix), #0
fb_loop:
	ld c, #0
	ld a, 10 (ix)		; nblock1 = nblock >> 8 (signed 8 bit)
	ld e, a
	rla
	sbc a, a
	ld d, a
	call	ixh_lh_m4
	or a
	sbc hl, de
	jr nz, fb_nb
	ld c, 9 (ix)
fb_nb:
	ld b, #0
	call	ixh_lh_m4
	add hl, hl
	call	ixh_ed_m2
	add hl, de
	ld e, (hl)
	inc hl
	ld d, (hl)		; bn[j]
	push bc			; nblock
	ld a, 8 (ix)
	dec a
	push af
	inc sp			; level - 1
	push de
	call	ixh_lh_p4
	push hl
	call _freeblk
	pop af
	pop af
	pop af
	inc sp
	call	ixh_lh_m4
	dec hl
	ld -4 (ix), l
	ld -3 (ix), h
	bit 7, h
	jr z, fb_loop
	call	ixh_lh_m2
	call	ixh_p1_brelse
fb_free:
	call	ixh_lh_p6
	push hl
	call	ixh_lh_p4
	push hl
	call _blk_free
	pop af
	pop af
fb_out:
	jp	ixh_leave

; int f_trunc_blocks(inoptr ino, uint16_t nblock)
; locals: -2 map1, -4 map2, -5 j
_f_trunc_blocks::
	call ___sdcc_enter_ix
	ld hl, #-6
	add hl, sp
	ld sp, hl
	ld hl, #0
	ld -2 (ix), l
	ld -1 (ix), h
	ld -4 (ix), l
	ld -3 (ix), h
	call	ixh_lh_p4
	ld de, #0x49
	add hl, de
	bit 6, (hl)		; CRDONLY
	jr z, tb_1
	ld hl, #0x1e		; EROFS
	ld (_udata + 0x0c), hl
	ld hl, #0xffff
	jp tb_out
tb_1:
	call	ixh_ed_p6
	ld hl, #17
	or a
	sbc hl, de
	jr nc, tb_dev		; nblock <= 17
	ld hl, #273
	or a
	sbc hl, de
	jr c, tb_big		; nblock > 273
	ld a, e			; map1 = (nblock - 18) << 8
	sub #18
	ld -1 (ix), a
	jr tb_dev
tb_big:
	ld hl, #-273
	add hl, de
	ld -4 (ix), l
	ld -3 (ix), h		; map2 = nblock - 273
tb_dev:
	call	ixh_lh_p4
	ld de, #0x44		; i_addr[19]
	add hl, de
	ld c, (hl)
	inc hl
	ld b, (hl)
	call	ixh_lh_m4
	push hl			; map2
	ld a, #2
	push af
	inc sp
	push bc
	call	ixh_lh_p4
	inc hl
	inc hl
	ld e, (hl)
	inc hl
	ld d, (hl)
	push de		; c_dev
	call _freeblk
	pop af
	pop af
	pop af
	inc sp
	ld a, -3 (ix)
	or -4 (ix)
	jr z, tb_2
	call	ixh_lh_p4
	ld de, #0x44
	add hl, de
	xor a
	ld (hl), a
	inc hl
	ld (hl), a
tb_2:
	call	ixh_lh_p4
	ld de, #0x42		; i_addr[18]
	add hl, de
	ld c, (hl)
	inc hl
	ld b, (hl)
	call	ixh_lh_m2
	push hl			; map1
	ld a, #1
	push af
	inc sp
	push bc
	call	ixh_lh_p4
	inc hl
	inc hl
	ld e, (hl)
	inc hl
	ld d, (hl)
	push de		; c_dev
	call _freeblk
	pop af
	pop af
	pop af
	inc sp
	ld a, -1 (ix)
	or -2 (ix)
	or -3 (ix)
	or -4 (ix)
	jr nz, tb_3
	call	ixh_lh_p4
	ld de, #0x42
	add hl, de
	xor a
	ld (hl), a
	inc hl
	ld (hl), a
tb_3:
	ld -5 (ix), #17		; j
tb_j:
	ld a, -5 (ix)
	bit 7, a
	jr nz, tb_end
	ld l, a
	ld h, #0
	call	ixh_ed_p6
	or a
	sbc hl, de		; j >= nblock ?
	jr c, tb_end
	ld l, -5 (ix)
	ld h, #0
	add hl, hl
	ld e, 4 (ix)
	ld d, 5 (ix)
	add hl, de
	ld de, #0x1e
	add hl, de		; &i_addr[j]
	ld c, (hl)
	inc hl
	ld b, (hl)
	xor a
	ld (hl), a
	dec hl
	ld (hl), a		; i_addr[j] = 0
	ld hl, #0
	push hl			; nblock = 0
	xor a
	push af
	inc sp			; level 0
	push bc
	call	ixh_lh_p4
	inc hl
	inc hl
	ld e, (hl)
	inc hl
	ld d, (hl)
	push de		; c_dev
	call _freeblk
	pop af
	pop af
	pop af
	inc sp
	dec -5 (ix)
	jr tb_j
tb_end:
	call	ixh_lh_p4
	ld de, #0x49
	add hl, de
	set 7, (hl)		; CDIRTY
	ld hl, #0
tb_out:
	jp	ixh_leave

; arg_t unlinki(inoptr ino, inoptr pino, uint8_t *fname)
_unlinki::
	call ___sdcc_enter_ix
	call	ixh_lh_p4
	call	ixh_p1_getmode
	ld a, l
	sub #0x40
	jr nz, ul_1
	ld hl, #21		; EISDIR
	ld (_udata + 0x0c), hl
	ld hl, #0xffff
	pop ix
	ret
ul_1:
	ld hl, #0
	push hl
	ld hl, #ul_e
	push hl
	call	ixh_lh_p8
	push hl
	call	ixh_lh_p6
	push hl
	call _ch_link
	pop af
	pop af
	pop af
	pop af
	bit 0, l
	jr nz, ul_2
	ld hl, #0xffff
	pop ix
	ret
ul_2:
	call	ixh_lh_p4
	ld de, #8
	add hl, de		; &i_nlink
	ld e, (hl)
	inc hl
	ld d, (hl)		; de = old nlink
	ld a, d
	or e
	push af			; Z = old nlink was 0
	dec de
	ld (hl), d
	dec hl
	ld (hl), e
	pop af
	jr nz, ul_3
	inc de
	inc de
	ld (hl), e
	inc hl
	ld (hl), d
	call	ixh_lh_p4
	push hl
	ld hl, #ul_s
	push hl
	call _kprintf
	pop af
	pop af
ul_3:
	ld a, #4
	push af
	inc sp
	call	ixh_lh_p4
	push hl
	call _setftime
	pop af
	inc sp
	ld hl, #0
	pop ix
	ret
ul_e:	.db 0
ul_s:	.ascii "_unlink: bad nlink"
	.db 10, 0

; struct mount *fs_tab_get(uint16_t dev)
_fs_tab_get::
	call	ixh_sp2_ed
	ld hl, #_fs_tab
	ld b, #4
fg_l:
	ld a, (hl)
	cp e
	jr nz, fg_n
	inc hl
	ld a, (hl)
	dec hl
	cp d
	ret z
fg_n:
	push de
	ld de, #0xe3
	add hl, de
	pop de
	djnz fg_l
	ld hl, #0
	ret

; void deflock(struct oft *ofptr)
_deflock::
	pop de
	pop hl
	push hl
	push de
	push hl
	pop iy
	bit 7, 6 (iy)		; o_access & O_FLOCK
	ret z
	ld l, 4 (iy)
	ld h, 5 (iy)
	ld de, #0x49
	add hl, de		; &c_flags
	ld a, (hl)
	ld c, a
	and #0x0f
	cp #0x0f
	jr nz, df_d
	xor a
	jr df_s
df_d:
	dec a
df_s:
	ld b, a
	ld a, c
	and #0xf0
	or b
	ld (hl), a
	call	ixh_p1_wakeup
	ret

; void oft_deref(uint_fast8_t of)
_oft_deref::
	pop de
	pop hl
	push hl
	push de
	call	ixh_oft
	push hl
	pop iy
	dec 7 (iy)
	ret nz
	ld a, 4 (iy)
	or 5 (iy)
	ret z
	push iy
	push iy
	call _deflock
	pop af
	pop iy
	push iy
	ld l, 4 (iy)
	ld h, 5 (iy)
	call	ixh_p1_i_deref
	pop iy
	xor a
	ld 4 (iy), a
	ld 5 (iy), a
	ret

; inoptr newfile(inoptr pino, uint8_t *name)   local: -2 nindex
_newfile::
	call ___sdcc_enter_ix
	push af
	ld a, 5 (ix)
	or 4 (ix)
	jr nz, nf_1
	ld hl, #6		; ENXIO
	jr nf_err
nf_1:
	call	ixh_lh_p4
	push hl
	call _getperm
	pop af
	bit 1, l
	jr nz, nf_2
	ld hl, #1		; EPERM
	jr nf_err
nf_2:
	call	ixh_lh_p4
	ld de, #0x49
	add hl, de
	bit 6, (hl)		; CRDONLY
	jr z, nf_3
	ld hl, #0x1e		; EROFS
	jr nf_err
nf_3:
	call	ixh_lh_p4
	inc hl
	inc hl
	ld c, (hl)
	inc hl
	ld b, (hl)		; pino->c_dev
	ld hl, #0
	push hl
	push bc
	call _i_open
	pop af
	pop af
	ld a, h
	or l
	jr nz, nf_4
	ld hl, #0x17		; ENFILE
nf_err:
	ld (_udata + 0x0c), hl
	jr nf_fail
nf_4:
	ld -2 (ix), l
	ld -1 (ix), h
	push hl
	pop iy
	ld hl, (_udata + 0x71)	; u_euid
	ld 10 (iy), l
	ld 11 (iy), h
	ld hl, (_udata + 0x73)	; u_egid
	ld 12 (iy), l
	ld 13 (iy), h
	ld 6 (iy), #0		; i_mode = F_REG (0x8000)
	ld 7 (iy), #0x80
	ld 8 (iy), #1		; i_nlink = 1
	ld 9 (iy), #0
	xor a
	ld 14 (iy), a		; i_size = 0
	ld 15 (iy), a
	ld 16 (iy), a
	ld 17 (iy), a
	push iy
	pop hl
	ld de, #0x1e
	add hl, de
	ld b, #40		; i_addr[20] = 0
nf_z:
	ld (hl), a
	inc hl
	djnz nf_z
	call	ixh_lh_m2
	call	ixh_p1_wr_inode
	call	ixh_lh_m2
	push hl
	call	ixh_lh_p6
	push hl
	ld hl, #nf_e
	push hl
	call	ixh_lh_p4
	push hl
	call _ch_link
	pop af
	pop af
	pop af
	pop af
	bit 0, l
	jr nz, nf_ok
	call	ixh_lh_m2
	call	ixh_p1_i_deref
nf_fail:
	call	ixh_lh_p4
	call	ixh_p1_i_deref
	ld hl, #0
	jr nf_out
nf_ok:
	call	ixh_lh_p4
	call	ixh_p1_i_deref
	call	ixh_lh_m2
nf_out:
	jp	ixh_leave
nf_e:	.db 0

; fsptr getdev(uint16_t dev)   local: 8 bytes time_t
_getdev::
	call ___sdcc_enter_ix
	ld hl, #-8
	add hl, sp
	ld sp, hl
	call	ixh_lh_p4
	push hl
	call _fs_tab_get
	pop af
	ld a, h
	or l
	jr z, gd_bad
	ld c, l
	ld b, h
	push hl
	pop iy
	ld a, 6 (iy)		; s_mounted
	or 7 (iy)
	jr nz, gd_ok
gd_bad:
	ld hl, #gd_s
	call	ixh_p1_panic
	ld hl, #0
	jr gd_out
gd_ok:
	bit 0, 2 (iy)		; MS_RDONLY
	jr nz, gd_ret
	push bc
	ld hl, #2		; &t (after pushed bc)
	add hl, sp
	push hl
	call _rdtime
	pop af
	pop bc
	push bc
	pop iy
	ld hl, #0
	add hl, sp
	ld e, c
	ld d, b
	ld a, (hl)		; t.low[0..3] -> s_time (m+0xda)
	ld 0xda (iy), a
	inc hl
	ld a, (hl)
	ld 0xdb (iy), a
	inc hl
	ld a, (hl)
	ld 0xdc (iy), a
	inc hl
	ld a, (hl)
	ld 0xdd (iy), a
	inc hl
	ld a, (hl)		; t.high[0] -> s_timeh (m+0xd9)
	ld 0xd9 (iy), a
	ld 0xd8 (iy), #1	; s_fmod = FMOD_DIRTY
gd_ret:
	ld hl, #6
	add hl, bc
gd_out:
	jp	ixh_leave
gd_s:	.ascii "getdev bad dev"
	.db 0
