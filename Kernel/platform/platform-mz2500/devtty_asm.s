	.module devtty_asm
	.optsdcc -mz80
	
; Public variables in this module
	.globl _kbd_process
	.globl _mz_video_init
	.globl _vram_clear
	.globl _vt_inproc
	.globl _clear_across
	.globl _vtinit
	.globl _vtoutput
	.globl _held_row
	.globl _keyrepeat
	.globl _termios_mask
	.globl _ttyinq
	.globl _vtattr_cap
	.globl _cursorpos
	.globl _keyprev
	.globl _keyin
	.globl _clear_lines
	.globl _cursor_off
	.globl _cursor_on
	.globl _cursor_disable
	.globl _plot_char
	.globl _do_beep
	.globl _vtattr_notify
	.globl _kputchar
	.globl _tty_writeready
	.globl _tty_putc
	.globl _tty_carrier
	.globl _tty_data_consumed
	.globl _tty_setup
	.globl _tty_sleeping
; special function registers
_kbd_row	=	0x00e8
_kbd_data	=	0x00ea
; ram data
	.area _DATA
_tbuf1:
	.ds 132
_cursor_cell:
	.ds 2
_cursor_save1:
	.ds 1
_cursor_save2:
	.ds 1
_cursor_shown:
	.ds 1
_keyin::
	.ds 12
_keyprev::
	.ds 12
_held_bit:
	.ds 1
_held_timer:
	.ds 1
_cursorpos::
	.ds 2
; ram data
	.area _INITIALIZED
_vtattr_cap::
	.ds 1
_ttyinq::
	.ds 24
_termios_mask::
	.ds 4
_keyrepeat::
	.ds 2
_held_row::
	.ds 1
; absolute external ram data
	.area _DABS (ABS)
; global & static initialisations
	.area _HOME
	.area _GSINIT
	.area _GSFINAL
	.area _GSINIT
; Home
	.area _HOME
	.area _HOME
; code
	.area _CODE
	.globl _vstart, ___hard_di
; ---- cell helpers --------------------------------------------------
; cell_off: e=y c=x -> hl = ((y*80+x)+vstart) & 0x7ff ; clobbers bc,de
cell_off:
	ld	l, e
	ld	h, #0
	ld	d, h
	add	hl, hl
	add	hl, hl
	add	hl, de
	add	hl, hl
	add	hl, hl
	add	hl, hl
	add	hl, hl
	ld	b, #0
	add	hl, bc
	ld	bc, (_vstart)
	add	hl, bc
	ld	a, h
	and	a, #7
	ld	h, a
	ret
; pc_put: hl = cell offset, a = char. writes text (char&0x3f)<<2 and
; attr (char>>6)+0x8c. clobbers af,bc,de,hl
pc_put:
	ld	c, a
	and	a, #0x3f
	add	a, a
	add	a, a
	ld	e, a
	ld	a, c
	rlca
	rlca
	and	a, #3
	add	a, #0x8c
	ld	d, a
	ld	a, h
	add	a, #0xc0
	ld	h, a
	ld	(hl), e
	ld	a, h
	add	a, #0x10
	ld	h, a
	ld	(hl), d
	ret
_mz_video_init::
	; 80 columns: CRTC registers 7/8 = 09h/59h, then E8h bit 5 (the keyboard
	; scan keeps bits 7-5 of E8h)
	ld	a, #7
	out	(0xF4), a
	ld	a, #0x09
	out	(0xF5), a
	ld	a, #8
	out	(0xF4), a
	ld	a, #0x59
	out	(0xF5), a
	in	a, (0xE8)
	or	a, #0x20
	out	(0xE8), a
	call	_vram_clear
	xor	a, a
	ld	(_cursor_shown), a
	jp	_vtinit
