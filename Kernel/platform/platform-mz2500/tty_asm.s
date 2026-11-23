; Hand written tty output path: tty_write and tty_putc_maywait (tty.c).
; SDCC convention: arguments on the stack (right to left, caller pops), result in HL,
; IX preserved, everything else may be destroyed. Byte arguments are packed.
	.module tty_asm
	.globl _udata, _ttydata, _valaddr_r, __ugetc, _psleep_flags_io, _tty_writeready
	.globl _chksigs, _nready, _runticks, ___hard_di, ___hard_irqrestore
	.globl _tty_sleeping, _psleep, _switchout, _tty_putc
	.globl _tty_write, _tty_putc_maywait
	.area _CODE

; int tty_write(uint8 minor, uint8 rawflag, uint8 flag)   local: -2 t
_tty_write::
	call ___sdcc_enter_ix
	push af
	ld hl, (_udata + 0x64)	; u_count
	push hl
	ld hl, (_udata + 0x62)	; u_base
	push hl
	call _valaddr_r
	pop af
	pop af
	ld a, h
	or l
	jr nz, tw_ok
	ld hl, #0xffff
	jp tw_out
tw_ok:
	ld l, 4 (ix)
	ld h, #0
	add hl, hl
	add hl, hl
	add hl, hl
	add hl, hl
	add hl, hl
	ld de, #_ttydata
	add hl, de
	ld -2 (ix), l
	ld -1 (ix), h
tw_loop:
	ld hl, (_udata + 0x99)	; u_done
	ld de, (_udata + 0x64)
	or a
	sbc hl, de
	jp z, tw_done
tw_wait:
	call	ixh_lh_m2
	ld a, (hl)
	bit 2, a		; TTYF_DEAD
	jr z, tw_nd
	ld hl, #6		; ENXIO
	ld (_udata + 0x0c), hl
	ld hl, #0xffff
	jp tw_out
tw_nd:
	bit 0, a		; TTYF_STOP
	jr z, tw_go
	ld a, 6 (ix)
	push af
	inc sp
	push hl			; &t->flag
	call _psleep_flags_io
	pop af
	inc sp
	ld a, h
	or l
	jr z, tw_wait
	ld hl, (_udata + 0x99)
	jp tw_out
tw_go:
	bit 1, a		; TTYF_DISCARD
	jp nz, tw_skip
	ld a, (_udata + 0x6c)	; u_sysio
	ld hl, (_udata + 0x62)
	bit 0, a
	jr z, tw_user
	ld b, (hl)
	jr tw_c
tw_user:
	call __ugetc
	ld b, l
tw_c:
	call	ixh_lh_m2
	ld de, #6
	add hl, de
	ld c, (hl)		; c_oflag (low)
	bit 0, c		; OPOST
	jr z, tw_put
	ld a, b
	cp #0x0a
	jr nz, tw_cr
	bit 2, c		; ONLCR
	jr z, tw_cr
	push bc
	ld d, 6 (ix)
	ld e, #0x0d
	push de
	ld a, 4 (ix)
	push af
	inc sp
	call _tty_putc_maywait
	pop af
	inc sp
	ld a, l
	pop bc
	or a
	jr z, tw_put
	jr tw_done
tw_cr:
	ld a, b
	cp #0x0d
	jr nz, tw_put
	bit 3, c		; OCRNL
	jr z, tw_put
	ld b, #0x0a
tw_put:
	ld a, 6 (ix)
	push af
	inc sp
	push bc
	inc sp			; c (B)
	ld a, 4 (ix)
	push af
	inc sp
	call _tty_putc_maywait
	pop af
	inc sp
	ld a, l
	or a
	jr nz, tw_done
tw_skip:
	ld hl, (_udata + 0x62)
	inc hl
	ld (_udata + 0x62), hl
	ld hl, (_udata + 0x99)
	inc hl
	ld (_udata + 0x99), hl
	jp tw_loop
tw_done:
	ld hl, (_udata + 0x99)
tw_out:
	jp	ixh_leave

; int tty_putc_maywait(uint8 minor, uint8 c, uint8 flag)
_tty_putc_maywait::
	call ___sdcc_enter_ix
	ld a, 6 (ix)
	and #0x10		; O_NDELAY
	ld 6 (ix), a
	ld a, (_udata + 16)	; u_ininterrupt
	bit 0, a
	jp nz, tp_put
