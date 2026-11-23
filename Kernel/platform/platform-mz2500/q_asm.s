; Hand written tty queue primitives (insq, remq, uninsq) from devio.c.
; SDCC convention: arguments on the stack (right to left, caller pops), result in L,
; IX preserved, other registers (incl. IY) may be destroyed.
; struct s_queue: q_base +0, q_head +2, q_tail +4, q_size +6, q_count +8, q_wakeup +10
	.module q_asm
	.globl _int_disabled
	.globl _insq, _remq, _uninsq
	.area _CODE

; bool insq(struct s_queue *q, uint8_t c)
_insq::
	call	ixh_sp2_ed
	inc hl
	ld c, (hl)		; c = char
	push de
	pop iy
	di
	ld a, (_int_disabled)
	push af
	ld a, #1
	ld (_int_disabled), a
	ld l, 8 (iy)		; count
	ld h, 9 (iy)
	ld e, 6 (iy)		; size
	ld d, 7 (iy)
	or a
	sbc hl, de
	jr z, iq_full
	ld e, 4 (iy)		; tail
	ld d, 5 (iy)
	ld a, c
	ld (de), a
	inc de
	ld l, 8 (iy)		; ++count
	ld h, 9 (iy)
	inc hl
	ld 8 (iy), l
	ld 9 (iy), h
	ld l, 0 (iy)		; limit = base + size
	ld h, 1 (iy)
	ld c, 6 (iy)
	ld b, 7 (iy)
	add hl, bc
	ld a, e
	sub l
	ld a, d
	sbc a, h
	jr c, iq_st
	ld e, 0 (iy)		; wrap
	ld d, 1 (iy)
iq_st:
	ld 4 (iy), e
	ld 5 (iy), d
	ld l, #1
	jp iq_end
iq_full:
	ld l, #0
iq_end:
	ld h, #0
	di
	pop af
	ld (_int_disabled), a
	or a
	ret nz
	ei
	ret

; bool remq(struct s_queue *q, uint8_t *cp)
_remq::
	call	ixh_sp2_ed
	inc hl
	ld c, (hl)
	inc hl
	ld b, (hl)		; bc = cp
	push de
	pop iy
	di
	ld a, (_int_disabled)
	push af
	ld a, #1
	ld (_int_disabled), a
	ld a, 8 (iy)
	or 9 (iy)
	jp z, rq_empty
	ld l, 2 (iy)		; head
	ld h, 3 (iy)
	ld a, (hl)
	ld (bc), a		; *cp
	inc hl
	ld c, 8 (iy)		; --count
	ld b, 9 (iy)
	dec bc
	ld 8 (iy), c
	ld 9 (iy), b
	ld c, 6 (iy)
	ld b, 7 (iy)
	ld e, 0 (iy)
	ld d, 1 (iy)
	ld a, e			; bc = base + size
	add a, c
	ld c, a
	ld a, d
	adc a, b
	ld b, a
	ld a, l
	sub c
	ld a, h
	sbc a, b
	jr c, rq_st
	ld l, e			; wrap
	ld h, d
rq_st:
	ld 2 (iy), l
	ld 3 (iy), h
	ld l, #1
	jp iq_end
rq_empty:
	ld l, #0
	jp iq_end

; bool uninsq(struct s_queue *q, uint8_t *cp)
_uninsq::
	call	ixh_sp2_ed
	inc hl
	ld c, (hl)
	inc hl
	ld b, (hl)		; bc = cp
	push de
	pop iy
	di
	ld a, (_int_disabled)
	push af
	ld a, #1
	ld (_int_disabled), a
	ld a, 8 (iy)
	or 9 (iy)
	jp z, rq_empty
	push bc			; cp
	ld c, 8 (iy)		; --count
	ld b, 9 (iy)
	dec bc
	ld 8 (iy), c
	ld 9 (iy), b
	ld l, 4 (iy)		; --tail
	ld h, 5 (iy)
	dec hl
	ld e, 0 (iy)
	ld d, 1 (iy)
	ld a, l
	sub e
	ld a, h
	sbc a, d
	jr nc, un_ok
	ld l, 6 (iy)		; tail = base + size - 1
	ld h, 7 (iy)
	add hl, de
	dec hl
un_ok:
	ld 4 (iy), l
	ld 5 (iy), h
	ld a, (hl)
	pop bc
	ld (bc), a		; *cp
	ld l, #1
	jp iq_end
