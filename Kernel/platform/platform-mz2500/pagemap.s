;
;	MZ-2500 page manager (assembler). Every process owns a variable number
;	of 8KB pages (windows 0-6, up to 56KB). A bank token (1..15, in the low
;	byte of p_page) selects a row of pmap[16][8]; unused windows point at the
;	dummy page 0Eh, byte 7 of a row is always 0.
;
;	C callable (SDCC: args on the stack, caller cleans up, result in HL):
;	  void pagemap_init(void), pagemap_add(uint8_t)
;	  void pagemap_free(ptptr p)
;	  int  pagemap_alloc(ptptr p)
;	  int  pagemap_realloc(struct exec *hdr, uint16_t size)
;	  int  pagemap_prepare(struct exec *hdr)
;	  uint16_t pagemap_mem_used(void)
;
	.module pagemap

	.globl _pagemap_init
	.globl _pagemap_add
	.globl _pagemap_free
	.globl _pagemap_alloc
	.globl _pagemap_realloc
	.globl _pagemap_prepare
	.globl _pagemap_mem_used
	.globl _pmap
	.globl _userbanks
	.globl _udata
	.globl _panic

DUMMY		.equ 0x0E
P_PAGE		.equ 15			; struct p_tab offsets (see kernel-z80.def)
P_TOP		.equ 69
P_SIZE		.equ 71
U_PAGE		.equ 2			; struct u_data offsets
U_ERROR		.equ 12
A_BASE		.equ 4			; struct exec offsets
A_SIZE		.equ 13
ENOEXEC		.equ 8
ENOMEM		.equ 12

	.area _COMMONMEM

; pages_for: HL = top -> A = pages (1..7)
pages_for:
	ld de, #0x1FFF
	add hl, de
	ld a, h
	rlca
	rlca
	rlca
	and #7
	ret nz
	inc a
	ret

; rowaddr: A = token -> HL = &pmap[token][0]. Destroys DE
rowaddr:
	ld l, a
	ld h, #0
	add hl, hl
	add hl, hl
	add hl, hl
	ld de, #_pmap
	add hl, de
	ret

; rowclr: HL = row, A = first slot to clear. Slots from A..6 get the dummy
; page, slot 7 gets 0. Destroys AF, BC, HL
rowclr:
	ld c, a
	ld b, #0
	push hl
	add hl, bc
	ld a, #8
	sub c
	ld b, a
1$:	ld (hl), #DUMMY
	inc hl
	djnz 1$
	pop hl
	ld bc, #7
	add hl, bc
	ld (hl), #0
	ret

; pfcount: A = number of free pages. Destroys HL, DE
pfcount:
	ld hl, (pfp)
	ld de, #pfree
	or a
	sbc hl, de
	ld a, l
	ret

_pagemap_init:
	ld hl, #pfree
	ld a, #0x08		; main RAM 08-0C (0Dh stash, 0Eh dummy)
1$:	ld (hl), a
	inc hl
	inc a
	cp #0x0D
	jr nz, 1$
	ld a, (_userbanks)
	cp #6
	jr c, 3$
	ld a, #0x10		; expansion RAM 10-1F
2$:	ld (hl), a
	inc hl
	inc a
	cp #0x20
	jr nz, 2$
3$:	ld (pfp), hl
	call pfcount
	ld (pooltotal), a
	ld hl, #tfree		; tokens 15..1, handed out lowest first
	ld a, #15
4$:	ld (hl), a
	inc hl
	dec a
	jr nz, 4$
	ld (tfp), hl
_pagemap_add:
	ret

_pagemap_free:
	ld hl, #2
	add hl, sp
	ld e, (hl)
	inc hl
	ld d, (hl)
	ex de, hl
	ld de, #P_PAGE
	add hl, de
	ld a, (hl)		; token
	or a
	jr nz, 1$
	ld hl, #free0
	push hl
	call _panic		; never returns
1$:	push af
	call rowaddr
	push hl
	ld de, (pfp)
	ld b, #7
2$:	ld a, (hl)
	inc hl
	cp #DUMMY
	jr z, 3$
	ld (de), a
	inc de
3$:	djnz 2$
	ld (pfp), de
	pop hl
	xor a
	call rowclr
	pop af
	ld hl, (tfp)
	ld (hl), a
	inc hl
	ld (tfp), hl
	ret

