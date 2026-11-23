; start_asm.s - kernel start-up code (hand-written replacement for start.c)
; All code lives in _DISCARD (reclaimed after boot).
	.module start_asm
	.globl _get_root_dev, _bootdevice, _parse_args, _complete_init, _create_init
	.globl _add_argument, _fstabinit, _bufinit, _tty_init, _set_boot_line, _fuzix_main
	.globl _kputs, _kprintf, __pause, ___hard_ei, _plt_param, _set_cpu_type
	.globl _map_init, _pagemap_init, _device_init, _exec_or_die, _panic
	.globl _ptab_alloc, _makeproc, _fmount, _i_open, _d_open, _cdread
	.globl _uzero, _uputw, _uput, _strlen
	.globl _udata, _ttydata, _bufpool, _fs_tab, _cmdline, _ttyinq, _init_process
	.globl _ramtop, _sysinfo, _sys_cpu, _sys_cpu_feat, _procmem, _maxproc, _ptab
	.globl _ptab_end, _ramsize, _ticks_per_dsecond, _root_dev, _root, _tod, _ticks

	.area _DATA
_progptr:	.ds 2
_old_progptr:	.ds 2
_argptr:	.ds 2
_old_argptr:	.ds 2
_bootline:	.ds 64
	.area _INITIALIZED
_ro:		.ds 1
	.area _INITIALIZER
	.db 1
	.area _DISCARD

; ---- tty_init: copy default termios into minor 1 ---------------------
_tty_init::
	ld	hl, #_ttydflt
	ld	de, #_ttydata+32+4
	ld	bc, #20
	ldir
	ret
_ttydflt:
	.dw 0x0003, 0x0005, 0x08bb, 0x0077
	.db 0x04, 0x00, 0x08, 0x03, 0x15, 0x1c, 0x11, 0x13
	.db 0x1a, 0x19, 0x16, 0x0f

; ---- bufinit: 6 buffers of 0x208 bytes --------------------------------
_bufinit::
	ld	de, #_bufpool
bi_lp:
	ld	a, e
	sub	a, #<(_bufpool + 0x0c30)
	ld	a, d
	sbc	a, #>(_bufpool + 0x0c30)
	ret	nc
	ld	hl, #0x0200
	add	hl, de
	ld	a, #0xff
	ld	(hl), a			; bf_dev = NO_DEVICE
	inc	hl
	ld	(hl), a
	ld	hl, #0x0204
	add	hl, de
	xor	a, a
	ld	(hl), a
	inc	hl
	ld	(hl), a
	inc	hl
	ld	(hl), a
	inc	hl
	ld	(hl), a
	ld	hl, #0x0208
	add	hl, de
	ex	de, hl
	jr	bi_lp

; ---- fstabinit: 4 mount slots of 0xe3 bytes -----------------------------
_fstabinit::
	ld	hl, #_fs_tab
fi_lp:
	ld	a, l
	sub	a, #<(_fs_tab + 0x038c)
	ld	a, h
	sbc	a, #>(_fs_tab + 0x038c)
	ret	nc
	ld	(hl), #0xff
	inc	hl
	ld	(hl), #0xff
	dec	hl
	ld	bc, #0x00e3
	add	hl, bc
	jr	fi_lp

; ---- add_argument(char *s) -------------------------------------------
_add_argument::
	ld	hl, #2
	add	hl, sp
	ld	e, (hl)
	inc	hl
	ld	d, (hl)
	push	de
	call	_strlen
	pop	de
	inc	hl
	ld	b, h
	ld	c, l
	push	bc			; keep n
	push	bc
	ld	hl, (_progptr)
	push	hl
	push	de
	call	_uput			; uput(s, progptr, n)
	pop	af
	pop	af
	pop	af
	ld	hl, (_argptr)
	push	hl
	ld	hl, (_progptr)
	push	hl
	call	_uputw			; uputw(progptr, argptr)
	pop	af
	pop	af
	pop	bc
	inc	bc
	inc	bc
	inc	bc
	ld	a, c
	and	a, #0xfc
	ld	c, a
	ld	hl, (_progptr)
	add	hl, bc
	ld	(_progptr), hl
	ld	hl, (_argptr)
	inc	hl
	inc	hl
	ld	(_argptr), hl
	ret

