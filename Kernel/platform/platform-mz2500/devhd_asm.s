;
;	MZ-1E30 style SASI hard disk driver (SASI ID 0, LUN 0), hand written.
;
;	A4h = data (an access acknowledges the byte), A5h = status (read) /
;	control (write). Status: b7 REQ, b6 ACK, b5 BSY, b4 MSG, b3 C/D,
;	b2 I/O. Control: b5 SEL, b3 RST. The disk has 256 byte blocks, a Fuzix
;	block (512 bytes) is two of them.
;
;	Layout: block 3 holds the "EHSASI" partition table (signature, then up
;	to 15 entries of 16 bytes). The partition flagged for priority boot
;	(entry byte 0, bit 7) is Fuzix drive hda. Its first 512 blocks are the
;	boot area (IPLPRO header and kernel image), the Fuzix filesystem
;	follows. Only transfers into kernel buffers (rawflag 0) are supported.
;
;	Internal calling convention is register based:
;	  wait_req   -> A = status (0 on timeout)      clobbers A BC E
;	  wait_free  -> A = 1 free, 0 timeout          clobbers A BC
;	  sasi_command, sasi_finish -> A = 0 ok, 0xFF fail (flags set)
;
	.module devhd_asm

	.globl _hd_probe, _hd_open, _hd_read, _hd_write
	.globl _kputs, _kprintf, _udata
	.globl _emm_cache_init, _emm_cache_get, _emm_cache_put
	.globl _sasi_rd512, _sasi_wr512

SASI_D	=	0xA4
SASI_C	=	0xA5
SPIN	=	60000

	.area _CODE

wait_req:
	ld	bc, #SPIN
wq1:
	in	a, (SASI_C)
	ld	e, a
	and	#0xC0
	cp	#0x80
	jr	nz, wq2
	ld	a, e
	ret
wq2:
	dec	bc
	ld	a, b
	or	c
	jr	nz, wq1
	xor	a
	ret

wait_free:
	ld	bc, #SPIN
wf1:
	in	a, (SASI_C)
	and	#0x20
	jr	z, wf2
	dec	bc
	ld	a, b
	or	c
	jr	nz, wf1
	xor	a
	ret
wf2:
	ld	a, #1
	ret

sasi_reset:
	ld	a, #0x08
	out	(SASI_C), a
	ld	bc, #2000
sr1:
	dec	bc
	ld	a, b
	or	c
	jr	nz, sr1
	out	(SASI_C), a
	ld	bc, #20000
sr2:
	dec	bc
	ld	a, b
	or	c
	jr	nz, sr2
	ret

;	select the target and send the 6 byte command
sasi_command:
	call	wait_free
	or	a
	jr	z, sf_bad
	ld	a, #0x01
	out	(SASI_D), a
	ld	a, #0x20
	out	(SASI_C), a
	ld	bc, #SPIN
sc1:
	in	a, (SASI_C)
	and	#0x20
	jr	nz, sc2
	dec	bc
	ld	a, b
	or	c
	jr	nz, sc1
sc2:
	xor	a
	out	(SASI_C), a
	in	a, (SASI_C)
	and	#0x20
	jr	z, sf_bad
	ld	hl, #sasi_cdb
	ld	d, #6
sc3:
	push	hl
	call	wait_req
	pop	hl
	or	a
	jr	z, sf_bad
	and	#0x1c
	cp	#0x08
	jr	nz, sf_bad
	ld	a, (hl)
	out	(SASI_D), a
	inc	hl
	dec	d
	jr	nz, sc3
	xor	a
	ret

;	status and message phases after the data
sasi_finish:
	ld	bc, #0x08ff
sf1:
	push	bc
	call	wait_req
	pop	bc
	or	a
	jr	z, sf_bad
	and	#0x1c
	cp	#0x0c
	jr	z, sf_st
	cp	#0x1c
	jr	nz, sf_bad
	in	a, (SASI_D)
	ld	a, c
	or	a
	ret	z
sf_bad:
	ld	a, #0xff
	or	a
	ret
sf_st:
	in	a, (SASI_D)
	ld	c, a
	djnz	sf1
	jr	sf_bad

;	A = opcode, B = count, DE:HL = lba
sasi_setup:
	ld	(sasi_cdb), a
	ld	a, e
	and	#0x1f
	ld	(sasi_cdb + 1), a
	ld	a, h
	ld	(sasi_cdb + 2), a
	ld	a, l
	ld	(sasi_cdb + 3), a
	ld	a, b
	ld	(sasi_cdb + 4), a
	xor	a
	ld	(sasi_cdb + 5), a
	ret

;	read the partition table block (lba 3) into ptbuf, A = 0 ok
rd256:
	ld	a, #0x08
	ld	b, #1
	ld	hl, #3
	ld	de, #0
	call	sasi_setup
	call	sasi_command
	or	a
	jr	nz, r256_f
	ld	hl, #ptbuf
	ld	d, #0
r256_1:
	push	hl
	call	wait_req
	pop	hl
	or	a
	jr	z, r256_f
	and	#0x1c
	cp	#0x04
	jr	nz, r256_f
	in	a, (SASI_D)
	ld	(hl), a
	inc	hl
	dec	d
	jr	nz, r256_1
	call	sasi_finish
	or	a
	ret	z
r256_f:
	call	sasi_reset
	ld	a, #0xff
	or	a
	ret

_hd_probe::
	xor	a
	ld	(hd_present), a
	in	a, (SASI_C)
	cp	#0xff
	ret	z
	call	sasi_reset
	call	rd256
	or	a
	ld	hl, #hp_nodisk
	jr	nz, hp_msg
	ld	hl, #ptbuf
	ld	de, #hp_sig
	ld	b, #6
