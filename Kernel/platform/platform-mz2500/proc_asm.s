; Hand written replacements for small hot helpers of process.c.
; SDCC convention: arguments on the stack (right to left, caller pops), result in HL,
; IX preserved, other registers may be destroyed.
; struct p_tab: sizeof 0x4b, p_status +0, p_wait +13
	.module proc_asm
	.globl _int_disabled, _ptab, _ptab_end, _pwake
	.globl _wakeup
	.area _CODE

; void wakeup(void *event)
_wakeup::
	call	ixh_sp2_cb
	di
	ld a, (_int_disabled)
	push af
	ld a, #1
	ld (_int_disabled), a
	ld de, #_ptab
wk_l:
	ld hl, (_ptab_end)
	ld a, e
	sub l
	ld a, d
	sbc a, h
	jr nc, wk_done
	ld a, (de)		; p_status > P_RUNNING ?
	cp #2
	jr c, wk_n
	push de
	pop iy
	ld a, 13 (iy)		; p_wait
	cp c
	jr nz, wk_n
	ld a, 14 (iy)
	cp b
	jr nz, wk_n
	push bc
	push de
	push de
	call _pwake
	pop af
	pop de
	pop bc
wk_n:
	ld hl, #0x4b
	add hl, de
	ex de, hl
	jr wk_l
wk_done:
	di
	pop af
	ld (_int_disabled), a
	or a
	ret nz
	ei
	ret

	.globl _timer_interrupt, _inswap, _udata, _ticks_this_dsecond, _ticks_per_dsecond
	.globl _ticks, _alarms, _ssig, _updatetod, _load_average, _runticks, _nready
	.globl _need_resched, _panic
; void timer_interrupt(void)   locals: -2 q (ptptr *), -4 p
_timer_interrupt::
	call ___sdcc_enter_ix
	push af
	push af
	ld a, (_inswap)
	or a
	jr nz, ti_ds
	ld hl, (_udata + 0)	; u_ptab
	ld a, (hl)
	dec a			; P_RUNNING ?
	jr nz, ti_ds
	ld a, (_udata + 6)	; u_insys
	ld de, #0x31		; p_utime
	bit 0, a
	jr z, ti_cnt
	ld e, #0x35		; p_stime
ti_cnt:
	add hl, de
	inc (hl)
	jr nz, ti_ds
	inc hl
	inc (hl)
	jr nz, ti_ds
	inc hl
	inc (hl)
	jr nz, ti_ds
	inc hl
	inc (hl)
ti_ds:
	ld hl, #_ticks_this_dsecond
	inc (hl)
	ld a, (_ticks_per_dsecond)
	cp (hl)
	jp nz, ti_run
	xor a
	ld (hl), a
	ld hl, #_ticks
	inc (hl)
	jr nz, ti_q
	inc hl
	inc (hl)
	jr nz, ti_q
	inc hl
	inc (hl)
	jr nz, ti_q
	inc hl
	inc (hl)
ti_q:
	ld hl, #_alarms
	ld -2 (ix), l
	ld -1 (ix), h
ti_loop:
	call	ixh_lh_m2
	ld c, (hl)
	inc hl
	ld b, (hl)		; p = *q
	ld a, b
	or c
	jp z, ti_done
	ld -4 (ix), c
	ld -3 (ix), b
	ld a, (bc)
	or a
	jr nz, ti_live
	ld hl, #ti_dead
	call	ixh_p1_panic
	call	ixh_cb_m4
ti_live:
	push bc
	pop iy
	ld l, 9 (iy)		; p_alarm
	ld h, 10 (iy)
	ld a, h
	or l
	jr z, ti_to
	dec hl
	ld 9 (iy), l
	ld 10 (iy), h
	ld a, h
	or l
	jr nz, ti_to
	ld a, #14		; SIGALRM
	push af
	inc sp
	push bc
	call _ssig
	pop af
	inc sp
	call	ixh_cb_m4
	push bc
	pop iy
ti_to:
	ld e, 0x23 (iy)		; p_timeout
	ld d, 0x24 (iy)
	ld a, #1
	cp e
	ld a, #0
	sbc a, d
	jr nc, ti_tq
	dec de
	ld 0x23 (iy), e
	ld 0x24 (iy), d
	ld a, e
	dec a
	or d
	jr nz, ti_tq
	push bc
	call _pwake
	pop af
	call	ixh_cb_m4
	push bc
	pop iy
ti_tq:
	ld e, 0x23 (iy)
	ld d, 0x24 (iy)
	ld a, e
	sub #2
	ld a, d
	sbc a, #0
	jr nc, ti_keep
	ld a, 9 (iy)
	or 10 (iy)
	jr nz, ti_keep
	res 1, 1 (iy)		; ~PFL_ALARM
	ld l, 0x49 (iy)		; p_timerq
	ld h, 0x4a (iy)
	call	ixh_ed_m2
	ex de, hl
	ld (hl), e		; *q = p->p_timerq
	inc hl
	ld (hl), d
	jp ti_loop
