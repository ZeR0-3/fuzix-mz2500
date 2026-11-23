; MZ-2500 floppy driver (/dev/fd0-3): FDC at D8h-DEh, polled, 256 byte sectors.
; Written from the IOCS specification 5.13.1a / hardware notes 2 (no ROM code).
;
; The FDC bus is inverted for status, track, sector, command and data bytes;
; standard disks hold true data, so the driver complements data bytes. A Fuzix block (512 bytes) = two consecutive records (record r =
; cylinder r/32, head (r/16)&1, sector r%16+1). Cylinders 0-7 are the boot
; area (IPLPRO header + kernel, stored with the other polarity); block 0 =
; record 256, so the filesystem has 1152 blocks.
;
; minor = drive 0-3: filesystem area (block 0 = record 256, 1152 blocks).
; minor 4-7 = drive 0-3 as a whole disk (block 0 = record 0, 1280 blocks): the boot
; area (records 0-255) is stored with the other data polarity and is accessed as is.
; Only transfers to kernel buffers (rawflag 0).
	.module devfd
	.globl _fd_open, _fd_read, _fd_write, _fd_ioctl, _fd_tick, _udata, _int_disabled

U_ERROR	.equ 12
U_BLOCK	.equ 0x91
U_DPTR	.equ 0x97

	.area _DATA
fd_drive:	.ds 1
fd_dir:		.ds 1		; 1 = read, 0 = write
fd_rec:		.ds 2
fd_buf:		.ds 2
fd_cyl:		.ds 1
fd_head:	.ds 1
fd_sec:		.ds 1
fd_retry:	.ds 1
fd_motor:	.ds 1
fd_latch:	.ds 1		; DCh value for the current drive/head
fd_cur:		.ds 1		; drive that is selected (FFh = none), set in init
fd_idle:	.ds 1
fd_hp:		.ds 4		; head position per drive: FFh - cylinder, 0 = unknown
fd_inited:	.ds 1
fd_whole:	.ds 1		; nonzero: whole-disk device (minor 4-7)
fd_fsp:		.ds 2		; stack pointer while formatting (error unwind)
fm_s:		.ds 1		; sector number being formatted

	.area _CODE

_fd_open::
	ld hl, #2
	add hl, sp
	ld a, (hl)
	cp #8
	jr nc, 1$
	ld hl, #0
	ret
1$:	ld hl, #19		; ENODEV
	ld (_udata + U_ERROR), hl
	ld hl, #0xffff
	ret

_fd_read::
	ld c, #1
	jr xfer
_fd_write::
	ld c, #0
xfer:
	ld hl, #2
	add hl, sp
	ld a, (hl)		; minor
	ld b, a
	and #3
	ld (fd_drive), a
	ld a, b
	and #4
	ld (fd_whole), a
	inc hl
	ld a, (hl)		; rawflag
	or a
	jr nz, eio
	ld a, c
	ld (fd_dir), a
	ld a, (fd_inited)
	or a
	jr nz, 2$
	dec a
	ld (fd_cur), a		; FFh: no drive selected yet
	ld a, #1
	ld (fd_inited), a
2$:	ld hl, (_udata + U_BLOCK)
	ld a, (fd_whole)
	or a
	ld de, #1152
	jr z, 3$
	ld de, #1280		; whole disk
3$:	or a
	sbc hl, de
	jr nc, eio
	add hl, de
	add hl, hl		; first record
	ld a, (fd_whole)
	or a
	jr nz, 4$
	ld de, #256		; cylinders 0-7 hold the IPL/kernel boot area
	add hl, de
4$:	ld (fd_rec), hl
	ld hl, (_udata + U_DPTR)
	ld (fd_buf), hl
	call fd_one
	jr c, eio
	call fd_one
	jr c, eio
	ld hl, #512
	ret
eio:	ld hl, #5		; EIO
	ld (_udata + U_ERROR), hl
	ld hl, #0xffff
	ret

; one record with retries; advances fd_rec / fd_buf. Carry set = failure.
fd_one:
	ld a, #9
	ld (fd_retry), a