; clear_lines(y, n): clear_across(y, 0, n*80)
_clear_lines::
	ld	hl, #3
	add	hl, sp
	ld	l, (hl)
	ld	h, #0
	ld	d, h
	ld	e, l
	add	hl, hl
	add	hl, hl
	add	hl, de
	add	hl, hl
	add	hl, hl
	add	hl, hl
	add	hl, hl
	push	hl
	ld	hl, #4
	add	hl, sp
	ld	e, (hl)
	ld	d, #0
	push	de
	call	_clear_across
	pop	af
	pop	af
	ret
_cursor_off::
	ld	a, (_cursor_shown)
	rrca
	ret	nc
	ld	hl, (_cursor_cell)
	ld	a, h
	add	a, #0xc0
	ld	h, a
	ld	a, (_cursor_save1)
	ld	(hl), a
	ld	a, h
	add	a, #0x10
	ld	h, a
	ld	a, (_cursor_save2)
	ld	(hl), a
	xor	a, a
	ld	(_cursor_shown), a
	ret
; cursor_on(y, x)
_cursor_on::
	call	_cursor_off
	ld	hl, #2
	add	hl, sp
	ld	e, (hl)
	inc	hl
	ld	c, (hl)
	call	cell_off
	ld	(_cursor_cell), hl
	ld	a, h
	add	a, #0xc0
	ld	h, a
	ld	a, (hl)
	ld	(_cursor_save1), a
	ld	a, h
	add	a, #0x10
	ld	h, a
	ld	a, (hl)
	ld	(_cursor_save2), a
	ld	hl, (_cursor_cell)
	ld	a, #0x5f
	call	pc_put
	ld	a, #1
	ld	(_cursor_shown), a
	ret
_cursor_disable::
	jp	_cursor_off
; plot_char(y, x, c16)
_plot_char::
	ld	hl, #2
	add	hl, sp
	ld	e, (hl)
	inc	hl
	ld	c, (hl)
	inc	hl
	ld	a, (hl)
	push	af
	call	cell_off
	pop	af
	push	hl
	call	pc_put
	pop	bc
	ld	a, (_cursor_shown)
	rrca
	ret	nc
	ld	hl, (_cursor_cell)
	or	a, a
	sbc	hl, bc
	ret	nz
	ld	a, b
	add	a, #0xc0
	ld	h, a
	ld	l, c
	ld	a, (hl)
	ld	(_cursor_save1), a
	ld	a, h
	add	a, #0x10
	ld	h, a
	ld	a, (hl)
	ld	(_cursor_save2), a
	ret
_do_beep::
_vtattr_notify::
_tty_data_consumed::
_tty_setup::
_tty_sleeping::
	ret
_kputchar::
	ld	hl, #2
	add	hl, sp
	ld	d, (hl)
	ld	a, d
	cp	a, #0x0a
	jr	nz, kp1
	push	de
	ld	de, #0x0d01
	push	de
	call	_tty_putc
	pop	af
	pop	de
kp1:
	ld	e, #1
	push	de
	call	_tty_putc
	pop	af
	ret
_tty_writeready::
	ld	l, #1
	ret
_tty_putc::
	ld	hl, #3
	add	hl, sp
	ld	bc, #1
	push	bc
	push	hl
	call	_vtoutput
	pop	af
	pop	af
	ret
_tty_carrier::
	ld	hl, #1
	ret
; ---- keyboard ------------------------------------------------------
; key_emit(row, bit)
_key_emit:
	ld	hl, #2
	add	hl, sp
	ld	a, (hl)
	inc	hl
	ld	e, (hl)
	ld	l, a
	ld	h, #0
	add	hl, hl
	add	hl, hl
	add	hl, hl
	ld	d, #0
	add	hl, de
	ld	a, (_keyin+11)
	ld	b, a
	and	a, #4
	ld	c, a
	ld	de, #_keytab
	jr	z, ke1
	ld	de, #_keytab_shift
