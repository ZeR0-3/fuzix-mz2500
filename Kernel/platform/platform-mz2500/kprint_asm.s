; Hand written kernel console print helpers (kputs, kputhex, kputhexbyte,
; kputunum, kputnum, kprintf) from devio.c.
; SDCC convention: arguments on the stack (right to left, caller pops), result in HL,
; IX preserved, everything else may be destroyed. char arguments are pushed as a
; single byte (push af / inc sp).
	.module kprint_asm
	.globl _kputchar
	.globl _kputs, _kputhex, _kputhexbyte, _kputunum, _kputnum, _kprintf
	.area _CODE

; print the low nibble of A as a hex digit
k_pd0:
	and #0x0f
	ld hl, #k_hex
	ld e, a
	ld d, #0
	add hl, de
	ld a, (hl)
	push af
	inc sp
	call _kputchar
	inc sp
	ret
k_hex:	.ascii "0123456789ABCDEF"

; void kputs(const char *p)
_kputs::
	pop de
	pop bc
	push bc
	push de
ks_l:
	ld a, (bc)
	or a
	ret z
	inc bc
	push bc
	push af
	inc sp
	call _kputchar
	inc sp
	pop bc
	jr ks_l

; void kputhex(unsigned int v)
_kputhex::
	call	ixh_sp2_ed
	push de			; value at (sp) low, (sp+1) high
	ld hl, #1
	add hl, sp
	ld a, (hl)
	rrca
	rrca
	rrca
	rrca
	call k_pd0
	ld hl, #1
	add hl, sp
	ld a, (hl)
	call k_pd0
	ld hl, #0
	add hl, sp
	ld a, (hl)
	rrca
	rrca
	rrca
	rrca
	call k_pd0
	ld hl, #0
	add hl, sp
	ld a, (hl)
	call k_pd0
	pop de
	ret

; void kputhexbyte(unsigned int v)
_kputhexbyte::
	ld hl, #2
	add hl, sp
	ld a, (hl)
	push af
	rrca
	rrca
	rrca
	rrca
	call k_pd0
	pop af
	call k_pd0
	ret

; void kputunum(unsigned int v)   locals: -2 value, -3 flag, -5 table ptr
_kputunum::
	call ___sdcc_enter_ix
	push af
	push af
	push af
	call	ixh_lh_p4
	ld -2 (ix), l
	ld -1 (ix), h
	xor a
	ld -3 (ix), a
	ld hl, #kd_tab
	ld -5 (ix), l
	ld -4 (ix), h
kn_l:
	call	ixh_lh_m5
	ld e, (hl)
	inc hl
	ld d, (hl)
	inc hl
	ld -5 (ix), l
	ld -4 (ix), h
	ld a, d
	or e
	jr z, kn_last
	call	ixh_lh_m2
	ld c, #0
kn_s:
	or a
	sbc hl, de
	jr c, kn_d
	inc c
	jr kn_s
kn_d:
	add hl, de
	ld -2 (ix), l
	ld -1 (ix), h
	ld a, c
	or -3 (ix)
	jr z, kn_l		; leading zero
	ld -3 (ix), a
	ld a, c
	call k_pd0
	jr kn_l
kn_last:
	ld a, -2 (ix)
	call k_pd0
	jp	ixh_leave
kd_tab:	.dw 10000, 1000, 100, 10, 0

; void kputnum(int v)
_kputnum::
	call	ixh_sp2_ed
	bit 7, d
	jr z, kv_pos
	push de
	ld a, #'-'
	push af
	inc sp
	call _kputchar
	inc sp
	pop de
	ld hl, #0
	or a
	sbc hl, de
	ex de, hl
kv_pos:
	push de
	call _kputunum
	pop af
	ret

; void kprintf(const char *fmt, ...)   locals: -2 fmt, -4 ap
_kprintf::
	call ___sdcc_enter_ix
	push af
	push af
	call	ixh_lh_p4
	ld -2 (ix), l
	ld -1 (ix), h
	push ix
	pop hl
	ld de, #6
	add hl, de
	ld -4 (ix), l
	ld -3 (ix), h
kp_l:
	call	ixh_lh_m2
	ld a, (hl)
	or a
	jp z, kp_end
	cp #'%'
	jr nz, kp_ch
	inc hl
	ld -2 (ix), l
	ld -1 (ix), h
	ld a, (hl)
	or a
	jp z, kp_end
	cp #'s'
	jr z, kp_s
	cp #'c'
	jr z, kp_c
	cp #'l'
	jp z, kp_L
	cp #'2'
	jp z, kp_2
	cp #'p'
	jr z, kp_x
	cp #'x'
	jr z, kp_x
	cp #'d'
	jr z, kp_d
	cp #'u'
	jr z, kp_u
kp_ch:				; print *fmt, fmt++
	call	ixh_lh_m2
	ld a, (hl)
	push af
	inc sp
	call _kputchar
	inc sp
kp_n1:
	inc -2 (ix)
	jr nz, kp_l
	inc -1 (ix)
	jr kp_l
kp_s:
	call kp_arg
	call	ixh_p1_kputs
	jr kp_n1
kp_c:
	call kp_arg
	ld a, l
	push af
	inc sp
	call _kputchar
	inc sp
	jr kp_n1
kp_x:
	call kp_arg
	push hl
	call _kputhex
	pop af
	jr kp_n1
kp_d:
	call kp_arg
	push hl
	call _kputnum
	pop af
	jr kp_n1
kp_u:
	call kp_arg
	push hl
	call _kputunum
	pop af
	jr kp_n1
kp_L:
	call	ixh_lh_m4
	inc hl
	inc hl
	ld e, (hl)
	inc hl
	ld d, (hl)
	push de
	call _kputhex		; high word
	pop af
	call	ixh_lh_m4
	ld e, (hl)
	inc hl
	ld d, (hl)
	push de
	call _kputhex		; low word
	pop af
	call	ixh_lh_m4
	ld de, #4
	add hl, de
	ld -4 (ix), l
	ld -3 (ix), h
	jr kp_n2
kp_2:
	call kp_arg
	push hl
	call _kputhexbyte
	pop af
kp_n2:
	inc -2 (ix)		; fmt += 2
	jr nz, kp_n1
	inc -1 (ix)
	jr kp_n1
kp_end:
	jp	ixh_leave
; hl = *ap, ap += 2
kp_arg:
	call	ixh_lh_m4
	ld e, (hl)
	inc hl
	ld d, (hl)
	inc hl
	ld -4 (ix), l
	ld -3 (ix), h
	ex de, hl
	ret