tp_l:
	ld a, 4 (ix)
	push af
	inc sp
	call _tty_writeready
	inc sp
	ld c, l
	dec l
	jp z, tp_put		; ready now
	push bc
	call _chksigs
	pop bc
	ld a, l
	or a
	jr z, tp_nosig
	ld hl, #4		; EINTR
	ld (_udata + 0x0c), hl
	ld hl, #1
	jp tp_out
tp_nosig:
	ld a, c
	or a
	jr nz, tp_108
	ld a, (_nready)
	dec a
	jr z, tp_l
	ld hl, (_udata + 0)
	ld de, #0x13		; p_priority
	add hl, de
	ld b, (hl)
	inc hl
	ld e, (hl)
	ld iy, #_runticks
	ld a, 0 (iy)
	sub b
	ld a, 1 (iy)
	sbc a, e
	jr c, tp_l
tp_108:
	ld a, 6 (ix)
	or a
	jr z, tp_104
	ld hl, #11		; EAGAIN
	ld (_udata + 0x0c), hl
	ld hl, #1
	jr tp_out
tp_104:
	ld a, c
	or a
	jr z, tp_sw
	call ___hard_di
	push hl
	ld a, 4 (ix)
	push af
	inc sp
	call _tty_sleeping
	inc sp
	pop bc
	ld l, 4 (ix)
	ld h, #0
	add hl, hl
	add hl, hl
	add hl, hl
	add hl, hl
	add hl, hl
	ld de, #_ttydata
	add hl, de
	push bc
	push hl
	call _psleep
	pop af
	call ___hard_irqrestore
	pop af
	jp tp_l
tp_sw:
	call _switchout
	jp tp_l
tp_put:
	ld h, 5 (ix)
	ld l, 4 (ix)
	push hl
	call _tty_putc
	pop af
	ld hl, #0
tp_out:
	pop ix
	ret

	.globl _ttyinq, _sgrpsig, _clrq, _wakeup, _insq, _uninsq, _tty_echo, _tty_erase
	.globl _tty_putc_wait, _tty_inproc
; void tty_echo(uint8 minor, uint8 c)
_tty_echo::
	ld hl, #2
	add hl, sp
	ld l, (hl)
	ld h, #0
	add hl, hl
	add hl, hl
	add hl, hl
	add hl, hl
	add hl, hl
	ld de, #_ttydata + 10	; c_lflag
	add hl, de
	bit 0, (hl)		; ECHO
	ret z
	call	ixh_sp2_ed
	push de
	call _tty_putc_wait
	pop af
	ret

; void tty_erase(uint8 minor)
_tty_erase::
	call ___sdcc_enter_ix
	ld h, #8
	ld l, 4 (ix)
	push hl
	call _tty_putc_wait
	pop af
	ld h, #0x20
	ld l, 4 (ix)
	push hl
	call _tty_putc_wait
	pop af
	ld h, #8
	ld l, 4 (ix)
	push hl
	call _tty_putc_wait
	pop af
	pop ix
	ret

; uint8 tty_inproc(uint8 minor, uint8 c)
; locals: -2 t, -4 q, -5 canon, -6 c, -7 oc, -8 wr
; struct tty: flag +0, pgrp +2, c_iflag +4, c_oflag +6, c_cflag +8, c_lflag +10, c_cc +12
; c_cc: VEOF 12, VEOL 13, VERASE 14, VINTR 15, VKILL 16, VQUIT 17, VSTART 18, VSTOP 19, VDISCARD 23
_tty_inproc::
	call ___sdcc_enter_ix
	ld hl, #-8
	add hl, sp
	ld sp, hl
	ld l, 4 (ix)
	ld h, #0
	ld e, l
	ld d, h
	add hl, hl
	add hl, hl
	add hl, hl
	add hl, hl
	add hl, hl
	push de
	ld de, #_ttydata
	add hl, de
	ld -2 (ix), l
	ld -1 (ix), h
	pop de
	ld l, e			; q = ttyinq + minor * 12
	ld h, d
	add hl, hl
	add hl, de
	add hl, hl
	add hl, hl
	ld de, #_ttyinq
	add hl, de
	ld -4 (ix), l
	ld -3 (ix), h
	ld a, 5 (ix)
	ld -6 (ix), a
	call	ixh_lh_m2
	push hl
	pop iy
	ld a, 10 (iy)
	and #0x10		; ICANON
	ld -5 (ix), a
	bit 7, 4 (iy)		; ISTRIP
	jr z, ti_ns
	ld a, -6 (ix)
	and #0x7f
	ld -6 (ix), a