ti_keep:
	ld a, c
	add a, #0x49
	ld -2 (ix), a
	ld a, b
	adc a, #0
	ld -1 (ix), a
	jp ti_loop
ti_done:
	call _updatetod
	call _load_average
ti_run:
	ld a, (_inswap)
	or a
	jr nz, ti_end
	ld hl, (_runticks)
	inc hl
	ld (_runticks), hl
	ex de, hl
	ld hl, (_udata + 0)
	ld bc, #0x13		; p_priority
	add hl, bc
	ld c, (hl)
	inc hl
	ld b, (hl)
	ld a, e
	sub c
	ld a, d
	sbc a, b
	jr c, ti_end
	ld a, (_udata + 6)
	bit 0, a
	jr nz, ti_end
	ld a, (_nready)
	cp #2
	jr c, ti_zero
	ld a, #1
	ld (_need_resched), a
	jr ti_end
ti_zero:
	ld hl, #0
	ld (_runticks), hl
ti_end:
	jp	ixh_leave
ti_dead:
	.ascii "dead timer"
	.db 0

	.globl _ssig, _recalc_cursig, _nready
; void ssig(ptptr proc, uint8_t sig)
; p_sig[2] at +0x15: s_pending +0, s_ignored +2, s_held +4 (each 6 bytes)
_ssig::
	call	ixh_sp2_ed
	inc hl
	ld c, (hl)		; c = sig
	push de
	pop iy			; iy = proc
	push iy
	pop hl
	ld de, #0x15
	add hl, de		; hl = &p_sig[0]
	ld a, #15
	cp c
	jr nc, sg_1
	ld de, #6
	add hl, de		; sig > 15: p_sig[1]
sg_1:
	ld a, c
	and #15
	ld de, #1
	jr z, sg_2
	ld b, a
sg_sh:
	sla e
	rl d
	djnz sg_sh
sg_2:				; de = 1 << (sig & 15), hl = m
	di
	ld a, (_int_disabled)
	push af
	ld a, #1
	ld (_int_disabled), a
	ld a, 0 (iy)
	or a
	jp z, sg_done
	set 0, 1 (iy)		; PFL_CHKSIG
	ld a, c
	cp #0x12		; SIGCONT
	jr nz, sg_nc
	ld a, 0 (iy)
	cp #5			; P_STOPPED
	jr nz, sg_c1
	ld 0 (iy), #2		; P_READY
	ld 0x44 (iy), #0	; p_event
	push hl
	ld hl, #_nready
	inc (hl)
	pop hl
sg_c1:
	ld a, 0x1b (iy)		; discard pending stops
	and #0x87
	ld 0x1b (iy), a
sg_nc:
	ld a, c
	cp #0x13		; SIGSTOP..SIGTTOU discard pending CONT
	jr c, sg_ns
	ld a, #0x16
	cp c
	jr c, sg_ns
	res 2, 0x1b (iy)
sg_ns:
	push hl
	inc hl
	inc hl
	ld a, (hl)		; s_ignored & sigm
	and e
	ld b, a
	inc hl
	ld a, (hl)
	and d
	or b
	pop hl
	jr nz, sg_final
	push hl
	ld bc, #4
	add hl, bc
	ld a, (hl)		; s_held & sigm
	and e
	ld b, a
	inc hl
	ld a, (hl)
	and d
	or b
	pop hl
	jr nz, sg_pend
	ld a, 0 (iy)
	cp #3			; P_SLEEP
	jr nz, sg_w
	ld 0 (iy), #2		; P_READY
	push hl
	ld hl, #_nready
	inc (hl)
	pop hl
sg_w:
	xor a
	ld 13 (iy), a		; p_wait = NULL
	ld 14 (iy), a
sg_pend:
	ld a, (hl)
	or e
	ld (hl), a
	inc hl
	ld a, (hl)
	or d
	ld (hl), a
sg_final:
	ld a, 0 (iy)
	cp #2			; P_READY: if it is us, we are running
	jr nz, sg_done
	ld hl, (_udata + 0)
	push iy
	pop de
	or a
	sbc hl, de
	jr nz, sg_done
	ld 0 (iy), #1		; P_RUNNING
sg_done:
	di
	pop af
	ld (_int_disabled), a
	or a
	ret nz
	ei
	ret

; void recalc_cursig(void)
_recalc_cursig::
	ld a, (_udata + 0x11)	; u_cursig
	or a
	jr z, rc_end
	ld hl, (_udata + 0)
	ld de, #0x15
	add hl, de
	bit 4, a
	jr z, rc_1
	ld de, #6
	add hl, de
	res 4, a
	ld (_udata + 0x11), a
rc_1:
	ld de, #1
	or a
	jr z, rc_2
	ld b, a
rc_sh:
	sla e
	rl d
	djnz rc_sh