; ---- create_init -------------------------------------------------------
_create_init::
	ld	hl, #0x0300
	ld	(_udata + 0x1c), hl	; u_top
	call	_ptab_alloc
	ld	(_init_process), hl
	ld	(_udata), hl		; u_ptab
	ld	de, #0x45		; p_top
	add	hl, de
	ld	de, (_udata + 0x1c)
	ld	(hl), e
	inc	hl
	ld	(hl), d
	call	_map_init
	ld	hl, #_udata + 0x7d	; u_files[] = -1
	ld	b, #10
	ld	a, #0xff
ci_fl:
	ld	(hl), a
	inc	hl
	djnz	ci_fl
	ld	hl, #_udata
	push	hl
	ld	hl, (_init_process)
	push	hl
	call	_makeproc
	pop	af
	pop	af
	ld	a, #1
	ld	(_udata + 6), a		; u_insys
	ld	hl, (_init_process)
	ld	(hl), a			; p_status = P_RUNNING
	ld	hl, #0x0100
	ld	(_argptr), hl
	ld	h, #0x02
	ld	(_progptr), hl
	ld	hl, #0x0020
	push	hl
	ld	hl, #0x0200
	push	hl
	call	_uzero
	pop	af
	ld	hl, #s_init
	ex	(sp), hl
	call	_add_argument
	pop	af
	ret
s_init:	.asciz "/init"

_complete_init::
	ld	hl, (_argptr)
	push	hl
	ld	hl, #0
	push	hl
	call	_uputw
	pop	af
	pop	af
	ld	hl, (_argptr)
	ld	(_udata + 0x16), hl	; u_argn2 = envp
	ld	hl, #0x0200
	ld	(_udata + 0x12), hl	; u_argn  = "/init"
	ld	h, #0x01
	ld	(_udata + 0x14), hl	; u_argn1 = argv
	ld	hl, (_init_process)
	ld	de, #0x41		; p_pgrp
	add	hl, de
	ld	(hl), #1
	inc	hl
	ld	(hl), #0
	ret

; ---- system_param(char *p) -> L ------------------------------------------
sys_param:
	ld	hl, #2
	add	hl, sp
	ld	c, (hl)
	inc	hl
	ld	b, (hl)
	ld	a, (bc)
	cp	a, #'r
	jr	nz, sp_plt
	ld	h, b
	ld	l, c
	inc	hl
	inc	hl
	ld	a, (hl)
	or	a, a
	jr	nz, sp_plt
	dec	hl
	ld	a, (hl)
	cp	a, #'o
	jr	nz, sp_w
	ld	a, #1
	ld	(_ro), a
	ld	l, a
	ret
sp_w:
	cp	a, #'w
	jr	nz, sp_plt
	xor	a, a
	ld	(_ro), a
	ld	l, #1
	ret
sp_plt:
	push	bc
	call	_plt_param
	pop	af
	ret

; ---- parse_args(char *p) ---------------------------------------------------
_parse_args::
	ld	hl, #2
	add	hl, sp
	ld	c, (hl)
	inc	hl
	ld	b, (hl)
pa_lp:
	ld	a, (bc)
	cp	a, #0x20
	jr	z, pa_sk
	cp	a, #0x0a
	jr	nz, pa_st
pa_sk:
	inc	bc
	jr	pa_lp
pa_st:
	or	a, a
	ret	z
	ld	d, b
	ld	e, c			; de = start of word
pa_w:
	ld	a, (bc)
	or	a, a
	jr	z, pa_end
	cp	a, #0x20
	jr	z, pa_end
	cp	a, #0x0a
	jr	z, pa_end
	inc	bc
	jr	pa_w
pa_end:
	or	a, a
	jr	z, pa_go
	xor	a, a
	ld	(bc), a
	inc	bc
pa_go:
	push	bc
	push	de
	push	de
	call	sys_param
	pop	af
	pop	de
	ld	a, l
	or	a, a
	jr	nz, pa_nx
	push	de
	call	_add_argument
	pop	af
pa_nx:
	pop	bc
	jr	pa_lp

; ---- bootdevice(char *name) -> HL (0xffff = bad) -----------------------------
; locals: -2 b(lo) -1 b(hi) -4 n(lo) -3 n(hi) -5 match -7,-6 devname
_bootdevice::
	call	___sdcc_enter_ix
	ld	hl, #-8
	add	hl, sp
	ld	sp, hl
	call	ixh_cb_p4
