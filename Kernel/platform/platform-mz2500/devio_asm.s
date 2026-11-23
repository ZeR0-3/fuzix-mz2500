;
;	Device I/O layer (devio.c), hand written.
;
;	dev_tab entry = 5 words: open +0, close +2, read +4, write +6, ioctl +8.
;	dev = major << 8 | minor. Driver calls push minor as a byte last.
;	struct s_queue: base +0, head +2, tail +4, size +6, count +8, wakeup +10.
;	struct buf: data 0..0x1ff, bf_dev +0x200, bf_blk +0x202.
;
	.module devio_asm

	.globl _validchk, _bdread, _bdwrite, _cdread, _cdwrite
	.globl _d_open, _d_close, _d_ioctl, _d_flush, _d_blkoff
	.globl _nxio_open, _no_open, _no_close, _no_rdwr, _no_ioctl
	.globl _clrq, _fullq, _psleep_flags_io, _psleep_flags
	.globl _udata, _dev_tab, _kputs, _kputchar, _panic, _bdrop
	.globl _psleep, _chksigs, ___hard_di, ___hard_irqrestore, ___sdcc_call_hl

NMAJOR	=	5
BLKFLSBUF =	0x4103

	.area _CODE

;	HL = dev_tab[D].word at offset A; preserves BC DE
dt_fn:
	push	bc
	ld	h, #0
	ld	l, d
	ld	b, h
	ld	c, l
	add	hl, hl
	add	hl, hl
	add	hl, bc
	add	hl, hl
	ld	bc, #_dev_tab
	add	hl, bc
	ld	c, a
	ld	b, #0
	add	hl, bc
	ld	a, (hl)
	inc	hl
	ld	h, (hl)
	ld	l, a
	pop	bc
	ret

;	validchk(dev, name): panic if the major is out of range
_validchk::
	ld	hl, #3
	add	hl, sp
	ld	a, (hl)
	cp	#NMAJOR
	ret	c
	inc	hl
	ld	c, (hl)
	inc	hl
	ld	b, (hl)
	push	bc
	call	_kputs
	pop	af
	ld	a, #0x3a
	push	af
	inc	sp
	call	_kputchar
	inc	sp
	ld	hl, #s_invdev
	call	ixh_p1_panic
	ret
s_invdev:
	.ascii	"invalid dev"
	.db	0

;	bdread(bp) / bdwrite(bp): block device transfer through the driver
_bdread::
	ld	hl, #s_bdread
	ld	a, #4
	jr	bdrw
_bdwrite::
	ld	hl, #s_bdwrite
	ld	a, #6
bdrw:
	push	af
	ex	de, hl
	call	ixh_sp4_cb
	ld	hl, #0x200
	add	hl, bc
	ld	a, (hl)
	inc	hl
	ld	h, (hl)
	ld	l, a
	push	hl
	push	bc
	push	de
	push	hl
	call	_validchk
	pop	af
	pop	af
;	bdsetup(bp)
	pop	bc
	ld	(_udata + 0x6a), bc
	ld	hl, #0x202
	add	hl, bc
	ld	a, (hl)
	inc	hl
	ld	h, (hl)
	ld	l, a
	ld	(_udata + 0x91), hl
	ld	hl, #0
	ld	(_udata + 0x93), hl
	inc	l
	ld	(_udata + 0x95), hl
	ld	(_udata + 0x97), bc
	pop	de
	pop	af
	call	dt_fn
	ld	bc, #0
	push	bc
	ld	a, e
	push	af
	inc	sp
	call	___sdcc_call_hl
	pop	af
	inc	sp
	ret
s_bdread:
	.ascii	"bdread"
	.db	0
s_bdwrite:
	.ascii	"bdwrite"
	.db	0

;	cdread(dev, flag) / cdwrite(dev, flag)
_cdread::
	ld	hl, #s_cdread
	ld	a, #4
	jr	cdrw
_cdwrite::
	ld	hl, #s_cdwrite
	ld	a, #6
cdrw:
	push	af
	push	hl
	ld	hl, #6
	add	hl, sp
	ld	e, (hl)
	inc	hl
	ld	d, (hl)
	push	de
	call	_validchk
	pop	af
	pop	af
	call	ixh_sp4_ed
	inc	hl
	ld	c, (hl)
	pop	af
	call	dt_fn
	ld	a, c
	push	af
	inc	sp
	ld	a, #1
	push	af
	inc	sp
	ld	a, e
	push	af
	inc	sp
	call	___sdcc_call_hl
	pop	af
	inc	sp
	ret
s_cdread:
	.ascii	"cdread"
	.db	0
s_cdwrite:
	.ascii	"cdwrite"
	.db	0

;	d_open(dev, flag)
_d_open::
	call	ixh_sp2_ed
	inc	hl
	ld	c, (hl)
	ld	a, d
	cp	#NMAJOR
	jr	nc, d_enxio
	ld	b, #0
	push	bc
	xor	a
	call	dt_fn
	ld	a, e
	push	af
	inc	sp
	call	___sdcc_call_hl
	pop	af
	inc	sp
	ret
d_enxio:
	ld	hl, #6
	ld	(_udata + 0x0c), hl
	ld	hl, #0xffff
	ret

;	d_close(dev)
_d_close::
	ld	hl, #s_dclose
	push	hl
	call	ixh_sp4_ed
	push	de
	call	_validchk
	call	_bdrop
	pop	af
	pop	af
	call	ixh_sp2_ed
	ld	a, #2
	call	dt_fn
	ld	a, e
	push	af
	inc	sp
	call	___sdcc_call_hl
	inc	sp
	ret
