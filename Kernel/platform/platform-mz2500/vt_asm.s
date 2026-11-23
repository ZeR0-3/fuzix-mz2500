;
;	Mini VT52 terminal emulation (vt.c), hand written.  40 x 25.
;
;	Hooks provided by the video driver (SDCC calling convention, byte
;	arguments pushed y first-lowest):
;	  plot_char(y, x, c16)  clear_lines(y, n)  clear_across(y, x, n16)
;	  cursor_on(y, x)  cursor_off()  cursor_disable()
;	  scroll_up() scroll_down() do_beep() vtattr_notify()
;
;	Internal convention: A = character; charout/escout/vo_char clobber
;	everything.
;
	.module vt_asm

	.globl _vtattr, _vtink, _vtpaper, _vt_cursor_off, _vt_cursor_on
	.globl _vtoutput, _vt_ioctl, _vt_inproc, _vtinit
	.globl _vtattr_notify, _do_beep, _plot_char, _scroll_down, _scroll_up
	.globl _cursor_disable, _cursor_on, _cursor_off, _clear_across
	.globl _clear_lines, _tty_inproc, _tty_ioctl, _vtattr_cap
	.globl ___hard_di, ___hard_irqrestore

VT_RIGHT	=	39
VT_BOTTOM	=	24

	.area _VIDEO

cursor_fix:
	ld	hl, #cursorx
	bit	7, (hl)
	jr	z, cf1
	ld	(hl), #VT_RIGHT
	ld	hl, #cursory
	dec	(hl)
cf1:
	ld	hl, #cursory
	bit	7, (hl)
	jr	z, cf2
	ld	(hl), #0
cf2:
	ld	a, (cursorx)
	cp	#VT_RIGHT + 1
	jr	c, cf3
	xor	a
	ld	(cursorx), a
	ld	hl, #cursory
	inc	(hl)
cf3:
	ld	a, (cursory)
	cp	#VT_BOTTOM + 1
	ret	c
	call	_scroll_up
	ld	de, #(1 << 8) | VT_BOTTOM
	push	de
	call	_clear_lines
	pop	af
	ld	hl, #cursory
	dec	(hl)
	ret

charout:
	cp	#0x1c
	jr	nc, co_plot
	cp	#7
	jr	nz, co1
	jp	_do_beep
co1:
	cp	#8
	jr	nz, co2
	ld	hl, #cursorx
	dec	(hl)
	jr	cursor_fix
co2:
	cp	#9
	jr	nz, co3
co_tab:
	ld	a, #0x20
	call	charout
	ld	a, (cursorx)
	and	#7
	jr	z, cursor_fix
	jr	co_tab
co3:
	cp	#10
	jr	nz, co4
	ld	hl, #cursory
	inc	(hl)
	jr	cursor_fix
co4:
	cp	#13
	jr	nz, co5
	xor	a
	ld	(cursorx), a
	ret
co5:
	cp	#0x1b
	jr	nz, co_plot
	ld	a, #1
	ld	(vtmode), a
	ret
co_plot:
	ld	c, a
	ld	b, #0
	push	bc
	ld	a, (cursorx)
	ld	h, a
	ld	a, (cursory)
	ld	l, a
	push	hl
	call	_plot_char
	pop	af
	pop	af
	ld	hl, #cursorx
	inc	(hl)
	jp	cursor_fix

;	clear from the cursor to the end of the line
clr_eol:
	ld	a, (cursorx)
	ld	c, a
	ld	a, #VT_RIGHT + 1
	sub	c
	ld	l, a
	ld	h, #0
	push	hl
	ld	h, c
	ld	a, (cursory)
	ld	l, a
	push	hl
	call	_clear_across
	pop	af
	pop	af
	ret

;	escape sequences: A = char, returns the next vtmode in A
escout:
	ld	hl, #cursory
	cp	#'A'
	jr	nz, es1
	ld	a, (hl)
	or	a
	jr	z, es_0
	dec	(hl)
	jr	es_0