_pagemap_alloc:
	ld hl, #2
	add hl, sp
	ld e, (hl)
	inc hl
	ld d, (hl)		; DE = p
	push de
	ex de, hl
	ld de, #P_TOP
	add hl, de
	ld e, (hl)
	inc hl
	ld d, (hl)
	ex de, hl
	call pages_for		; A = need
	ld b, a
	ld hl, (tfp)
	ld de, #tfree
	or a
	sbc hl, de
	jr z, nomem1		; no free token
	push bc
	call pfcount
	pop bc
	cp b
	jr c, nomem1		; fewer free pages than needed
	ld hl, (tfp)
	dec hl
	ld (tfp), hl
	ld c, (hl)		; C = token
	push bc			; [need, token]
	ld a, c
	call rowaddr
	push hl			; [row]
	ld de, (pfp)
1$:	dec de
	ld a, (de)
	ld (hl), a
	inc hl
	djnz 1$
	ld (pfp), de
	pop hl			; row
	pop bc			; B = need, C = token
	push bc
	ld a, b
	call rowclr
	pop bc
	pop de			; p
	ex de, hl
	ld de, #P_PAGE
	add hl, de
	ld (hl), c
	inc hl
	ld (hl), #0
	ld hl, #0
	ret
nomem1:	pop de
	ld hl, #ENOMEM
	ret

_pagemap_realloc:
	ld hl, #4
	add hl, sp
	ld e, (hl)
	inc hl
	ld d, (hl)
	ex de, hl
	call pages_for		; A = want
	ld (sc_want), a
	ld a, (_udata + U_PAGE)
	call rowaddr
	push hl
	ld c, #0		; have = leading non-dummy slots
1$:	ld a, c
	cp #7
	jr z, 2$
	ld a, (hl)
	cp #DUMMY
	jr z, 2$
	inc hl
	inc c
	jr 1$
2$:	pop hl			; row
	ld a, (sc_want)
	ld b, a
	cp c
	jr z, fin
	jr c, shrink
	sub c			; grow by n = want - have
	ld e, a
	push hl
	push bc
	push de
	call pfcount
	pop de
	pop bc
	pop hl
	cp e
	jr c, nomem2
	ld a, c
	add a, l
	ld l, a
	jr nc, 3$
	inc h
3$:	ld a, b
	sub c
	ld b, a
	ld de, (pfp)
4$:	dec de
	ld a, (de)
	ld (hl), a
	inc hl
	djnz 4$
	ld (pfp), de
	jr fin
shrink:	ld a, b			; give back have - want pages
	add a, l
	ld l, a
	jr nc, 5$
	inc h
5$:	ld a, c
	sub b
	ld b, a
	ld de, (pfp)
6$:	ld a, (hl)
	ld (de), a
	inc de
	ld (hl), #DUMMY
	inc hl
	djnz 6$
	ld (pfp), de
fin:	ld a, (sc_want)		; u_ptab->p_size = want * 8 (KB)
	ld l, a
	ld h, #0
	add hl, hl
	add hl, hl
	add hl, hl
	ex de, hl
	ld hl, (_udata)
	push de
	ld de, #P_SIZE
	add hl, de
	pop de
	ld (hl), e
	inc hl
	ld (hl), d
	ld hl, #0
	ret
nomem2:	ld hl, #ENOMEM
	ret

_pagemap_prepare:
	ld hl, #2
	add hl, sp
	ld e, (hl)
	inc hl
	ld d, (hl)		; DE = hdr
	ld hl, #A_BASE
	add hl, de
	ld a, (hl)
	or a
	jr nz, 1$
	ld a, #1		; relocatable: load at PROGLOAD (0100h)
	ld (hl), a
1$:	cp #1
	jr nz, bad_fmt
	ld c, a			; C = base
	ld hl, #A_SIZE
	add hl, de
	ld a, (hl)
	or a
	jr nz, 2$
	ld a, #0x9F		; "all memory" = default 40KB top (A000h)
	ld (hl), a
2$:	add a, c
	jr c, bad_mem
	cp #0xE1		; base + size must not pass PROGTOP (E000h)
	jr nc, bad_mem
	ld hl, #0
	ret
bad_fmt:
	ld hl, #ENOEXEC
	jr seterr
bad_mem:
	ld hl, #ENOMEM
seterr:	ld (_udata + U_ERROR), hl
	ld hl, #0xFFFF
	ret

_pagemap_mem_used:
	call pfcount
	ld b, a
	ld a, (pooltotal)
	sub b
	ld l, a
	ld h, #0
	add hl, hl
	add hl, hl
	add hl, hl
	ret

	.area _CONST
free0:
	.asciz "free0"

	.area _DATA
pfree:	.ds 24
pfp:	.dw 0
tfree:	.ds 16
tfp:	.dw 0
pooltotal:
	.db 0
sc_want:
	.db 0