rc_2:
	ld a, (hl)
	or e
	ld (hl), a
	inc hl
	ld a, (hl)
	or d
	ld (hl), a
	xor a
	ld (_udata + 0x11), a
rc_end:
	ld hl, (_udata + 0)
	inc hl
	set 0, (hl)
	ret

	.globl _ptab_alloc, _nextpid, _nproc, _pagemap_alloc
; ptptr ptab_alloc(void)
; p_pid +3, p_name +0x25 (8), p_pgrp +0x41, p_top +0x45
_ptab_alloc::
	ld hl, #11		; EAGAIN
	ld (_udata + 0x0c), hl
	di
	ld a, (_int_disabled)
	push af
	ld a, #1
	ld (_int_disabled), a
	ld de, #_ptab
pa_l:
	ld hl, (_ptab_end)
	ld a, e
	sub l
	ld a, d
	sbc a, h
	jp nc, pa_none
	ld a, (de)
	or a
	jr z, pa_found
	ld hl, #0x4b
	add hl, de
	ex de, hl
	jr pa_l
pa_found:
	push de			; newp
	push de
	pop iy
	ld l, e
	ld h, d
	ld b, #0x4b
	xor a
pa_z:
	ld (hl), a
	inc hl
	djnz pa_z
pa_pid:
	ld a, 3 (iy)
	or 4 (iy)
	jr nz, pa_pidok
	ld hl, (_nextpid)
	inc hl
	ld a, h
	cp #0x7d		; MAXPID = 32000
	jr c, pa_np
	ld hl, #20
pa_np:
	ld (_nextpid), hl
	ld 3 (iy), l
	ld 4 (iy), h
	ld de, #_ptab
	ld bc, (_ptab_end)
pa_cl:
	ld a, e
	sub c
	ld a, d
	sbc a, b
	jr nc, pa_pid
	ld a, (de)
	or a
	jr z, pa_cn
	push de
	inc de
	inc de
	inc de
	ld a, (de)
	cp l
	jr nz, pa_cx
	inc de
	ld a, (de)
	cp h
	jr nz, pa_cx
	pop de
	xor a
	ld 3 (iy), a		; clash: try again
	ld 4 (iy), a
	jr pa_pid
pa_cx:
	pop de
pa_cn:
	push hl
	ld hl, #0x4b
	add hl, de
	ex de, hl
	pop hl
	jr pa_cl
pa_pidok:
	ld hl, (_udata + 0x1c)	; u_top
	ld 0x45 (iy), l
	ld 0x46 (iy), h
	ld hl, (_udata + 0)	; u_ptab: forking?
	ld a, h
	or l
	jr z, pa_pm
	push hl
	ld de, #0x41		; p_pgrp
	add hl, de
	ld a, (hl)
	ld 0x41 (iy), a
	inc hl
	ld a, (hl)
	ld 0x42 (iy), a
	pop hl
	ld de, #0x25		; p_name
	add hl, de
	push iy
	pop de
	push hl
	ld hl, #0x25
	add hl, de
	ex de, hl
	pop hl
	ld bc, #8
	ldir
pa_pm:
	pop hl			; newp
	push hl
	push hl
	call _pagemap_alloc
	pop af
	ld a, h
	or l
	jr nz, pa_nomem
	pop hl
	push hl
	ld (hl), #6		; P_FORKING
	ld hl, (_nproc)
	inc hl
	ld (_nproc), hl
	ld hl, #0
	ld (_udata + 0x0c), hl
	pop de			; return newp
	jr pa_ret
pa_nomem:
	ld hl, #12		; ENOMEM
	ld (_udata + 0x0c), hl
	pop af
pa_none:
	ld de, #0
pa_ret:
	di
	pop af
	ld (_int_disabled), a
	or a
	ex de, hl
	ret nz
	ei
	ret

	.globl _chksigs, _doexit, _switchout, _udata, _nready, _need_resched, ___hard_di
; uint8 chksigset(struct sigbits *sb, uint8 b)   sb: 4(ix), b: 6(ix)
; sigbits: pending +0, ignored +2, held +4.  u_sigvec = udata+34
; locals: -2/-1 pending, -3 j, -5/-4 svec, -7/-6 m, -8 spare
_chksigset::
	call ___sdcc_enter_ix
	push af
	push af
	push af
	push af
	call	ixh_lh_p4
	push hl
	pop iy
	ld a, 4 (iy)
	cpl
	and 0 (iy)
	ld -2 (ix), a
	ld a, 5 (iy)
	cpl
	and 1 (iy)
	ld -1 (ix), a
	or -2 (ix)
	jr nz, cs_go
	ld hl, #0
	jp cs_ret
cs_go:
	ld -3 (ix), #1
	ld hl, #(_udata + 34)
	ld -7 (ix), #2
	ld -6 (ix), #0
	ld a, 6 (ix)
	dec a
	jr nz, cs_set
	ld -3 (ix), a		; j = 0
	ld hl, #(_udata + 64)
	ld -7 (ix), #1