es1:
	cp	#'B'
	jr	nz, es2
	ld	a, (hl)
	cp	#VT_BOTTOM
	jp	p, es_0
	inc	(hl)
	jr	es_0
es2:
	ld	hl, #cursorx
	cp	#'C'
	jr	nz, es3
	ld	a, (hl)
	cp	#VT_RIGHT
	jp	p, es_0
	inc	(hl)
	jr	es_0
es3:
	cp	#'D'
	jr	nz, es4
	ld	a, (hl)
	or	a
	jr	z, es_0
	dec	(hl)
	jr	es_0
es4:
	cp	#'E'
	jr	nz, es5
	ld	de, #((VT_BOTTOM + 1) << 8)
es_cl:
	push	de
	call	_clear_lines
	pop	af
es_0:
	xor	a
	ret
es5:
	cp	#'H'
	jr	nz, es6
	xor	a
	ld	(cursorx), a
	ld	(cursory), a
	ret
es6:
	cp	#'I'
	jr	nz, es7
	ld	a, (cursory)
	or	a
	jr	z, es6a
	dec	a
	ld	(cursory), a
	jr	es_0
es6a:
	call	_scroll_down
	ld	de, #0x0100
	jr	es_cl
es7:
	cp	#'J'
	jr	nz, es8
	call	clr_eol
	ld	a, (cursory)
	ld	c, a
	inc	a
	ld	e, a
	ld	a, #VT_BOTTOM
	sub	c
	ld	d, a
	jr	es_cl
es8:
	cp	#'K'
	jr	nz, es9
	call	clr_eol
	jr	es_0
es9:
	cp	#'e'
	jr	nz, es10
	xor	a
	ld	(cursorhide), a
	ret
es10:
	cp	#'f'
	jr	nz, es11
	ld	a, #1
	ld	(cursorhide), a
	call	_cursor_disable
	jr	es_0
es11:
	ld	b, #2
	cp	#'Y'
	jr	z, es_r
	inc	b
	inc	b
	cp	#'a'
	jr	z, es_r
	inc	b
	cp	#'b'
	jr	z, es_r
	inc	b
	cp	#'c'
	jr	z, es_r
	xor	a
	ret
es_r:
	ld	a, b
	ret

_vt_cursor_off::
	ld	a, (cursorhide)
	or	a
	ret	nz
	jp	_cursor_off

_vt_cursor_on::
	ld	a, (cursorhide)
	or	a
	ret	nz
	ld	a, (cursorx)
	ld	h, a
	ld	a, (cursory)
	ld	l, a
	push	hl
	call	_cursor_on
	pop	af
	ret

;	one character through the state machine (A = char)
vo_char:
	ld	b, a
	ld	a, (vtmode)
	or	a
	jr	nz, vc1
	ld	a, b
	jp	charout
vc1:
	dec	a
	jr	nz, vc2
	ld	a, b
	call	escout
	ld	(vtmode), a
	ret
vc2:
	dec	a
	jr	nz, vc3
	ld	a, b
	sub	#0x20
	ld	(ncursory), a
	ld	a, #3
	ld	(vtmode), a
	ret
vc3:
	dec	a
	jr	nz, vc4
	ld	a, (ncursory)
	cp	#VT_BOTTOM + 1
	jr	nc, vc3a
	ld	(cursory), a
vc3a:
	ld	a, b
	sub	#0x20
	jr	c, vc3b
	cp	#VT_RIGHT + 1
	jr	nc, vc3b
	ld	(cursorx), a
vc3b:
	xor	a
	ld	(vtmode), a
	ret
vc4:
	dec	a
	jr	nz, vc5
	ld	a, b
	ld	(_vtattr), a
	jr	vc_end
vc5:
	dec	a
	jr	nz, vc6
	ld	a, b
	ld	(_vtink), a
	jr	vc_end
