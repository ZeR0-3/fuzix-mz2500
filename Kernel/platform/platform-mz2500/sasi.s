;
;	SASI (MZ-1E30) data phase loops in assembler.
;	A4h = data, A5h = status. Status: b7 REQ, b6 ACK, b5 BSY, b4 MSG,
;	b3 C/D, b2 I/O. For every byte wait for REQ=1/ACK=0, check the bus
;	phase, then move the byte (the access to A4h acknowledges it).
;
;	C callable (args on the stack, caller cleans up):
;	  int sasi_rd512(uint8_t *buf);   disk -> buf, 512 bytes
;	  int sasi_wr512(const uint8_t *buf);  buf -> disk
;	Return HL = 0 ok, FFFFh on timeout or wrong phase.
;
	.module sasi

	.globl _sasi_rd512
	.globl _sasi_wr512

SASI_DATA	.equ 0xA4
SASI_STAT	.equ 0xA5
SPIN		.equ 60000

	.area _COMMONMEM

_sasi_rd512:
	ld hl, #2
	add hl, sp
	ld e, (hl)
	inc hl
	ld d, (hl)
	ex de, hl		; HL = buffer
	ld de, #512
1$:	ld bc, #SPIN
2$:	in a, (SASI_STAT)
	and #0xDC		; REQ, ACK, MSG, C/D, I/O in one read
	cp #0x84		; REQ, not ACK, data in
	jr z, 3$
	dec bc
	ld a, b
	or c
	jr nz, 2$
	jr bad
3$:	in a, (SASI_DATA)
	ld (hl), a
	inc hl
	dec de
	ld a, d
	or e
	jr nz, 1$
	ld hl, #0
	ret

_sasi_wr512:
	ld hl, #2
	add hl, sp
	ld e, (hl)
	inc hl
	ld d, (hl)
	ex de, hl
	ld de, #512
1$:	ld bc, #SPIN
2$:	in a, (SASI_STAT)
	and #0xDC
	cp #0x80		; REQ, not ACK, data out (phase 0)
	jr z, 3$
	dec bc
	ld a, b
	or c
	jr nz, 2$
	jr bad
3$:	ld a, (hl)
	out (SASI_DATA), a
	inc hl
	dec de
	ld a, d
	or e
	jr nz, 1$
	ld hl, #0
	ret

bad:	ld hl, #0xFFFF
	ret