cs_set:
	ld -5 (ix), l
	ld -4 (ix), h
cs_loop:
	ld a, -3 (ix)
	cp #16
	jp nc, cs_end
	call	ixh_lh_m5
	inc hl
	inc hl
	ld -5 (ix), l
	ld -4 (ix), h
	ld a, -7 (ix)
	and -2 (ix)
	ld c, a
	ld a, -6 (ix)
	and -1 (ix)
	or c
	jp z, cs_next
	ld e, (hl)
	inc hl
	ld d, (hl)
	ld a, d
	or e
	jr nz, cs_nodfl
	ld a, 6 (ix)		; SIG_DFL
	or a
	jr z, cs_notstop
	ld a, -7 (ix)
	and #0x78		; stopper
	jr z, cs_notstop
	call ___hard_di
	ld hl, (_udata + 0)
	ld (hl), #5		; P_STOPPED
	ld de, #0x44
	add hl, de
	ld a, -3 (ix)
	ld (hl), a		; p_event = j
	call cs_clrpend
	ld a, (_udata + 0x10)	; u_ininterrupt
	bit 0, a
	jr z, cs_sw
	ld a, #1
	ld (_need_resched), a
	jr cs_ff
cs_sw:
	call _switchout
cs_ff:
	ld hl, #0xff
	jp cs_ret
cs_notstop:
	call cs_clrpend
	ld a, 6 (ix)
	or a
	jr z, cs_pid
	ld a, -7 (ix)
	and #0xfe
	ld c, a
	ld a, -6 (ix)
	and #0x30
	or c			; (m & 0x30fe)
	jr nz, cs_next
cs_pid:
	ld hl, (_udata + 0)
	inc hl
	inc hl
	inc hl
	ld e, (hl)
	inc hl
	ld d, (hl)
	ld a, e
	dec a
	or d
	jr z, cs_next		; pid == 1
	ld hl, (_udata + 0)
	ld a, (hl)
	cp #3			; P_SLEEP
	jr nz, cs_exit
	ld (hl), #1		; P_RUNNING
	ld hl, #_nready
	inc (hl)
cs_exit:
	ld l, -3 (ix)
	ld h, #0
	push hl
	call _doexit
	pop af
	jr cs_next
cs_nodfl:
	ld a, e			; SIG_IGN == 1
	dec a
	or d
	jr z, cs_next
	call cs_clrpend
	ld a, 6 (ix)
	add a, a
	add a, a
	add a, a
	add a, a
	add a, -3 (ix)
	ld (_udata + 0x11), a	; u_cursig
	jr cs_end
cs_next:
	inc -3 (ix)
	sla -7 (ix)
	rl -6 (ix)
	jp cs_loop
cs_end:
	ld a, (_udata + 0x11)
	ld l, a
	ld h, #0
cs_ret:
	jp	ixh_leave
; sb->s_pending &= ~m
cs_clrpend:
	call	ixh_lh_p4
	ld a, -7 (ix)
	cpl
	and (hl)
	ld (hl), a
	inc hl
	ld a, -6 (ix)
	cpl
	and (hl)
	ld (hl), a
	ret

; uint8 chksigs(void)
_chksigs::
	ld hl, (_udata + 0)
	ld a, (hl)
	cp #4			; P_IOWAIT
	jr nz, ck_re
	call _recalc_cursig
	ld hl, #0
	ret
ck_re:
	ld a, (_udata + 0x11)
	or a
	jr nz, ck_retc
	ld hl, (_udata + 0)
	inc hl
	bit 0, (hl)		; PFL_CHKSIG
	jr z, ck_retc
	dec hl
	ld a, (hl)
	cp #5			; P_STOPPED
	jr z, ck_retc
	ld hl, (_udata + 0)
	ld de, #0x15
	add hl, de
	xor a
	push af
	inc sp
	push hl
	call _chksigset
	pop af
	inc sp
	ld a, l
	cp #0xff
	jr z, ck_re
	or a
	jr nz, ck_retc
	ld hl, (_udata + 0)
	ld de, #0x1b
	add hl, de
	ld a, #1
	push af
	inc sp
	push hl
	call _chksigset
	pop af
	inc sp
	ld a, l
	cp #0xff
	jr z, ck_re
	or a
	jr nz, ck_retc
	ld hl, (_udata + 0)
	inc hl
	res 0, (hl)
	ld hl, #0
	ret
ck_retc:
	ld a, (_udata + 0x11)
	ld l, a
	ld h, #0
	ret

	.globl _psleep, _psleep_nosig, _ptimer_insert, _sgrpsig, _waitno, _alarms
; void psleep(void *event) / psleep_nosig(void *event)
_psleep::
	ld a, #3		; P_SLEEP
	jr ps_common
_psleep_nosig::
	ld a, #4		; P_IOWAIT