ti_ns:
	ld a, -5 (ix)
	or a
	jr z, ti_nn
	ld a, -6 (ix)
	or a
	jp z, ti_ret1		; canon && NUL
ti_nn:
	ld a, -6 (ix)
	cp #0x0d
	jr nz, ti_ncr
	bit 3, 4 (iy)		; IGNCR
	jp nz, ti_ret1
	bit 1, 4 (iy)		; ICRNL
	jr z, ti_ncr
	ld -6 (ix), #0x0a
ti_ncr:
	ld a, -6 (ix)
	cp #0x0a
	jr nz, ti_nl
	bit 5, 4 (iy)		; INLCR
	jr z, ti_nl
	ld -6 (ix), #0x0d
ti_nl:
	bit 6, 10 (iy)		; ISIG
	jr z, ti_nsig
	ld a, -6 (ix)
	cp 15 (iy)		; VINTR
	ld b, #2		; SIGINT
	jr z, ti_sig
	cp 17 (iy)		; VQUIT
	ld b, #3		; SIGQUIT
	jr nz, ti_nsig
ti_sig:
	ld a, b
	push af
	inc sp
	ld l, 2 (iy)
	ld h, 3 (iy)
	push hl
	call _sgrpsig
	pop af
	inc sp
	call	ixh_lh_m4
	push hl
	call _clrq
	pop af
	call	ixh_lh_m2
	ld a, (hl)
	and #0xfc		; ~(TTYF_STOP | TTYF_DISCARD)
	ld (hl), a
	jp ti_ret1
ti_nsig:
	call	ixh_lh_m2
	push hl
	pop iy
	bit 4, 5 (iy)		; IXON
	jr z, ti_nx
	ld a, -6 (ix)
	cp 19 (iy)		; VSTOP
	jr nz, ti_nst
	set 0, 0 (iy)		; TTYF_STOP
	jp ti_ret1
ti_nst:
	cp 18 (iy)		; VSTART
	jr nz, ti_nx
	res 0, 0 (iy)
	push iy
	call _wakeup
	pop af
	jp ti_ret1
ti_nx:
	call	ixh_lh_m2
	push hl
	pop iy
	ld a, -5 (ix)
	or a
	jr z, ti_cm
	ld a, -6 (ix)
	cp 23 (iy)		; VDISCARD
	jr nz, ti_nd
	ld a, 0 (iy)
	xor #2
	ld 0 (iy), a
	jp ti_ret1
ti_nd:
	cp 14 (iy)		; VERASE
	jr nz, ti_nk
	ld -8 (ix), #2		; ECHOE
	jp ti_erase
ti_nk:
	cp 16 (iy)		; VKILL
	jr nz, ti_cm
	ld -8 (ix), #4		; ECHOK
	jp ti_erase
ti_cm:
	ld a, -6 (ix)
	cp #0x0a
	jr nz, ti_ins
	ld a, 6 (iy)		; (c_oflag & (OPOST|ONLCR)) == both
	and #5
	cp #5
	jr nz, ti_ins
	ld h, #0x0d
	ld l, 4 (ix)
	push hl
	call _tty_echo
	pop af
ti_ins:
	ld a, -6 (ix)
	push af
	inc sp
	call	ixh_lh_m4
	push hl
	call _insq
	pop af
	inc sp
	ld -8 (ix), l		; wr
	call	ixh_lh_m2
	push hl
	pop iy
	ld a, -8 (ix)
	or a
	jr z, ti_beep
	ld a, -5 (ix)
	or a
	jr z, ti_echo
	ld a, -6 (ix)
	cp 12 (iy)		; VEOF
	jr z, ti_beep
ti_echo:
	ld h, -6 (ix)
	ld l, 4 (ix)
	push hl
	call _tty_echo
	pop af
	jr ti_aft
ti_beep:
	ld h, #7
	ld l, 4 (ix)
	push hl
	call _tty_putc
	pop af