bd_sk:
	ld	a, (bc)
	cp	a, #0x20
	jr	nz, bd_s2
	inc	bc
	jr	bd_sk
bd_s2:
	ld	-7 (ix), c
	ld	-6 (ix), b
	xor	a, a
	ld	-1 (ix), a
	ld	-2 (ix), a
	ld	-3 (ix), a
	ld	-4 (ix), a
	inc	a
	ld	-5 (ix), a
	ld	de, #bd_names
bd_lp:
	ld	a, (de)
	or	a, a
	jr	z, bd_done
	cp	a, #',
	jr	nz, bd_nc
	ld	a, -5 (ix)
	or	a, a
	jr	z, bd_cm
	ld	a, c
	cp	a, -7 (ix)
	jr	nz, bd_done
	ld	a, b
	cp	a, -6 (ix)
	jr	nz, bd_done
bd_cm:
	ld	c, -7 (ix)
	ld	b, -6 (ix)
	inc	-1 (ix)
	ld	a, #1
	ld	-5 (ix), a
	inc	de
	jr	bd_lp
bd_nc:
	ld	l, a			; l = name char
	ld	a, (bc)
	cp	a, #'A
	jr	c, bd_lo
	cp	a, #'Z+1
	jr	nc, bd_lo
	or	a, #0x20
bd_lo:
	ld	h, a			; h = input char (lower case)
	ld	a, l
	cp	a, #'#
	jr	nz, bd_ch
	ld	a, -5 (ix)
	or	a, a
	jr	z, bd_ch
	ld	a, h
	cp	a, #'a
	jr	c, bd_bad
	cp	a, #'p+1
	jr	nc, bd_bad
	sub	a, #'a
	add	a, a
	add	a, a
	add	a, a
	add	a, a
	add	a, -2 (ix)
	ld	-2 (ix), a
	inc	bc
	jr	bd_done
bd_ch:
	ld	a, -5 (ix)
	or	a, a
	jr	z, bd_ad
	ld	a, h
	cp	a, l
	jr	z, bd_ad
	xor	a, a
	ld	-5 (ix), a
bd_ad:
	inc	bc
	inc	de
	jr	bd_lp
bd_bad:
	ld	hl, #0xffff
	jr	bd_ret
bd_done:
	ld	a, -5 (ix)
	or	a, a
	jr	nz, bd_dg
	xor	a, a
	ld	-1 (ix), a
	ld	-2 (ix), a
	ld	c, -7 (ix)
	ld	b, -6 (ix)
bd_dg:
	ld	a, (bc)
	sub	a, #'0
	jr	c, bd_de
	cp	a, #10
	jr	nc, bd_de
	call	ixh_lh_m4
	ld	d, h
	ld	e, l
	add	hl, hl
	add	hl, hl
	add	hl, de
	add	hl, hl
	add	a, l
	ld	l, a
	jr	nc, bd_nn
	inc	h
bd_nn:
	ld	-4 (ix), l
	ld	-3 (ix), h
	inc	bc
	ld	a, #1
	ld	-5 (ix), a
	jr	bd_dg
bd_de:
	ld	a, (bc)
	or	a, a
	jr	z, bd_fin
	cp	a, #0x0a
	jr	z, bd_fin
	cp	a, #0x0d
	jr	z, bd_fin
	cp	a, #0x20
	jr	nz, bd_bad
	push	bc
	call	_parse_args
	pop	af
bd_fin:
	ld	a, -5 (ix)
	or	a, a
	jr	z, bd_bad
	call	ixh_lh_m2
	call	ixh_ed_m4
	add	hl, de
bd_ret:
	jp	ixh_leave
bd_names:	.asciz "hd#,fd"

; ---- get_root_dev -> HL -------------------------------------------------------
_get_root_dev::
	ld	bc, #0xffff
	ld	hl, (_cmdline)
	ld	a, h
	or	a, l
	jr	z, gr_1
	ld	a, (hl)
	or	a, a
	jr	z, gr_1
	push	hl
	call	_bootdevice
	pop	af
	ld	b, h
	ld	c, l
gr_1:
	ld	hl, #0
	ld	(_cmdline), hl