1$:	ld a, #250
	ld (fd_idle), a
	call fd_select
	call fd_pos
	call nc, fd_sector
	call nc, fd_verify
	jr nc, 3$
	call hpptr		; error: forget the head position, retry
	ld (hl), #0
	ld hl, #fd_retry
	dec (hl)
	jr nz, 1$
	scf
	ret
3$:	ld hl, (fd_rec)
	inc hl
	ld (fd_rec), hl
	ld hl, (fd_buf)
	inc h
	ld (fd_buf), hl
	or a
	ret

hpptr:				; HL = &fd_hp[drive]
	ld a, (fd_drive)
	ld e, a
	ld d, #0
	ld hl, #fd_hp
	add hl, de
	ret

; motor on / drive / head selection, also derives cyl, head, sec of fd_rec
fd_select:
	ld hl, (fd_rec)
	ld a, l
	and #0x0f
	inc a
	ld (fd_sec), a
	ld a, l
	rrca
	rrca
	rrca
	rrca
	and #1
	ld (fd_head), a
	ld b, #5
2$:	srl h
	rr l
	djnz 2$
	ld a, l
	ld (fd_cyl), a
	ld a, (fd_motor)
	or a
	jr nz, 4$
	ld a, #0x80
	out (0xDC), a
	ld a, #0x02
	out (0xDD), a
	ld b, #0x22		; spin-up wait
5$:	ld de, #0x0BB8
6$:	dec de
	ld a, d
	or e
	jr nz, 6$
	djnz 5$
	ld a, #1
	ld (fd_motor), a
	ld a, #0xff
	ld (fd_cur), a
4$:	ld a, (fd_drive)
	ld b, a
	ld a, (fd_cur)
	cp b
	jr z, 7$
	ld a, b
	ld (fd_cur), a
	or #0x84
	ld (fd_latch), a
	out (0xDC), a
	rlca
	rlca
	out (0xDD), a
7$:	ld a, (fd_latch)	; head: bit 6 set = head 0
	res 6, a
	ld b, a
	ld a, (fd_head)
	or a
	ld a, b
	jr nz, 8$
	set 6, a
8$:	ld (fd_latch), a
	ret

; restore if the head position is unknown, then seek to fd_cyl.
; Carry set = failure.
fd_pos:
	call hpptr
	ld a, (hl)
	or a
	jr nz, 1$
	ld a, #0xF7		; restore
	out (0xD8), a
	call fd_dly
	call w_idle
	ret c
	call hpptr
	ld (hl), #0xff
1$:	ld a, (fd_cyl)
	cpl
	ld c, a			; target = FFh - cyl
	ld a, (hl)
	cp c
	ret z
	out (0xD9), a		; track register = where the head is
	ld a, c
	out (0xDB), a		; target
	ld a, #0xE7		; seek
	out (0xD8), a
	call fd_dly
	call w_idle
	ret c
	call hpptr
	ld a, (fd_cyl)
	cpl
	ld (hl), a
	or a
	ret

fd_dly:				; about 500 cycles between command and status
	ld b, #40
1$:	djnz 1$
	ret

; wait until the FDC is not busy; carry set on timeout
w_idle:
	ld bc, #0
	ld d, #3
1$:	in a, (0xD8)
	cpl
	and #0x81
	ret z
	djnz 1$
	dec c
	jr nz, 1$
	dec d
	jr nz, 1$
	scf
	ret

; wait for busy and ready (status & 81h == 01h); carry set on timeout
w_start:
	ld bc, #0
	ld d, #1
1$:	in a, (0xD8)
	cpl
	and #0x81
	cp #1
	ret z
	djnz 1$
	dec c
	jr nz, 1$
	dec d
	jr nz, 1$
	scf
	ret

; transfer the sector (cylinder/head/sector set up). Carry set = failure.
; after a successful write, read the record back and compare (fd_dir 0 -> 2 -> 0)
fd_verify:
	ld a, (fd_dir)
	or a
	ret nz			; reads need no verify (carry clear)
	ld a, #2
	ld (fd_dir), a
	call fd_sector
	push af
	xor a
	ld (fd_dir), a
	pop af
	ret