ti_aft:
	call	ixh_lh_m2
	push hl
	pop iy
	ld a, -5 (ix)
	or a
	jr z, ti_wk
	ld a, -6 (ix)
	cp 13 (iy)		; VEOL
	jr z, ti_wk
	cp #0x0a
	jr z, ti_wk
	cp 12 (iy)		; VEOF
	jr nz, ti_fin
ti_wk:
	call	ixh_lh_m4
	call	ixh_p1_wakeup
ti_fin:
	ld l, -8 (ix)
	jr ti_out
ti_erase:
	push ix
	pop hl
	ld de, #-7
	add hl, de
	push hl			; &oc
	call	ixh_lh_m4
	push hl
	call _uninsq
	pop af
	pop af
	ld a, l
	or a
	jr z, ti_ret1
	ld a, -7 (ix)
	cp #0x0a
	jr z, ti_put
	call	ixh_lh_m2
	push hl
	pop iy
	cp 13 (iy)		; VEOL
	jr nz, ti_np
ti_put:
	ld a, -7 (ix)
	push af
	inc sp
	call	ixh_lh_m4
	push hl
	call _insq
	pop af
	inc sp
	jr ti_ret1
ti_np:
	ld a, 10 (iy)		; c_lflag & wr
	and -8 (ix)
	jr z, ti_nc
	ld a, 4 (ix)
	push af
	inc sp
	call _tty_erase
	inc sp
ti_nc:
	ld a, -8 (ix)
	cp #2			; ECHOE: only one char
	jr z, ti_ret1
	jr ti_erase
ti_ret1:
	ld l, #1
ti_out:
	jp	ixh_leave

	.globl _tty_read, _remq, _uputc, _ptimer_insert, _tty_data_consumed
; int tty_read(uint8 minor, uint8 rawflag, uint8 flag)
; locals: -2 t, -4 q, -5 c, -6 n
_tty_read::
	call ___sdcc_enter_ix
	ld hl, #-6
	add hl, sp
	ld sp, hl
	ld l, 4 (ix)
	ld h, #0
	ld e, l
	ld d, h
	add hl, hl
	add hl, hl
	add hl, hl
	add hl, hl
	add hl, hl
	push de
	ld de, #_ttydata
	add hl, de
	ld -2 (ix), l
	ld -1 (ix), h
	pop de
	ld l, e
	ld h, d
	add hl, hl
	add hl, de
	add hl, hl
	add hl, hl
	ld de, #_ttyinq
	add hl, de
	ld -4 (ix), l
	ld -3 (ix), h
tr_loop:
	ld hl, (_udata + 0x99)	; u_done >= u_count ?
	ld de, (_udata + 0x64)
	or a
	sbc hl, de
	jp nc, tr_out
tr_inner:
	call	ixh_lh_m2
	bit 2, (hl)		; TTYF_DEAD && queue empty
	jr z, tr_nd
	call	ixh_lh_m4
	ld de, #8
	add hl, de
	ld a, (hl)
	inc hl
	or (hl)
	jp z, tr_dead
tr_nd:
	push ix
	pop hl
	ld de, #-5
	add hl, de
	push hl			; &c
	call	ixh_lh_m4
	push hl
	call _remq
	pop af
	pop af
	bit 0, l
	jr z, tr_nodata
	ld a, (_udata + 0x6c)	; u_sysio
	ld hl, (_udata + 0x62)
	bit 0, a
	jr z, tr_user
	ld a, -5 (ix)
	ld (hl), a
	jp tr_got
tr_user:
	ld c, -5 (ix)
	ld b, #0
	push hl
	push bc
	call _uputc
	pop af
	pop af
	jr tr_got
tr_nodata:
	call	ixh_lh_m2
	push hl
	pop iy
	bit 4, 10 (iy)		; ICANON
	jr nz, tr_sleep
	ld a, 13 (iy)		; n = VTIME
	ld -6 (ix), a
	ld hl, (_udata + 0x99)
	ld a, h
	or l
	jr nz, tr_chk
	ld a, -6 (ix)
	or a
	jr nz, tr_n
tr_chk:
	ld hl, (_udata + 0x99)	; done >= VMIN ?
	ld e, 12 (iy)
	ld d, #0
	or a
	sbc hl, de
	jp nc, tr_out