gr_2:
	ld	a, b
	and	a, c
	inc	a
	jr	nz, gr_ret
	ld	hl, #s_bootdev
	call	ixh_p1_kputs
	ld	hl, #_bootline
	ld	(_udata + 0x62), hl	; u_base
	ld	a, #1
	ld	(_udata + 0x6c), a	; u_sysio
	ld	hl, #0x003f
	ld	(_udata + 0x64), hl	; u_count
	ld	hl, #0
	ld	(_udata + 0x71), hl	; u_euid
	ld	(_udata + 0x99), hl	; u_done
	xor	a, a
	push	af
	inc	sp
	ld	hl, #0x0201
	push	hl
	call	_cdread
	pop	af
	inc	sp
	ld	hl, (_udata + 0x99)
	ld	de, #_bootline
	add	hl, de
	ld	(hl), #0
	ld	hl, #_bootline
	push	hl
	call	_bootdevice
	pop	af
	ld	b, h
	ld	c, l
	jr	gr_2
gr_ret:
	ld	h, b
	ld	l, c
	ret
s_bootdev:	.asciz "bootdev: "

; ---- set_boot_line(const char *p) -------------------------------------------
_set_boot_line::
	ld	hl, #10
	ld	(_udata + 0x12), hl
	call	__pause
	ld	hl, (_ttyinq + 0x14)
	ld	a, h
	or	a, l
	ret	nz
	ld	hl, #2
	add	hl, sp
	ld	e, (hl)
	inc	hl
	ld	d, (hl)
	ex	de, hl
	ld	de, #_bootline
	ld	bc, #0x003f
	ldir
	ld	hl, #_bootline
	ld	(_cmdline), hl
	ret

; ---- fuzix_main -------------------------------------------------------------------
_fuzix_main::
	xor	a, a
	ld	(_udata + 0x10), a	; u_ininterrupt
	inc	a
	ld	(_udata + 6), a		; u_insys
	ld	hl, #0xe000
	ld	(_ramtop), hl
	call	_tty_init
	xor	a, a
	push	af
	inc	sp
	ld	hl, #0x0201
	push	hl
	call	_d_open
	pop	af
	inc	sp
	ld	a, h
	or	a, l
	jr	z, fm_1
	ld	hl, #s_notty
	push	hl
	call	_panic
fm_1:
	ld	hl, #_sysinfo + 0x2a
	push	hl
	ld	hl, #s_banner
	push	hl
	call	_kprintf
	pop	af
	pop	af
	call	_set_cpu_type
	ld	a, (_sys_cpu_feat)
	ld	(_sysinfo + 0x17), a
	ld	a, (_sys_cpu)
	ld	(_sysinfo + 0x16), a
	ld	hl, (_procmem)
	srl	h
	rr	l
	srl	h
	rr	l
	srl	h
	rr	l
	ld	(_maxproc), hl
	ld	de, #16
	or	a, a
	sbc	hl, de
	jr	c, fm_2
	ld	hl, (_maxproc)
	push	hl
	ld	hl, #s_ptab
	push	hl
	call	_kprintf
	pop	af
	pop	af
	ld	hl, #15
	ld	(_maxproc), hl
fm_2:
	ld	de, (_maxproc)		; ptab_end = ptab + maxproc * 75
	ld	l, e
	ld	h, d
	add	hl, hl
	add	hl, hl
	add	hl, hl
	add	hl, de
	add	hl, hl
	add	hl, hl
	add	hl, de
	add	hl, hl
	add	hl, de
	ld	bc, #_ptab
	add	hl, bc
	ld	(_ptab_end), hl
	call	_bufinit
	call	_fstabinit
	call	_pagemap_init
	call	_create_init
	ld	hl, (_maxproc)
	push	hl
	ld	hl, (_procmem)
	push	hl
	ld	hl, (_ramsize)
	push	hl
	ld	hl, #s_ram
	push	hl
	call	_kprintf
	pop	af
	pop	af
	pop	af
	pop	af
	ld	a, #5
	ld	(_ticks_per_dsecond), a
	ld	hl, #s_ei
	call	ixh_p1_kputs
	call	___hard_ei
	ld	hl, #s_ok
	call	ixh_p1_kputs
	call	_device_init