fd_sector:
	xor a
	out (0xDE), a
	ld a, (fd_latch)
	rlca
	rlca
	out (0xDD), a
	ld a, (fd_sec)
	cpl
	out (0xDA), a
	ld hl, (fd_buf)
	ld a, (fd_dir)
	or a
	jr z, wr
	cp #2
	jr z, vfy
	ld a, #0x7F		; read sector (80h)
	out (0xD8), a
	call fd_dly
	call w_start
	ret c
	ld a, (_int_disabled)
	push af
	di
	call fd_mask
	ld b, #0
1$:	in a, (0xD8)
	cpl
	bit 1, a
	jr nz, 2$
	rrca
	jr c, 1$		; busy: keep waiting
	jr rderr
2$:	in a, (0xDB)
	xor e			; standard disks: data arrives complemented (E = FFh)
	ld (hl), a
	inc hl
	djnz 1$
	pop af
	call ei_if0
	call w_idle
	ret c
	in a, (0xD8)
	cpl
	and #0x99
	ret z
	scf
	ret
rderr:	pop af
	call ei_if0
	scf
	ret

wr:	ld a, #0x5F		; write sector (A0h)
	out (0xD8), a
	call fd_dly
	call w_start
	ret c
	ld a, (_int_disabled)
	push af
	di
	call fd_mask
	ld b, #0
3$:	in a, (0xD8)
	cpl
	bit 1, a
	jr nz, 4$
	rrca
	jr c, 3$
	jr rderr
4$:	ld a, (hl)
	xor e
	out (0xDB), a
	inc hl
	djnz 3$
	pop af
	call ei_if0
	call w_idle
	ret c
	in a, (0xD8)
	cpl
	and #0xFC
	ret z
	scf
	ret

; verify: read the sector back and compare with the buffer (fd_dir = 2)
vfy:	ld a, #0x7F
	out (0xD8), a
	call fd_dly
	call w_start
	ret c
	ld a, (_int_disabled)
	push af
	di
	call fd_mask
	ld b, #0
	ld c, #0		; C accumulates differences
5$:	in a, (0xD8)
	cpl
	bit 1, a
	jr nz, 6$
	rrca
	jr c, 5$
	jr rderr
6$:	in a, (0xDB)
	xor e
	xor (hl)
	or c
	ld c, a
	inc hl
	djnz 5$
	pop af
	call ei_if0
	push bc			; w_idle destroys BC
	call w_idle
	pop bc
	ret c
	in a, (0xD8)
	cpl
	and #0x99
	jr nz, 7$
	ld a, c
	or a
	ret z
7$:	scf
	ret

; ioctl 46xxh (super-user class): format physical track xx (0-159; cylinder xx/2,
; side xx&1, the same numbering as the D88 track table). 16 sectors of 256 bytes
; (MFM, IDs 1-16 in order), data filled with E5h. minor = drive.
_fd_ioctl::
	ld hl, #2
	add hl, sp
	ld a, (hl)		; minor
	and #3
	ld (fd_drive), a
	inc hl
	ld c, (hl)		; request low = track
	inc hl
	ld a, (hl)		; request high
	cp #0x46
	jr nz, 9$
	ld a, c
	cp #160
	jr nc, 8$
	ld a, (fd_inited)
	or a
	jr nz, 1$
	dec a
	ld (fd_cur), a
	ld a, #1
	ld (fd_inited), a
1$:	ld a, c			; first record of the track: cyl*32 + (side^1)*16
	srl a
	ld l, a
	ld h, #0
	add hl, hl
	add hl, hl
	add hl, hl
	add hl, hl
	add hl, hl
	ld a, c
	and #1
	xor #1
	rlca
	rlca
	rlca
	rlca
	or l
	ld l, a
	ld (fd_rec), hl
	ld a, #3
	ld (fd_retry), a