tr_n:
	ld a, -6 (ix)
	or a
	jr z, tr_sleep
	ld hl, (_udata + 0)
	ld de, #0x23		; p_timeout = n + 1
	add hl, de
	ld c, -6 (ix)
	ld b, #0
	inc bc
	ld (hl), c
	inc hl
	ld (hl), b
	call _ptimer_insert
tr_sleep:
	ld a, 6 (ix)
	push af
	inc sp
	call	ixh_lh_m4
	push hl
	call _psleep_flags_io
	pop af
	inc sp
	ld a, h
	or l
	jp nz, tr_out
	ld hl, (_udata + 0)	; timer expired (p_timeout == 1)
	ld de, #0x23
	add hl, de
	ld c, (hl)
	inc hl
	ld b, (hl)
	ld a, c
	dec a
	or b
	jp z, tr_out
	jp tr_inner
tr_got:
	ld hl, (_udata + 0x99)
	inc hl
	ld (_udata + 0x99), hl
	call	ixh_lh_m2
	push hl
	pop iy
	bit 4, 10 (iy)		; ICANON
	jr z, tr_next
	ld a, l			; done == 1 ?
	ld hl, (_udata + 0x99)
	ld a, l
	dec a
	or h
	jr nz, tr_nz
	ld a, -5 (ix)
	cp 12 (iy)		; VEOF
	jr nz, tr_nz
	ld hl, #0
	ld (_udata + 0x99), hl	; ^D: nothing read
	jr tr_out
tr_nz:
	ld a, -5 (ix)
	cp #0x0a
	jr z, tr_out
	cp 13 (iy)		; VEOL
	jr z, tr_out
tr_next:
	ld hl, (_udata + 0x62)
	inc hl
	ld (_udata + 0x62), hl
	jp tr_loop
tr_out:
	ld a, 4 (ix)
	push af
	inc sp
	call _tty_data_consumed
	inc sp
	call	ixh_lh_m4
	ld de, #8
	add hl, de
	call	ixh_p1_wakeup
	ld hl, (_udata + 0x99)
	jr tr_ret
tr_dead:
	ld hl, #6		; ENXIO
	ld (_udata + 0x0c), hl
	ld hl, #0xffff
tr_ret:
	jp	ixh_leave

	.globl _tty_open, _tty_post, _tty_close, _tty_setup, _tty_carrier, _psleep_flags
	.globl ___hard_di, ___hard_irqrestore
; helper: A = minor -> HL = &ttydata[minor]
to_t:
	ld l, a
	ld h, #0
	add hl, hl
	add hl, hl
	add hl, hl
	add hl, hl
	add hl, hl
	ld de, #_ttydata
	add hl, de
	ret

; int tty_open(uint8 minor, uint16 flag)  locals: -2 irq, -4 t
_tty_open::
	call ___sdcc_enter_ix
	push af
	push af
	ld a, #1
	sub 4 (ix)
	jr nc, to_ok
	ld hl, #0x13		; ENODEV
	ld (_udata + 0x0c), hl
	jp to_fail
to_ok:
	ld a, 4 (ix)
	call to_t
	ld -4 (ix), l
	ld -3 (ix), h
	inc hl
	ld a, (hl)		; users
	or a
	jr z, to_new
	dec hl
	bit 2, (hl)		; DEAD
	jr z, to_inc
	ld hl, #6		; ENXIO
	ld (_udata + 0x0c), hl
	jp to_fail
to_inc:
	inc hl
	inc (hl)
	jp to_ok0
to_new:
	dec hl
	res 2, (hl)
	xor a
	push af
	inc sp
	ld a, 4 (ix)
	push af
	inc sp
	call _tty_setup
	pop af
	call	ixh_lh_m4
	ld de, #9		; c_cflag high byte
	add hl, de
	bit 3, (hl)		; CLOCAL
	jr nz, to_out
	bit 4, 5 (ix)		; O_NDELAY
	jr nz, to_out
	call ___hard_di
	ld -2 (ix), l
	ld -1 (ix), h
	ld a, 4 (ix)
	push af
	inc sp
	call _tty_carrier
	inc sp
	ld a, h
	or l
	jr nz, to_car
	ld h, 5 (ix)
	ld l, -4 (ix)		; dummy; rebuilt below
	ld a, 5 (ix)
	push af
	inc sp
	call	ixh_lh_m4
	ld de, #8
	add hl, de
	push hl
	call _psleep_flags
	pop af
	inc sp
	ld a, h
	or l
	jr z, to_car
	call	ixh_lh_m2
	call	ixh_p1___hard_irqrestore
	jp to_fail