fm_root:
	ld	hl, (_progptr)
	ld	(_old_progptr), hl
	ld	hl, (_argptr)
	ld	(_old_argptr), hl
	call	_get_root_dev
	ld	(_root_dev), hl
	ld	a, h
	and	a, l
	inc	a
	jr	nz, fm_3
	ld	hl, #s_noroot
	push	hl
	call	_panic
fm_3:
	ld	a, (_ro)
	ld	bc, #'w
	or	a, a
	jr	z, fm_4
	ld	c, #'o
fm_4:
	push	bc
	ld	hl, (_root_dev)
	push	hl
	ld	hl, #s_mnt
	push	hl
	call	_kprintf
	pop	af
	pop	af
	pop	af
	ld	a, (_ro)
	ld	c, a
	ld	b, #0
	push	bc
	ld	hl, #0
	push	hl
	ld	hl, (_root_dev)
	push	hl
	call	_fmount
	pop	af
	pop	af
	pop	af
	ld	a, h
	or	a, l
	jr	nz, fm_mounted
	ld	hl, #s_failed
	call	ixh_p1_kputs
	ld	hl, (_old_progptr)
	ld	(_progptr), hl
	ld	hl, (_old_argptr)
	ld	(_argptr), hl
	ld	a, #1
	ld	(_ro), a
	jr	fm_root
fm_mounted:
	ld	de, #6 + 0xd4		; m->m_fs.s_time / s_timeh
	add	hl, de
	push	hl
	ld	de, #_tod
	ld	bc, #4
	ldir
	pop	hl
	dec	hl			; +0xd3
	ld	a, (hl)
	ld	(_tod + 4), a
	xor	a, a
	ld	(_tod + 5), a
	ld	(_tod + 6), a
	ld	(_tod + 7), a
	ld	hl, #1
	push	hl
	ld	hl, (_root_dev)
	push	hl
	call	_i_open
	pop	af
	pop	af
	ld	(_root), hl
	ld	a, h
	or	a, l
	jr	nz, fm_5
	ld	hl, #s_noroot
	push	hl
	call	_panic
fm_5:
	ld	hl, #s_okl
	call	ixh_p1_kputs
	call	_complete_init
	ld	hl, (_root)
	ld	de, #0x46		; c_refs
	add	hl, de
	inc	(hl)
	ld	hl, (_root)
	ld	(_udata + 0x89), hl	; u_cwd
	ld	hl, (_root)
	add	hl, de
	inc	(hl)
	ld	hl, (_root)
	ld	(_udata + 0x8b), hl	; u_root
	ld	hl, (_udata)
	ld	de, #0x2d		; p_time
	add	hl, de
	ex	de, hl
	ld	hl, #_ticks
	ld	bc, #4
	ldir
	jp	_exec_or_die

s_notty:	.asciz "no tty"
s_banner:
	.ascii "FUZIX version %s"
	.db 0x0a
	.ascii "Copyright (c) 1988-2002 by H.F.Bower, D.Braun, S.Nitschke, H.Peraza"
	.db 0x0a
	.ascii "Copyright (c) 1997-2001 by Arcady Schekochikhin, Adriano C. R. da Cunha"
	.db 0x0a
	.ascii "Copyright (c) 2013-2015 Will Sowerbutts <will@sowerbutts.com>"
	.db 0x0a
	.ascii "Copyright (c) 2014-2025 Alan Cox <alan@etchedpixels.co.uk>"
	.db 0x0a
	.ascii "Devboot"
	.db 0x0a, 0
s_ptab:		.ascii "WARNING: Increase PTABSIZE to %d to use available RAM"
	.db 0x0a, 0
s_ram:		.ascii "%dKiB total RAM, %dKiB available to processes (%d processes max)"
	.db 0x0a, 0
s_ei:		.asciz "Enabling interrupts ... "
s_ok:		.db 0x6f, 0x6b, 0x2e, 0x0a, 0	; "ok.\n"
s_noroot:	.asciz "no root"
s_mnt:		.asciz "Mounting root fs (root_dev=%d, r%c): "
s_failed:	.db 0x66, 0x61, 0x69, 0x6c, 0x65, 0x64, 0x0a, 0	; "failed\n"
s_okl:		.db 0x4f, 0x4b, 0x0a, 0	; "OK\n"