ps_common:
	push af
	call ___hard_di
	pop af
	ld c, a
	ld hl, (_udata + 0)
	ld a, (hl)
	cp #1			; P_RUNNING
	jr z, ps_set
	cp #3
	jr z, ps_inc
	cp #4
	jr z, ps_inc
	cp #5
	jr nz, ps_voodoo
ps_inc:
	ld hl, #_nready
	inc (hl)
ps_set:
	call	ixh_sp2_ed
	ld hl, (_udata + 0)
	ld (hl), c		; p_status = state
	ld bc, #0x0d
	add hl, bc
	ld (hl), e		; p_wait
	inc hl
	ld (hl), d
	ld hl, (_waitno)
	inc hl
	ld (_waitno), hl
	ex de, hl
	ld hl, (_udata + 0)
	ld bc, #0x21
	add hl, bc
	ld (hl), e		; p_waitno
	inc hl
	ld (hl), d
	jp _switchout
ps_voodoo:
	ld hl, #ps_str
	call	ixh_p1_panic
	ret
ps_str:
	.ascii "psleep: voodoo"
	.db 0

; void pwake(ptptr p)
_pwake::
	call	ixh_sp2_cb
	ld a, (bc)
	cp #2
	jr z, pw_clr
	jr c, pw_end		; <= RUNNING: nothing
	cp #5
	jr nc, pw_end		; >= STOPPED
	ld hl, #_nready
	inc (hl)
	ld a, #2		; P_READY
	ld (bc), a
pw_clr:
	ld hl, #0x0d
	add hl, bc
	xor a
	ld (hl), a
	inc hl
	ld (hl), a
pw_end:
	ret

; void ptimer_insert(void)
_ptimer_insert::
	ld hl, (_udata + 0)
	ld e, l
	ld d, h
	inc de
	ld a, (de)
	bit 1, a		; PFL_ALARM
	ret nz
	ld bc, #0x49
	add hl, bc
	ld bc, (_alarms)
	ld (hl), c
	inc hl
	ld (hl), b
	ld hl, (_udata + 0)
	ld (_alarms), hl
	ld a, (de)
	set 1, a
	ld (de), a
	ret

; void sgrpsig(uint16 pgrp, uint8 sig)   pgrp 4(ix), sig 6(ix)
_sgrpsig::
	call ___sdcc_enter_ix
	ld a, 4 (ix)
	or 5 (ix)
	jr z, sgp_end
	ld de, #_ptab
sgp_loop:
	ld hl, #_ptab_end
	ld a, e
	sub (hl)
	inc hl
	ld a, d
	sbc a, (hl)
	jr nc, sgp_end
	ld hl, #0x41
	add hl, de
	ld a, (hl)
	cp 4 (ix)
	jr nz, sgp_next
	inc hl
	ld a, (hl)
	cp 5 (ix)
	jr nz, sgp_next
	push de
	ld a, 6 (ix)
	push af
	inc sp
	push de
	call _ssig
	pop af
	inc sp
	pop de
sgp_next:
	ld hl, #0x4b
	add hl, de
	ex de, hl
	jr sgp_loop
sgp_end:
	pop ix
	ret

	.globl _switchout, _plt_idle, _plt_switchout, ___hard_ei
; void switchout(void)
_switchout::
	call ___hard_di
	ld hl, (_udata + 0)
	ld a, #2
	sub (hl)
	jr nc, so_1
	ld hl, #_nready
	dec (hl)		; status > P_READY
so_1:
	call _chksigs
	ld a, l
	or a
	jr z, so_idle
	ld hl, (_udata + 0)
	ld a, #2
	sub (hl)
	jr nc, so_2
	ld hl, #_nready
	inc (hl)
so_2:
	ld hl, (_udata + 0)
	ld (hl), #1		; P_RUNNING
	call ___hard_ei
so_idle:
	ld a, (_nready)
	or a
	jr nz, so_run
	call ___hard_ei
	call _plt_idle
	call ___hard_di
	jr so_idle
so_run:
	ld hl, (_udata + 0)
	ld a, (hl)
	cp #1
	jr z, so_chk
	cp #2
	jp nz, _plt_switchout
so_chk:
	ld a, (_nready)
	dec a
	jr nz, so_sw
	ld (hl), #1
	jp ___hard_ei
so_sw:
	ld (hl), #2		; P_READY
	jp _plt_switchout

	.globl _getproc, _getproc_nextp
; ptptr getproc(void)   -- round-robin scheduler
_getproc::
	ld hl, (_getproc_nextp)
	push hl			; haltafter
gp_loop:
	ld hl, (_getproc_nextp)
	ld de, #0x4b
	add hl, de
	ld de, (_ptab_end)
	push hl
	or a
	sbc hl, de
	pop hl
	jr c, gp_ok
	ld hl, #_ptab
gp_ok:
	ld (_getproc_nextp), hl
	ld a, (hl)
	dec a			; P_RUNNING?
	jr z, gp_p1
	dec a			; P_READY?
	jr z, gp_ready