to_car:
	call	ixh_lh_m2
	call	ixh_p1___hard_irqrestore
	call	ixh_lh_m4
	bit 2, (hl)
	jr z, to_out
	ld hl, #6
	ld (_udata + 0x0c), hl
	call	ixh_lh_m4
	res 2, (hl)
	jr to_fail
to_out:
	call	ixh_lh_m4
	inc hl
	inc (hl)
to_ok0:
	ld hl, #0
	jr to_ret
to_fail:
	ld hl, #0xffff
to_ret:
	jp	ixh_leave

; void tty_post(inoptr ino, uint8 minor, uint16 flag)  local -2 irq
_tty_post::
	call ___sdcc_enter_ix
	push af
	ld a, 6 (ix)
	call to_t
	push hl
	call ___hard_di
	ld -2 (ix), l
	ld -1 (ix), h
	pop de			; de = t
	ld a, (de)
	bit 2, a
	jr nz, tpo_end
	ld hl, (_udata + 0)
	inc hl
	inc hl
	ld a, (hl)		; p_tty
	or a
	jr nz, tpo_end
	inc de
	inc de
	ld a, (de)		; pgrp
	inc de
	ld b, a
	ld a, (de)
	or b
	jr nz, tpo_end
	dec de
	bit 3, 8 (ix)		; O_NOCTTY
	jr nz, tpo_end
	ld a, 6 (ix)
	ld (hl), a
	ld hl, #(_udata + 0x8f)
	ld a, 4 (ix)
	ld (hl), a
	inc hl
	ld a, 5 (ix)
	ld (hl), a
	ld hl, (_udata + 0)
	ld bc, #0x41
	add hl, bc
	ld c, (hl)
	inc hl
	ld b, (hl)
	ld a, c
	ld (de), a
	inc de
	ld a, b
	ld (de), a
tpo_end:
	call	ixh_lh_m2
	call	ixh_p1___hard_irqrestore
	jp	ixh_leave

; int tty_close(uint8 minor)
_tty_close::
	ld hl, #2
	add hl, sp
	ld a, (hl)
	call to_t
	ex de, hl		; de = t
	ld l, e
	ld h, d
	inc hl
	dec (hl)
	jr z, tc_last
	ld hl, #0
	ret
tc_last:
	ld hl, (_udata + 0)
	inc hl
	inc hl
	ld a, (hl)
	ld c, a
	ld hl, #2
	add hl, sp
	ld a, (hl)
	cp c
	jr nz, tc_np
	ld hl, (_udata + 0)
	inc hl
	inc hl
	ld (hl), #0
	ld hl, #0
	ld (_udata + 0x8f), hl
tc_np:
	ld l, e
	ld h, d
	inc hl
	inc hl
	xor a
	ld (hl), a
	inc hl
	ld (hl), a
	ld a, (de)
	res 2, a
	ld (de), a
	ld hl, #0
	ret

	.globl _tty_outproc
	.globl _tty_exit, _tty_hangup, _tty_carrier_drop, _tty_carrier_raise, _sgrpsig, _ttyinq
; void tty_exit(void)
_tty_exit::
	ld hl, (_udata + 0)
	push hl
	pop iy
	ld a, 2 (iy)		; p_tty
	or a
	ret z
	call to_t
	inc hl
	inc hl			; &pgrp
	ld e, (hl)
	inc hl
	ld d, (hl)
	dec hl
	ld c, 0x41 (iy)		; p_pgrp
	ld b, 0x42 (iy)
	ld a, e
	cp c
	ret nz
	ld a, d
	cp b
	ret nz
	ld c, 3 (iy)		; p_pid
	ld b, 4 (iy)
	ld a, e
	cp c
	ret nz
	ld a, d
	cp b
	ret nz
	xor a
	ld (hl), a
	inc hl
	ld (hl), a
	ret