s_dclose:
	.ascii	"d_close"
	.db	0

;	d_ioctl(dev, request, data)
_d_ioctl::
	call	ixh_sp2_ed
	ld	a, d
	cp	#NMAJOR
	jr	c, di_ok
	jp	d_enxio
di_ok:
	call	ixh_sp4_cb
	inc	hl
	ld	a, (hl)
	inc	hl
	ld	h, (hl)
	ld	l, a
	push	hl
	push	bc
	ld	a, #8
	call	dt_fn
	ld	a, e
	push	af
	inc	sp
	call	___sdcc_call_hl
	pop	af
	pop	af
	inc	sp
	ld	a, h
	and	l
	inc	a
	ret	nz
	ld	de, (_udata + 0x0c)
	ld	a, d
	or	e
	ret	nz
	ld	de, #0x19
	ld	(_udata + 0x0c), de
	ret

;	d_flush(dev): BLKFLSBUF, "no such ioctl" is not an error
_d_flush::
	call	ixh_sp2_ed
	ld	hl, #0
	push	hl
	ld	hl, #BLKFLSBUF
	push	hl
	push	de
	call	_d_ioctl
	pop	af
	pop	af
	pop	af
	ld	a, h
	or	l
	ret	z
	ld	de, (_udata + 0x0c)
	ld	a, e
	sub	#0x19
	or	d
	ret	nz
	ld	hl, #0
	ld	(_udata + 0x0c), hl
	ret

;	d_blkoff(shift): u_block = offset >> shift, u_nblock, u_dptr
_d_blkoff::
	ld	hl, #2
	add	hl, sp
	ld	b, (hl)
	ld	hl, #1
	ld	c, b
dbk_m:
	add	hl, hl
	djnz	dbk_m
	dec	hl
	push	hl
	ld	b, c
	ld	hl, (_udata + 0x68)
	ld	de, (_udata + 0x66)
dbk_s:
	srl	h
	rr	l
	rr	d
	rr	e
	djnz	dbk_s
	ld	(_udata + 0x91), de
	pop	de
	ld	hl, (_udata + 0x66)
	ld	a, l
	and	e
	ld	l, a
	ld	a, h
	and	d
	or	l
	jr	z, dbk_ok
	ld	hl, #5
	ld	(_udata + 0x0c), hl
	ld	hl, #0xffff
	ret
dbk_ok:
	ld	hl, (_udata + 100)
	add	hl, de
	ld	b, c
dbk_n:
	srl	h
	rr	l
	djnz	dbk_n
	ld	(_udata + 0x95), hl
	ld	hl, (_udata + 98)
	ld	(_udata + 0x97), hl
	ld	hl, #0
	ret

;	default device handlers
_nxio_open::
	ld	hl, #6
	jr	dd_err
_no_open::
_no_close::
	ld	hl, #0
	ret
_no_rdwr::
	ld	hl, #0x16
	jr	dd_err
_no_ioctl::
	ld	hl, #0x19
dd_err:
	ld	(_udata + 0x0c), hl
	ld	hl, #0xffff
	ret

;	queues
_clrq::
	call	ixh_sp2_cb
	push	bc
	call	___hard_di
	pop	bc
	push	hl
	ld	l, c
	ld	h, b
	ld	e, (hl)
	inc	hl
	ld	d, (hl)
	inc	hl
	ld	(hl), e
	inc	hl
	ld	(hl), d
	inc	hl
	ld	(hl), e
	inc	hl
	ld	(hl), d
	inc	hl
	inc	hl
	inc	hl
	xor	a
	ld	(hl), a
	inc	hl
	ld	(hl), a
	call	___hard_irqrestore
	pop	af
	ret

;	fullq(q): count > wakeup
_fullq::
	call	ixh_sp2_ed
	ex	de, hl
	ld	de, #8
	add	hl, de
	ld	e, (hl)
	inc	hl
	ld	d, (hl)
	inc	hl
	ld	c, (hl)
	inc	hl
	ld	b, (hl)
	ld	a, c
	sub	e
	ld	a, b
	sbc	a, d
	ld	a, #0
	rla
	ld	l, a
	ret

;	psleep_flags_io(p, flags) / psleep_flags(p, flags)
_psleep_flags_io::
	ld	hl, #4
	add	hl, sp
	bit	4, (hl)
	jr	z, pio_sl
	ld	hl, (_udata + 0x99)
	ld	a, h
	or	l
	jr	nz, pio_m1
	ld	hl, #0xffff
	ld	(_udata + 0x99), hl
	ld	hl, #0x0b
	ld	(_udata + 0x0c), hl
pio_m1:
	ld	hl, #0xffff
	ret
pio_sl:
	call	psl_sleep
	ret	z
	ld	hl, (_udata + 0x99)
	ld	a, h
	or	l
	jr	nz, pio_m1
	ld	hl, #0xffff
	ld	(_udata + 0x99), hl
	ld	hl, #4
	ld	(_udata + 0x0c), hl
	jr	pio_m1

_psleep_flags::
	ld	hl, #4
	add	hl, sp
	bit	4, (hl)
	jr	z, pf_sl
	ld	hl, #0x0b
	jp	dd_err
pf_sl:
	call	psl_sleep
	ret	z
	ld	hl, #4
	jp	dd_err

;	psleep(p); chksigs: returns Z with HL=0 if undisturbed, else NZ
psl_sleep:
	call	ixh_sp4_ed
	push	de
	call	_psleep
	pop	af
	call	_chksigs
	ld	a, l
	or	a
	ld	hl, #0
	ret