gp_next:
	ld hl, #0
	add hl, sp
	ld e, (hl)
	inc hl
	ld d, (hl)
	ld hl, (_getproc_nextp)
	or a
	sbc hl, de
	jr nz, gp_loop
	ld a, (_udata + 0x10)	; u_ininterrupt
	bit 0, a
	jr z, gp_ei
	ld hl, #gp_s2
	call	ixh_p1_panic
gp_ei:
	call ___hard_ei
	call _plt_idle
	jr gp_loop
gp_p1:
	ld hl, #gp_s1
	call	ixh_p1_panic
	ld hl, (_getproc_nextp)
gp_ready:
	inc hl
	bit 2, (hl)		; PFL_BATCH
	jr z, gp_ret
	res 2, (hl)
	jr gp_loop
gp_ret:
	ld hl, (_getproc_nextp)
	pop af
	ret
gp_s1:
	.ascii "getproc: extra running"
	.db 0
gp_s2:
	.ascii "getproc: can't ei"
	.db 0

	.globl _makeproc, _program_vectors, _ticks, _of_tab, ___hard_irqrestore
; void makeproc(ptptr p, u_data *u)   p 4(ix), u 6(ix); local -2 irq
_makeproc::
	call ___sdcc_enter_ix
	push af
	call ___hard_di
	ld -2 (ix), l
	ld -1 (ix), h
	call	ixh_lh_p4
	push hl
	pop iy			; iy = p
	call	ixh_ed_p6
	ld hl, #2
	add hl, de		; &u->u_page
	ld a, 15 (iy)		; p_page
	ld (hl), a
	inc hl
	ld a, 16 (iy)
	ld (hl), a
	inc hl
	ld a, 17 (iy)		; p_page2
	ld (hl), a
	inc hl
	ld a, 18 (iy)
	ld (hl), a
	ld hl, #2
	add hl, de
	push hl
	call _program_vectors
	pop af
	call	ixh_lh_p4
	push hl
	pop iy
	call	ixh_ed_p6
	ld 0 (iy), #1		; P_RUNNING
	ld hl, #_nready
	inc (hl)
	ld a, (de)
	ld c, a
	inc de
	ld a, (de)
	ld b, a
	dec de			; bc = pp = u->u_ptab
	ld 7 (iy), c		; p_pptr
	ld 8 (iy), b
	ld hl, #0x17		; sig[0].s_ignored
	add hl, bc
	ld a, (hl)
	ld 0x17 (iy), a
	inc hl
	ld a, (hl)
	ld 0x18 (iy), a
	ld hl, #0x1d		; sig[1].s_ignored
	add hl, bc
	ld a, (hl)
	ld 0x1d (iy), a
	inc hl
	ld a, (hl)
	ld 0x1e (iy), a
	ld hl, #0x19		; sig[0].s_held
	add hl, bc
	ld a, (hl)
	ld 0x19 (iy), a
	inc hl
	ld a, (hl)
	ld 0x1a (iy), a
	ld hl, #0x1f		; sig[1].s_held
	add hl, bc
	ld a, (hl)
	ld 0x1f (iy), a
	inc hl
	ld a, (hl)
	ld 0x20 (iy), a
	ld hl, #2		; p_tty
	add hl, bc
	ld a, (hl)
	ld 2 (iy), a
	ld hl, #5		; p_uid
	add hl, bc
	ld a, (hl)
	ld 5 (iy), a
	inc hl
	ld a, (hl)
	ld 6 (iy), a
	ld 0x13 (iy), #25	; p_priority = MAXTICKS
	ld 0x14 (iy), #0
	push iy
	pop hl
	ld a, l			; u->u_ptab = p
	ld (de), a
	inc de
	ld a, h
	ld (de), a
	dec de
	ld bc, #0x31		; clear utime/stime/cutime/cstime
	add hl, bc
	ld b, #16
	xor a
mk_clr:
	ld (hl), a
	inc hl
	djnz mk_clr
	push de
	push iy
	pop de
	ld hl, #0x2d		; p_time = ticks.full
	add hl, de
	ex de, hl
	ld hl, #_ticks
	ld bc, #4
	ldir
	pop de
	ld hl, #0x89		; u_cwd
	add hl, de
	ld c, (hl)
	inc hl
	ld b, (hl)
	ld a, b
	or c
	jr z, mk_root
	ld hl, #0x46
	add hl, bc
	inc (hl)
mk_root:
	ld hl, #0x8b		; u_root
	add hl, de
	ld c, (hl)
	inc hl
	ld b, (hl)
	ld a, b
	or c
	jr z, mk_cs
	ld hl, #0x46
	add hl, bc
	inc (hl)
mk_cs:
	ld hl, #0x11		; u_cursig
	add hl, de
	ld (hl), #0
	ld hl, #0x0c		; u_error
	add hl, de
	xor a
	ld (hl), a
	inc hl
	ld (hl), a
	ld hl, #0x7d		; u_files
	add hl, de
	ld b, #10