vc6:
	dec	a
	ret	nz
	ld	a, b
	ld	(_vtpaper), a
vc_end:
	xor	a
	ld	(vtmode), a
	jp	_vtattr_notify

;	vtoutput(p, len): vtbusy guards against re-entry from tty echo
_vtoutput::
	call	___hard_di
	push	hl
	ld	a, (vtbusy)
	or	a
	jr	z, vo_go
	ld	hl, #4
	add	hl, sp
	ld	e, (hl)
	inc	hl
	ld	d, (hl)
	ld	a, (de)
	ld	(vtpend), a
	call	___hard_irqrestore
	pop	af
	ret
vo_go:
	ld	a, #1
	ld	(vtbusy), a
	call	___hard_irqrestore
	pop	af
	call	_vt_cursor_off
vo_loop:
	ld	hl, #4
	add	hl, sp
	ld	c, (hl)
	inc	hl
	ld	b, (hl)
	ld	a, b
	or	c
	jr	z, vo_pend
	dec	bc
	ld	(hl), b
	dec	hl
	ld	(hl), c
	ld	hl, #2
	add	hl, sp
	ld	e, (hl)
	inc	hl
	ld	d, (hl)
	ld	a, (de)
	inc	de
	ld	(hl), d
	dec	hl
	ld	(hl), e
	call	vo_char
	jr	vo_loop
vo_pend:
	ld	a, (vtpend)
	or	a
	jr	z, vo_done
	ld	c, a
	xor	a
	ld	(vtpend), a
	ld	a, c
	call	vo_char
	jr	vo_pend
vo_done:
	call	_vt_cursor_on
	xor	a
	ld	(vtbusy), a
	ret

;	vt_ioctl(minor, request, data)
_vt_ioctl::
	ld	hl, #2
	add	hl, sp
	ld	a, (hl)
	cp	#2
	jr	nc, vi_tty
	inc	hl
	ld	e, (hl)
	inc	hl
	ld	d, (hl)
	ld	a, d
	or	a
	jr	nz, vi_tty
	ld	a, e
	cp	#0x22
	jr	z, vi_size
	cp	#0x24
	jr	nz, vi_tty
	ld	a, (_vtattr_cap)
	ld	l, a
	ld	h, #0
	ret
vi_size:
	ld	hl, #((VT_BOTTOM + 1) << 8) | (VT_RIGHT + 1)
	ret
vi_tty:
	jp	_tty_ioctl

;	vt_inproc(minor, c)
_vt_inproc::
	ld	hl, #3
	add	hl, sp
	ld	a, (hl)
	cp	#0xa0
	jr	c, vp_n
	and	#0x7f
	ld	(hl), a
	dec	hl
	ld	l, (hl)
	ld	h, #0x1b
	push	hl
	call	_tty_inproc
	pop	af
vp_n:
	ld	hl, #3
	add	hl, sp
	ld	a, (hl)
	dec	hl
	ld	l, (hl)
	ld	h, a
	push	hl
	call	_tty_inproc
	pop	af
	ld	h, #0
	ret

_vtinit::
	xor	a
	ld	(vtmode), a
	call	_vtattr_notify
	ld	de, #((VT_BOTTOM + 1) << 8)
	push	de
	call	_clear_lines
	pop	af
	ld	hl, #0
	push	hl
	call	_cursor_on
	pop	af
	ret

	.area _DATA
vtmode:
	.ds	1
_vtattr::
	.ds	1
_vtpaper::
	.ds	1
cursorx:
	.ds	1
ncursory:
	.ds	1
cursorhide:
	.ds	1
vtpend:
	.ds	1
vtbusy:
	.ds	1
	.area _INITIALIZED
_vtink::
	.ds	1
cursory:
	.ds	1
	.area _INITIALIZER
	.db	0x07
	.db	0x00
	.area _CODE