ke1:
	add	hl, de
	ld	a, (hl)
	or	a, a
	ret	z
	ld	d, a
	bit	1, b
	jr	z, ke_ctl
	cp	a, #0x61
	jr	c, ke_up
	cp	a, #0x7b
	jr	nc, ke_up
	sub	a, #0x20
	ld	d, a
	jr	ke_ctl
ke_up:
	cp	a, #0x41
	jr	c, ke_ctl
	cp	a, #0x5b
	jr	nc, ke_ctl
	ld	a, c
	or	a, a
	jr	z, ke_ctl
	ld	a, d
	add	a, #0x20
	ld	d, a
ke_ctl:
	bit	4, b
	jr	z, ke_out
	ld	a, d
	and	a, #0x1f
	ld	e, a
	ld	a, d
	cp	a, #0x40
	jr	c, ke_lo
	cp	a, #0x60
	jr	nc, ke_lo
	ld	d, e
	jr	ke_out
ke_lo:
	cp	a, #0x61
	jr	c, ke_out
	cp	a, #0x7b
	jr	nc, ke_out
	ld	d, e
ke_out:
	ld	e, #1
	push	de
	call	_vt_inproc
	pop	af
	ret
_keytab:
	.db 0x00
	.db 0x00
	.db 0x00
	.db 0x00
	.db 0x00
	.db 0x00
	.db 0x00
	.db 0x00
	.db 0x00
	.db 0x00
	.db 0x38
	.db 0x39
	.db 0x2c
	.db 0x2e
	.db 0x2b
	.db 0x2d
	.db 0x30
	.db 0x31
	.db 0x32
	.db 0x33
	.db 0x34
	.db 0x35
	.db 0x36
	.db 0x37
	.db 0x09
	.db 0x20
	.db 0x0d
	.db 0xc1
	.db 0xc2
	.db 0xc4
	.db 0xc3
	.db 0x03
	.db 0x2f
	.db 0x61
	.db 0x62
	.db 0x63
	.db 0x64
	.db 0x65
	.db 0x66
	.db 0x67
	.db 0x68
	.db 0x69
	.db 0x6a
	.db 0x6b
	.db 0x6c
	.db 0x6d
	.db 0x6e
	.db 0x6f
	.db 0x70
	.db 0x71
	.db 0x72
	.db 0x73
	.db 0x74
	.db 0x75
	.db 0x76
	.db 0x77
	.db 0x78
	.db 0x79
	.db 0x7a
	.db 0x5e
	.db 0x5c
	.db 0x5f
	.db 0x2e
	.db 0x2c
	.db 0x30
	.db 0x31
	.db 0x32
	.db 0x33
	.db 0x34
	.db 0x35
	.db 0x36
	.db 0x37
	.db 0x38
	.db 0x39
	.db 0x3a
	.db 0x3b
	.db 0x2d
	.db 0x40
	.db 0x5b
	.db 0x00
	.db 0x5d
	.db 0x00
	.db 0xc8
	.db 0x7f
	.db 0x08
	.db 0x1b
	.db 0x2a
	.db 0x2f
	.db 0x00
	.db 0x00
	.db 0x00
	.db 0x00
	.db 0x00
	.db 0x00
	.db 0x00
	.db 0x00