mk_f:
	ld a, (hl)
	inc hl
	cp #0xff
	jr z, mk_fn
	push hl
	ld l, a
	ld h, #0
	add hl, hl
	add hl, hl
	add hl, hl
	ld de, #(_of_tab + 7)	; o_refs
	add hl, de
	inc (hl)
	pop hl
mk_fn:
	djnz mk_f
	call	ixh_lh_m2
	call	ixh_p1___hard_irqrestore
	jp	ixh_leave

	.globl _doexit, _sync, _pagemap_free, _doclose, _i_deref, _nproc, _tty_exit, _switchin
; static int signal_parent(ptptr c)
signal_parent:
	call	ixh_sp2_cb
	ld hl, #7
	add hl, bc
	ld e, (hl)
	inc hl
	ld d, (hl)		; de = parent
	ld hl, #0x1d		; sig[1].s_ignored
	add hl, de
	bit 1, (hl)		; SIGCHLD ignored?
	jr z, sp_go
	ld hl, (_udata + 0)
	ld (hl), #0		; P_EMPTY
	ld hl, #0
	ret
sp_go:
	push de
	ld a, #0x11		; SIGCHLD
	push af
	inc sp
	push de
	call _ssig
	pop af
	inc sp
	call _wakeup
	pop af
	ld hl, (_udata + 0)
	ld (hl), #7		; P_ZOMBIE
	ld hl, #1
	ret

; void doexit(uint16 val)   locals: -2/-1 irq, -3 j, -4 spare
_doexit::
	call ___sdcc_enter_ix
	push af
	push af
	ld hl, (_udata + 0)
	ld de, #3
	add hl, de
	ld c, (hl)
	inc hl
	ld b, (hl)
	ld a, c
	dec a
	or b
	jr nz, de_1
	ld hl, #de_s1
	call	ixh_p1_panic
de_1:
	call _sync
	call ___hard_di
	ld -2 (ix), l
	ld -1 (ix), h
	ld hl, (_udata + 0)
	ld de, #0x19		; sig[0].s_held
	add hl, de
	ld (hl), #0xff
	inc hl
	ld (hl), #0xff
	ld de, #5		; sig[1].s_held
	add hl, de
	ld (hl), #0xff
	inc hl
	ld (hl), #0xff
	xor a
	ld (_udata + 0x11), a	; u_cursig
	ld hl, (_udata + 0)
	push hl
	call _pagemap_free
	pop af
	xor a
	ld -3 (ix), a
de_f:
	ld e, -3 (ix)
	ld d, #0
	ld hl, #(_udata + 125)	; u_files
	add hl, de
	ld a, (hl)
	inc a
	jr z, de_fn
	ld a, -3 (ix)
	push af
	inc sp
	call _doclose
	inc sp
de_fn:
	inc -3 (ix)
	ld a, -3 (ix)
	cp #10
	jr c, de_f
	ld hl, (_udata + 0)
	ld de, #0x0b		; p_exitval
	add hl, de
	ld a, 4 (ix)
	ld (hl), a
	inc hl
	ld a, 5 (ix)
	ld (hl), a
	ld hl, (_udata + 137)	; u_cwd
	call	ixh_p1_i_deref
	ld hl, (_udata + 139)	; u_root
	call	ixh_p1_i_deref
	ld de, #_ptab
de_l:
	ld hl, (_ptab_end)
	ld a, e
	sub l
	ld a, d
	sbc a, h
	jp nc, de_end
	ld a, (de)
	or a
	jp z, de_n
	ld bc, (_udata + 0)
	ld a, e
	sub c
	jr nz, de_c1
	ld a, d
	sub b
	jp z, de_n
de_c1:
	ld hl, #7		; p_pptr
	add hl, de
	ld a, (hl)
	inc hl
	ld h, (hl)
	ld l, a
	or a
	sbc hl, bc
	jr nz, de_pg
	ld hl, #7
	add hl, de
	ld a, #<(_ptab)
	ld (hl), a
	inc hl
	ld a, #>(_ptab)
	ld (hl), a
	push de
	push de
	call signal_parent
	pop af
	pop de
de_pg:
	ld hl, #0x41		; p_pgrp
	add hl, de
	ld c, (hl)
	inc hl
	ld b, (hl)
	ld hl, (_udata + 0)
	inc hl
	inc hl
	inc hl
	ld a, (hl)
	inc hl
	ld h, (hl)
	ld l, a			; our pid
	or a
	sbc hl, bc
	jr nz, de_tq
	ld hl, #0x41
	add hl, de
	xor a
	ld (hl), a
	inc hl
	ld (hl), a
	push de
	ld a, #1		; SIGHUP
	push af
	inc sp
	push de
	call _ssig
	pop af
	inc sp
	pop de
	push de
	ld a, #0x12		; SIGCONT
	push af
	inc sp
	push de
	call _ssig
	pop af
	inc sp
	pop de