hp_c:
	ld	a, (de)
	cp	(hl)
	jr	nz, hp_notab
	inc	hl
	inc	de
	djnz	hp_c
	ld	hl, #ptbuf + 16
	ld	b, #15
hp_l:
	bit	7, (hl)
	jr	nz, hp_found
	ld	de, #16
	add	hl, de
	djnz	hp_l
	ld	hl, #hp_nopart
	jr	hp_msg
hp_notab:
	ld	hl, #hp_notbl
hp_msg:
	call	ixh_p1_kputs
	ret
hp_found:
	push	hl
	inc	hl
	ld	d, (hl)
	inc	hl
	ld	e, (hl)
	ld	(part_len), de
	ld	hl, #0
	ld	(part_len + 2), hl
	pop	hl
	ld	de, #5
	add	hl, de
	ld	a, (hl)
	inc	hl
	ld	d, (hl)
	inc	hl
	ld	e, (hl)
	ld	(part_top), de
	ld	h, #0
	ld	l, a
	ld	(part_top + 2), hl
	ld	hl, (part_top)
	ld	bc, #512
	add	hl, bc
	ld	(part_fs), hl
	ld	hl, (part_top + 2)
	ld	bc, #0
	adc	hl, bc
	ld	(part_fs + 2), hl
	ld	hl, (part_top)
	ld	bc, (part_len)
	add	hl, bc
	ld	(part_end), hl
	ld	hl, (part_top + 2)
	ld	bc, (part_len + 2)
	adc	hl, bc
	ld	(part_end + 2), hl
	ld	a, #1
	ld	(hd_present), a
	call	_emm_cache_init
	ld	hl, (part_len)
	push	hl
	ld	hl, (part_top + 2)
	push	hl
	ld	hl, (part_top)
	push	hl
	ld	hl, #hp_fmt
	push	hl
	call	_kprintf
	pop	af
	pop	af
	pop	af
	pop	af
	ret
hp_sig:
	.ascii	"EHSASI"
hp_nodisk:
	.ascii	"hd: no disk"
	.db	0x0a, 0x00
hp_notbl:
	.ascii	"hd: no partition table"
	.db	0x0a, 0x00
hp_nopart:
	.ascii	"hd: no boot partition"
	.db	0x0a, 0x00
hp_fmt:
	.ascii	"hd: partition at block %lx, %d blocks"
	.db	0x0a, 0x00

_hd_open::
	ld	a, (hd_present)
	or	a
	jr	z, ho_err
	ld	hl, #2
	add	hl, sp
	ld	a, (hl)
	or	a
	jr	nz, ho_err
	ld	h, a
	ld	l, a
	ret
ho_err:
	ld	hl, #0x13
	ld	(_udata + 0x0c), hl
	ld	hl, #0xffff
	ret

_hd_read::
	ld	a, #1
	jr	hx
_hd_write::
	xor	a
hx:
	ld	(hd_rw), a
	ld	hl, #3
	add	hl, sp
	ld	a, (hl)
	or	a
	jp	nz, hx_eio
;	lba = part_fs + 2 * u_block
	ld	hl, (_udata + 0x91)
	add	hl, hl
	ld	a, #0
	rla
	ld	b, a
	ld	de, (part_fs)
	add	hl, de
	ld	(hd_lba), hl
	ld	a, (part_fs + 2)
	adc	a, b
	ld	(hd_lba + 2), a
	ld	a, (part_fs + 3)
	adc	a, #0
	ld	(hd_lba + 3), a
;	lba + 2 must not pass part_end
	ld	hl, (hd_lba)
	ld	de, (hd_lba + 2)
	ld	bc, #2
	add	hl, bc
	jr	nc, hx_1
	inc	de
hx_1:
	ld	a, (part_end)
	sub	l
	ld	a, (part_end + 1)
	sbc	a, h
	ld	a, (part_end + 2)
	sbc	a, e
	ld	a, (part_end + 3)
	sbc	a, d
	jr	c, hx_eio
	ld	a, (hd_rw)
	or	a
	jr	z, hx_io
	ld	hl, (_udata + 0x97)
	push	hl
	ld	hl, (_udata + 0x91)
	push	hl
	call	_emm_cache_get
	pop	af
	pop	af
	ld	a, h
	or	l
	jr	z, hx_io
	ld	hl, #0x0200
	ret
hx_io:
	ld	a, (hd_rw)
	or	a
	ld	a, #0x0a
	jr	z, hx_2
	ld	a, #0x08
hx_2:
	ld	hl, (hd_lba)
	ld	de, (hd_lba + 2)
	ld	b, #2
	call	sasi_setup
	call	sasi_command
	or	a
	jr	nz, hx_fail
	ld	hl, (_udata + 0x97)
	push	hl
	ld	a, (hd_rw)
	or	a
	jr	z, hx_w
	call	_sasi_rd512
	jr	hx_3
hx_w:
	call	_sasi_wr512
hx_3:
	pop	af
	ld	a, l
	or	a
	jr	nz, hx_fail
	call	sasi_finish
	or	a
	jr	nz, hx_fail
	ld	hl, (_udata + 0x97)
	push	hl
	ld	hl, (_udata + 0x91)
	push	hl
	call	_emm_cache_put
	pop	af
	pop	af
	ld	hl, #0x0200
	ret
hx_fail:
	call	sasi_reset
hx_eio:
	ld	hl, #5
	ld	(_udata + 0x0c), hl
	ld	hl, #0xffff
	ret

	.area _DATA
part_top:
	.ds	4
part_len:
	.ds	4
part_fs:
	.ds	4
part_end:
	.ds	4
hd_lba:
	.ds	4
hd_present:
	.ds	1
hd_rw:
	.ds	1
sasi_cdb:
	.ds	6
ptbuf:
	.ds	256