2$:	ld a, #250
	ld (fd_idle), a
	call fd_select
	call fd_pos
	call nc, fd_fmt
	jr nc, 3$
	call hpptr
	ld (hl), #0
	ld hl, #fd_retry
	dec (hl)
	jr nz, 2$
	ld hl, #5		; EIO
	ld (_udata + U_ERROR), hl
	ld hl, #0xffff
	ret
3$:	ld hl, #0
	ret
8$:	ld hl, #22		; EINVAL
	ld (_udata + U_ERROR), hl
9$:	ld hl, #0xffff		; unknown ioctl (ENOTTY is set by the caller)
	ret

; emit one byte of the Write Track stream (A); control bytes F5-F7 are
; expanded by the FDC. Failure unwinds to fd_fmt.
emit:
	ld d, a
1$:	in a, (0xD8)
	cpl
	bit 1, a
	jr nz, 2$
	rrca
	jr c, 1$
	jp fmt_fail
2$:	ld a, d
	cpl
	out (0xDB), a
	ret

run:				; A = byte, B = count (0 = 256)
	ld c, a
1$:	ld a, c
	call emit
	djnz 1$
	ret

fd_fmt:
	xor a
	out (0xDE), a		; MFM
	ld a, (fd_latch)
	rlca
	rlca
	out (0xDD), a
	ld a, (_int_disabled)
	push af
	di
	ld (fd_fsp), sp
	ld a, #0x0B		; write track (F4h)
	out (0xD8), a
	call fd_dly
	ld a, #0x4E
	ld b, #80
	call run
	xor a
	ld b, #12
	call run
	ld a, #0xF6
	ld b, #3
	call run
	ld a, #0xFC		; index mark
	call emit
	ld a, #0x4E
	ld b, #50
	call run
	ld a, #1
	ld (fm_s), a
sect:	xor a
	ld b, #12
	call run
	ld a, #0xF5
	ld b, #3
	call run
	ld a, #0xFE		; ID address mark
	call emit
	ld a, (fd_cyl)
	call emit
	ld a, (fd_head)		; ID side = physical side = logical head ^ 1
	xor #1
	call emit
	ld a, (fm_s)
	call emit
	ld a, #1		; N = 1: 256 bytes
	call emit
	ld a, #0xF7		; ID CRC
	call emit
	ld a, #0x4E
	ld b, #22
	call run
	xor a
	ld b, #12
	call run
	ld a, #0xF5
	ld b, #3
	call run
	ld a, #0xFB		; data address mark
	call emit
	ld a, #0xE5
	ld b, #0
	call run
	ld a, #0xF7		; data CRC
	call emit
	ld a, #0x4E
	ld b, #54
	call run
	ld hl, #fm_s
	inc (hl)
	ld a, (hl)
	cp #17
	jr nz, sect
tail:	in a, (0xD8)		; fill with 4Eh up to the index pulse
	cpl
	ld e, a
	bit 1, a
	jr z, 1$
	ld a, #0xB1		; ~4Eh
	out (0xDB), a
1$:	bit 0, e
	jr nz, tail
	pop af
	call ei_if0
	in a, (0xD8)
	cpl
	and #0xE4		; not ready, write protect, write fault, lost data
	ret z
	scf
	ret

fmt_fail:
	ld sp, (fd_fsp)
	ld a, #0x2F		; force interrupt (D0h)
	out (0xD8), a
	pop af
	call ei_if0
	scf
	ret

; E = data polarity mask of the current record: FFh (complemented on the bus) for the
; filesystem area, 00h for the boot area (records 0-255, whole-disk devices only)
fd_mask:
	ld a, (fd_rec + 1)
	or a
	ld e, #0xFF
	ret nz
	ld e, #0
	ret

ei_if0:				; A = saved _int_disabled
	or a
	ret nz
	ei
	ret

; called from the 50 Hz interrupt: stop the motor after ~5 s idle
_fd_tick::
	ld a, (fd_motor)
	or a
	ret z
	ld hl, #fd_idle
	dec (hl)
	ret nz
	xor a
	out (0xDC), a
	out (0xDD), a
	ld (fd_motor), a
	ld (fd_latch), a
	dec a
	ld (fd_cur), a
	ret