; void tty_hangup(uint8 minor)   local -2 t
_tty_hangup::
	call ___sdcc_enter_ix
	ld a, 4 (ix)
	call to_t
	push hl			; -2 t
	inc hl
	ld a, (hl)
	or a
	jr z, th_end
	inc hl
	ld c, (hl)
	inc hl
	ld b, (hl)
	ld a, #1		; SIGHUP
	push af
	inc sp
	push bc
	call _sgrpsig
	pop af
	inc sp
	pop hl
	push hl
	inc hl
	inc hl
	ld c, (hl)
	inc hl
	ld b, (hl)
	ld a, #0x12		; SIGCONT
	push af
	inc sp
	push bc
	call _sgrpsig
	pop af
	inc sp
	pop hl
	push hl
	inc hl
	inc hl
	xor a
	ld (hl), a
	inc hl
	ld (hl), a
	pop hl
	push hl
	set 2, (hl)		; DEAD
	ld l, 4 (ix)
	ld h, #0
	ld e, l
	ld d, h
	add hl, hl
	add hl, de
	add hl, hl
	add hl, hl
	ld de, #_ttyinq
	add hl, de
	call	ixh_p1_wakeup
	pop hl			; t
	push hl
	call	ixh_p1_wakeup
th_end:
	jp	ixh_leave

; void tty_carrier_drop(uint8 minor)
_tty_carrier_drop::
	ld hl, #2
	add hl, sp
	ld a, (hl)
	call to_t
	ld de, #9
	add hl, de
	bit 2, (hl)		; HUPCL
	ret z
	ld hl, #2
	add hl, sp
	ld a, (hl)
	push af
	inc sp
	call _tty_hangup
	inc sp
	ret

; void tty_carrier_raise(uint8 minor)
_tty_carrier_raise::
	ld hl, #2
	add hl, sp
	ld a, (hl)
	call to_t
	ld de, #8
	add hl, de
	call	ixh_p1_wakeup
	ret

; void tty_outproc(uint8 minor)
_tty_outproc::
	ld hl, #2
	add hl, sp
	ld a, (hl)
	call to_t
	call	ixh_p1_wakeup
	ret

; void tty_putc_wait(uint8 minor, uint8 c)  -> tty_putc_maywait(minor, c, 0)
_tty_putc_wait::
	xor a
	push af
	inc sp
	ld hl, #4
	add hl, sp
	ld a, (hl)		; c
	push af
	inc sp
	ld hl, #4
	add hl, sp
	ld a, (hl)		; minor
	push af
	inc sp
	call _tty_putc_maywait
	pop af
	inc sp
	ret

	.globl _tty_ioctl, _termios_mask, _tty_ioctl_tm, _uput, _uget, _uputw, _clrq
; int tty_ioctl(uint8 minor, uint16 request, char *data)
; 4 minor, 5/6 request, 7/8 data;  locals: -2 t, -4 mask, -5 waito
_tty_ioctl::
	call ___sdcc_enter_ix
	push af
	push af
	push af
	xor a
	ld -5 (ix), a
	ld a, 4 (ix)
	call to_t
	ld -2 (ix), l
	ld -1 (ix), h
	bit 2, (hl)		; DEAD
	jr z, ti_live
	ld hl, #6		; ENXIO
	ld (_udata + 0x0c), hl
	jp ti_fail
ti_live:
	ld a, 6 (ix)
	or a
	jp nz, ti_enotty
	ld a, 5 (ix)
	cp #1			; TCGETS
	jr z, ti_getsa
	cp #2			; TCSETS
	jp z, ti_sets
	cp #3			; TCSETSW
	jp z, ti_setsw
	cp #4			; TCSETSF
	jp z, ti_setsf
	cp #5			; TIOCINQ
	jp z, ti_inq
	cp #6			; TIOCFLUSH
	jp z, ti_flush
	cp #7			; TIOCHANGUP
	jp z, ti_hup
	cp #8			; TIOCOSTOP
	jp z, ti_ostop
	cp #9			; TIOCOSTART
	jp z, ti_ostart
	cp #10			; TIOCGWINSZ
	jp z, ti_gws
	cp #11			; TIOCSWINSZ
	jp z, ti_sws
	cp #12			; TIOCGPGRP
	jp z, ti_gpg
ti_enotty:
	ld hl, #0x19
	ld (_udata + 0x0c), hl
ti_fail:
	ld hl, #0xffff
	jp ti_ret
ti_getsa:
	ld hl, #20
	push hl
	call	ixh_lh_p7
	push hl
	call	ixh_lh_m2
	inc hl
	inc hl
	inc hl
	inc hl
	push hl
	call _uput