de_tq:
	ld hl, #0x49		; p_timerq
	add hl, de
	ld c, (hl)
	inc hl
	ld b, (hl)
	ld hl, (_udata + 0)
	or a
	sbc hl, bc
	jr nz, de_n
	ld hl, (_udata + 0)
	ld bc, #0x49
	add hl, bc
	ld c, (hl)
	inc hl
	ld b, (hl)
	ld hl, #0x49
	add hl, de
	ld (hl), c
	inc hl
	ld (hl), b
de_n:
	ld hl, #0x4b
	add hl, de
	ex de, hl
	jp de_l
de_end:
	ld hl, (_udata + 0)
	ld bc, (_alarms)
	or a
	sbc hl, bc
	jr nz, de_t
	ld hl, (_udata + 0)
	ld bc, #0x49
	add hl, bc
	ld c, (hl)
	inc hl
	ld b, (hl)
	ld (_alarms), bc
de_t:
	call _tty_exit
	call	ixh_lh_m2
	call	ixh_p1___hard_irqrestore
	ld hl, #0xffff
	ld (_udata + 2), hl	; u_page
	ld (_udata + 4), hl	; u_page2
	ld hl, (_udata + 0)
	push hl
	call signal_parent
	pop af
	ld hl, #_nready
	dec (hl)
	ld hl, (_nproc)
	dec hl
	ld (_nproc), hl
	call _getproc
	push hl
	call _switchin
	ld hl, #de_s2
	ex (sp), hl
	call _panic
	jp	ixh_leave
de_s1:
	.ascii "killed init"
	.db 0
de_s2:
	.ascii "doexit won't exit"
	.db 0

	.globl _unix_syscall, _panic, _exec_or_die, _syscall_dispatch, _loadavg, _kputs, _plt_monitor, __execve, _load_average_utick
; static uint8 utick lives in k_process.s data.
; void load_average(void)   (called every tick) -- struct runload {uint8 exponent; uint16 average;}
_load_average::
	ld hl, #_load_average_utick
	inc (hl)
	ld a, (hl)
	cp #50
	ret c
	ld (hl), #0
	ld a, (_nready)
	ld c, a			; c = nr (low byte)
	ld iy, #_loadavg
	call la_one
	ld iy, #(_loadavg + 3)
	call la_one
	ld iy, #(_loadavg + 6)
la_one:
	ld e, 1 (iy)
	ld a, 2 (iy)
	sub c
	ld d, a			; de = average - (nr << 8)
	ld a, 0 (iy)		; exponent
	ld hl, #0
	ld b, #8
la_m:
	add hl, hl
	rlca
	jr nc, la_s
	add hl, de
la_s:
	djnz la_m
	ld 1 (iy), h		; average = (prod >> 8) | (nr << 8)
	ld 2 (iy), c
	ret

; void unix_syscall(void)
_unix_syscall::
	ld hl, #0
	ld (_udata + 0x0c), hl	; u_error = 0
	ld a, (_udata + 7)	; u_callno
	cp #0x44
	jr c, us_ok
	ld hl, #0x2a		; ENOSYS
	ld (_udata + 0x0c), hl
	jr us_post
us_ok:
	ld l, a
	ld h, #0
	add hl, hl
	ld de, #_syscall_dispatch
	add hl, de
	ld a, (hl)
	inc hl
	ld h, (hl)
	ld l, a
	call us_call
	ld (_udata + 0x0a), hl	; u_retval
	jr us_post
us_call:
	jp (hl)
us_post:
	ld hl, (_udata + 0)
	ld de, #0x23
	add hl, de
	xor a
	ld (hl), a		; p_timeout = 0
	inc hl
	ld (hl), a
	call ___hard_di
	ld hl, (_udata + 0)
	ld de, #0x13
	add hl, de
	ld e, (hl)
	inc hl
	ld d, (hl)		; p_priority
	ld hl, (_runticks)
	or a
	sbc hl, de
	jr c, us_ei
	ld a, (_nready)
	cp #2
	jr c, us_ei
	ld hl, (_udata + 0)
	ld (hl), #2		; P_READY
	call _plt_switchout
us_ei:
	call ___hard_ei
	jp _chksigs

; void panic(char *deathcry)
_panic::
	ld hl, #pn_s
	call	ixh_p1_kputs
	call	ixh_sp2_cb
	push bc
	call _kputs
	pop af
	call _plt_monitor
pn_l:
	jr pn_l
pn_s:
	.db 0x0d, 0x0a
	.ascii "panic: "
	.db 0

; void exec_or_die(void)
_exec_or_die::
	ld hl, #ed_s1
	call	ixh_p1_kputs
	call __execve
	ld hl, #ed_s2
	call	ixh_p1_panic
	ret
ed_s1:
	.ascii "Starting /init"
	.db 0x0a, 0
ed_s2:
	.ascii "no /init"
	.db 0