_keytab_shift:
	.db 0x00
	.db 0x00
	.db 0x00
	.db 0x00
	.db 0x00
	.db 0x00
	.db 0x00
	.db 0x00
	.db 0x00
	.db 0x00
	.db 0x38
	.db 0x39
	.db 0x2c
	.db 0x2e
	.db 0x2b
	.db 0x2d
	.db 0x30
	.db 0x31
	.db 0x32
	.db 0x33
	.db 0x34
	.db 0x35
	.db 0x36
	.db 0x37
	.db 0x09
	.db 0x20
	.db 0x0d
	.db 0xc1
	.db 0xc2
	.db 0xc4
	.db 0xc3
	.db 0x03
	.db 0x3f
	.db 0x41
	.db 0x42
	.db 0x43
	.db 0x44
	.db 0x45
	.db 0x46
	.db 0x47
	.db 0x48
	.db 0x49
	.db 0x4a
	.db 0x4b
	.db 0x4c
	.db 0x4d
	.db 0x4e
	.db 0x4f
	.db 0x50
	.db 0x51
	.db 0x52
	.db 0x53
	.db 0x54
	.db 0x55
	.db 0x56
	.db 0x57
	.db 0x58
	.db 0x59
	.db 0x5a
	.db 0x7e
	.db 0x7c
	.db 0x5f
	.db 0x3e
	.db 0x3c
	.db 0x00
	.db 0x21
	.db 0x22
	.db 0x23
	.db 0x24
	.db 0x25
	.db 0x26
	.db 0x27
	.db 0x28
	.db 0x29
	.db 0x2a
	.db 0x2b
	.db 0x3d
	.db 0x60
	.db 0x7b
	.db 0x00
	.db 0x7d
	.db 0x00
	.db 0xc8
	.db 0x7f
	.db 0x08
	.db 0x1b
	.db 0x2a
	.db 0x2f
	.db 0x00
	.db 0x00
	.db 0x00
	.db 0x00
	.db 0x00
	.db 0x00
	.db 0x00
	.db 0x00
_kbd_process::
	ld	a, (_held_row)
	bit	7, a
	jr	nz, kb_scan
	ld	l, a
	ld	h, #0
	ld	de, #_keyin
	add	hl, de
	ld	c, (hl)
	ld	a, (_held_bit)
	ld	b, a
	ld	a, #1
	inc	b
	jr	kb_s2
kb_s1:
	add	a, a
kb_s2:
	djnz	kb_s1
	and	a, c
	jr	z, kb_rel
	ld	hl, #_held_timer
	dec	(hl)
	jr	nz, kb_scan
	ld	a, (_held_bit)
	ld	d, a
	ld	a, (_held_row)
	ld	e, a
	push	de
	call	_key_emit
	pop	af
	ld	a, (_keyrepeat+1)
	ld	(_held_timer), a
	jr	kb_scan
kb_rel:
	ld	a, #0xff
	ld	(_held_row), a
kb_scan:
	ld	c, #0
kb_l1:
	ld	hl, #_keyin
	ld	b, #0
	add	hl, bc
	ld	e, (hl)
	ld	hl, #_keyprev
	add	hl, bc
	ld	a, (hl)
	cpl
	and	a, e
	ld	b, a
	or	a, a
	jr	z, kb_next
	ld	de, #1
kb_l2:
	ld	a, d
	cp	a, #8
	jr	nc, kb_next
	ld	a, b
	and	a, e
	jr	z, kb_nb
	push	bc
	push	de
	ld	e, c
	push	de
	call	_key_emit
	pop	af
	pop	de
	pop	bc
	ld	a, c
	ld	(_held_row), a
	ld	a, d
	ld	(_held_bit), a
	ld	a, (_keyrepeat)
	ld	(_held_timer), a
kb_nb:
	inc	d
	sla	e
	jr	kb_l2
kb_next:
	inc	c
	ld	a, c
	cp	a, #11
	jr	c, kb_l1
	ld	hl, #_keyin
	ld	de, #_keyprev
	ld	bc, #12
	ldir
	ret
	.area _CONST
	.area _INITIALIZER
__xinit__vtattr_cap:
	.db #0x00	; 0
__xinit__ttyinq:
	.dw #0x0000
	.dw #0x0000
	.dw #0x0000
	.dw #0x0000
	.dw #0x0000
	.dw #0x0000
	.dw _tbuf1
	.dw _tbuf1
	.dw _tbuf1
	.dw #0x0084
	.dw #0x0000
	.dw #0x0042
__xinit__termios_mask:
	.dw #0x0000
	.dw #0x0c80
__xinit__keyrepeat:
	.db #0x19	; 25
	.db #0x03	; 3
__xinit__held_row:
	.db #0xff	; -1
	.area _CABS (ABS)
