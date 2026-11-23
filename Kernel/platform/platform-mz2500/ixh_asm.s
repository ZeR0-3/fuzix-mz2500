; ixh_asm.s - shared helpers: load a 16-bit IX-relative local into a register pair
	.module ixh_asm
	.area _CODE
	.globl ixh_cb_m4
ixh_cb_m4:
	ld	c, -4 (ix)
	ld	b, -3 (ix)
	ret
	.globl ixh_cb_p4
ixh_cb_p4:
	ld	c, 4 (ix)
	ld	b, 5 (ix)
	ret
	.globl ixh_ed_m6
ixh_ed_m6:
	ld	e, -6 (ix)
	ld	d, -5 (ix)
	ret
	.globl ixh_ed_m4
ixh_ed_m4:
	ld	e, -4 (ix)
	ld	d, -3 (ix)
	ret
	.globl ixh_ed_m2
ixh_ed_m2:
	ld	e, -2 (ix)
	ld	d, -1 (ix)
	ret
	.globl ixh_ed_p6
ixh_ed_p6:
	ld	e, 6 (ix)
	ld	d, 7 (ix)
	ret
	.globl ixh_lh_m12
ixh_lh_m12:
	ld	l, -12 (ix)
	ld	h, -11 (ix)
	ret
	.globl ixh_lh_m10
ixh_lh_m10:
	ld	l, -10 (ix)
	ld	h, -9 (ix)
	ret
	.globl ixh_lh_m8
ixh_lh_m8:
	ld	l, -8 (ix)
	ld	h, -7 (ix)
	ret
	.globl ixh_lh_m7
ixh_lh_m7:
	ld	l, -7 (ix)
	ld	h, -6 (ix)
	ret
	.globl ixh_lh_m6
ixh_lh_m6:
	ld	l, -6 (ix)
	ld	h, -5 (ix)
	ret
	.globl ixh_lh_m5
ixh_lh_m5:
	ld	l, -5 (ix)
	ld	h, -4 (ix)
	ret
	.globl ixh_lh_m4
ixh_lh_m4:
	ld	l, -4 (ix)
	ld	h, -3 (ix)
	ret
	.globl ixh_lh_m2
ixh_lh_m2:
	ld	l, -2 (ix)
	ld	h, -1 (ix)
	ret
	.globl ixh_lh_p4
ixh_lh_p4:
	ld	l, 4 (ix)
	ld	h, 5 (ix)
	ret
	.globl ixh_lh_p6
ixh_lh_p6:
	ld	l, 6 (ix)
	ld	h, 7 (ix)
	ret
	.globl ixh_lh_p7
ixh_lh_p7:
	ld	l, 7 (ix)
	ld	h, 8 (ix)
	ret
	.globl ixh_lh_p8
ixh_lh_p8:
	ld	l, 8 (ix)
	ld	h, 9 (ix)
	ret
	.globl ixh_leave
ixh_leave:
	ld	sp, ix
	pop	ix
	ret
	.globl ixh_p1_i_deref
ixh_p1_i_deref:
	push	hl
	call	_i_deref
	pop	af
	ret
	.globl ixh_p1_getmode
ixh_p1_getmode:
	push	hl
	call	_getmode
	pop	af
	ret
	.globl ixh_p1_kputs
ixh_p1_kputs:
	push	hl
	call	_kputs
	pop	af
	ret
	.globl ixh_p1_panic
ixh_p1_panic:
	push	hl
	call	_panic
	pop	af
	ret
	.globl ixh_p1_wakeup
ixh_p1_wakeup:
	push	hl
	call	_wakeup
	pop	af
	ret
	.globl ixh_p1_wr_inode
ixh_p1_wr_inode:
	push	hl
	call	_wr_inode
	pop	af
	ret
	.globl ixh_p1_brelse
ixh_p1_brelse:
	push	hl
	call	_brelse
	pop	af
	ret
	.globl ixh_p1___hard_irqrestore
ixh_p1___hard_irqrestore:
	push	hl
	call	___hard_irqrestore
	pop	af
	ret
	.globl ixh_sp2_cb
ixh_sp2_cb:
	ld	hl, #4
	add	hl, sp
	ld	c, (hl)
	inc	hl
	ld	b, (hl)
	ret
	.globl ixh_sp2_ed
ixh_sp2_ed:
	ld	hl, #4
	add	hl, sp
	ld	e, (hl)
	inc	hl
	ld	d, (hl)
	ret
	.globl ixh_sp4_cb
ixh_sp4_cb:
	ld	hl, #6
	add	hl, sp
	ld	c, (hl)
	inc	hl
	ld	b, (hl)
	ret
	.globl ixh_sp4_ed
ixh_sp4_ed:
	ld	hl, #6
	add	hl, sp
	ld	e, (hl)
	inc	hl
	ld	d, (hl)
	ret
	.globl ixh_oft
ixh_oft:
	ld	h, #0
	add	hl, hl
	add	hl, hl
	add	hl, hl
	ld	de, #_of_tab
	add	hl, de
	ret
	.globl ixh_getinode_argn
ixh_getinode_argn:
	ld	a, (_udata + 0x12)
	push	af
	inc	sp
	call	_getinode
	inc	sp
	ret