ti_ret3:
	pop af
	pop af
	pop af
	jp ti_ret
ti_setsf:
	call ti_clrq
ti_setsw:
	ld a, #1
	ld -5 (ix), a
ti_sets:
	ld l, 4 (ix)
	ld h, #0
	add hl, hl
	ld de, #_termios_mask
	add hl, de
	ld a, (hl)
	ld -4 (ix), a
	inc hl
	ld a, (hl)
	ld -3 (ix), a
	ld hl, #20
	push hl
	ld hl, #_tty_ioctl_tm
	push hl
	call	ixh_lh_p7
	push hl
	call _uget
	pop af
	pop af
	pop af
	ld a, l
	and h
	inc a			; 0xffff -> A=0
	jp z, ti_fail
	call	ixh_lh_m2
	ld de, #12
	add hl, de
	ex de, hl
	ld hl, #(_tty_ioctl_tm + 8)
	ld bc, #12
	ldir			; c_cc
	call	ixh_lh_m2
	push hl
	pop iy
	ld hl, (_tty_ioctl_tm + 0)
	ld 4 (iy), l		; c_iflag
	ld 5 (iy), h
	ld hl, (_tty_ioctl_tm + 2)
	ld 6 (iy), l		; c_oflag
	ld 7 (iy), h
	ld hl, (_tty_ioctl_tm + 6)
	ld 10 (iy), l		; c_lflag
	ld 11 (iy), h
	ld a, -4 (ix)		; cflag = (old & ~mask) | (new & mask)
	ld c, a
	cpl
	and 8 (iy)
	ld e, a
	ld hl, (_tty_ioctl_tm + 4)
	ld a, l
	and c
	or e
	ld 8 (iy), a
	ld a, -3 (ix)
	ld c, a
	cpl
	and 9 (iy)
	ld e, a
	ld a, h
	and c
	or e
	ld 9 (iy), a
	ld a, -5 (ix)
	push af
	inc sp
	ld a, 4 (ix)
	push af
	inc sp
	call _tty_setup
	pop af
	jp ti_zero
ti_inq:
	ld hl, #2
	push hl
	call	ixh_lh_p7
	push hl
	call ti_qaddr
	ld de, #8
	add hl, de
	push hl
	call _uput
	jp ti_ret3
ti_flush:
	call ti_clrq
	jp ti_zero
ti_hup:
	ld a, 4 (ix)
	push af
	inc sp
	call _tty_hangup
	inc sp
	jp ti_zero
ti_ostop:
	call	ixh_lh_m2
	set 0, (hl)
	jp ti_zero
ti_ostart:
	call	ixh_lh_m2
	res 0, (hl)
	jp ti_zero
ti_gws:
	ld hl, #8
	push hl
	call	ixh_lh_p7
	push hl
	call	ixh_lh_m2
	ld de, #0x18
	add hl, de
	push hl
	call _uput
	jp ti_ret3
ti_sws:
	ld hl, #8
	push hl
	call	ixh_lh_m2
	ld de, #0x18
	add hl, de
	push hl
	call	ixh_lh_p7
	push hl
	call _uget
	pop af
	pop af
	pop af
	ld a, h
	or l
	jp nz, ti_fail
	call	ixh_lh_m2
	inc hl
	inc hl
	ld c, (hl)
	inc hl
	ld b, (hl)
	ld a, #0x1c		; SIGWINCH
	push af
	inc sp
	push bc
	call _sgrpsig
	pop af
	inc sp
	jp ti_zero
ti_gpg:
	call	ixh_lh_p7
	push hl
	call	ixh_lh_m2
	inc hl
	inc hl
	ld c, (hl)
	inc hl
	ld b, (hl)
	push bc
	call _uputw
	pop af
	pop af
	jr ti_ret
ti_zero:
	ld hl, #0
ti_ret:
	jp	ixh_leave
; HL = &ttyinq[minor]
ti_qaddr:
	ld l, 4 (ix)
	ld h, #0
	ld e, l
	ld d, h
	add hl, hl
	add hl, de
	add hl, hl
	add hl, hl
	ld de, #_ttyinq
	add hl, de
	ret
ti_clrq:
	call ti_qaddr
	push hl
	call _clrq
	pop af
	ret
