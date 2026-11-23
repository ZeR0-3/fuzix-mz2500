;
;	Sharp MZ-2500 low level support for FUZIX
;	Own code. Hardware facts verified on the emulator (see port notes).
;
;	CPU window n (n = 0..7, 8K each) is selected by OUT (B4h),n and its
;	physical page set by OUT (B5h),page. Window 7 is the fixed common
;	area (page 0Fh). Bank "tokens": 0 = kernel, 1.. = user banks.
;
	.module mz2500

	.globl init_early
	.globl _userbanks
	.globl _pmap
	.globl _curmap
	.globl init_hardware
	.globl emm_init
	.globl _emm_chk
	.globl _program_vectors
	.globl plt_interrupt_all
	.globl map_kernel
	.globl map_kernel_di
	.globl map_kernel_restore
	.globl map_proc
	.globl map_proc_di
	.globl map_proc_always
	.globl map_proc_always_di
	.globl map_proc_a
	.globl map_save_kernel
	.globl map_restore
	.globl _int_disabled
	.globl _plt_reboot
	.globl _plt_monitor
	.globl outchar

	.globl _ramsize
	.globl _procmem
	.globl _mz_video_init
	.globl unix_syscall_entry
	.globl null_handler
	.globl nmi_handler
	.globl interrupt_handler

	.include "kernel.def"
	.include "../../cpu-z80/kernel-z80.def"

VECWORD		.equ 0xFFFC		; IM2 table: I=FFh, vector byte FCh

	.area _COMMONMEM

_plt_monitor:
_plt_reboot:
	di
haltloop:
	halt
	jr haltloop

plt_interrupt_all:
	ret

;
;	Debug output used by the assembler level fault handlers: writes the
;	character in A to the last text row (row 24) through a temporary
;	window 6 mapping. Preserves all registers.
;
outchar:
	push af
	push bc
	push de
	push hl
	ld c, a
	ld a, (_int_disabled)
	push af
	di
	ld a, #6
	out (0xB4), a
	ld a, #0x38
	out (0xB5), a
	ld hl, (dbgpos)
	ld de, #1000		; 40 x 25 cells: wrap inside the last row
	or a
	sbc hl, de
	add hl, de
	jr c, dbgok
	ld hl, #960
dbgok:
	ld de, #0xC000
	add hl, de
	ld a, c
	and #0x3F
	add a, a
	add a, a
	ld (hl), a
	ld de, #0x0800
	add hl, de
	ld (hl), #0x07
	add hl, de
	ld a, c
	rlca
	rlca
	and #0x03
	add a, #0x8C
	ld (hl), a
	ld hl, (dbgpos)
	inc hl
	ld (dbgpos), hl
	; restore window 6 for the current bank token
	ld a, (_curmap)
	ld l, a
	ld h, #0
	add hl, hl
	add hl, hl
	add hl, hl
	ld de, #_pmap + 6
	add hl, de
	ld a, #6
	out (0xB4), a
	ld a, (hl)
	out (0xB5), a
	pop af
	or a
	jr nz, dbgdone
	ei
dbgdone:
	pop hl
	pop de
	pop bc
	pop af
	ret

;
;	Install the low memory vectors in the bank selected by the pointer
;	on the stack (NULL = kernel). Entered with interrupts off.
;
_program_vectors:
	di
	pop de			; return address
	pop hl			; pointer to bank token (or NULL)
	push hl
	push de
	call map_proc

	ld hl, #0
	ld de, #1
	ld bc, #0x007f
	ld (hl), #0x00
	ldir

	ld a, #0xC3		; JP
	ld (0x0038), a
	ld hl, #interrupt_handler
	ld (0x0039), hl

	ld (0x0030), a		; RST 30h = system call
	ld hl, #unix_syscall_entry
	ld (0x0031), hl

	ld (0x0000), a
	ld hl, #null_handler
	ld (0x0001), hl

	ld (0x0066), a
	ld hl, #nmi_handler
	ld (0x0067), hl
	jr map_kernel

;
;	Core mapper: A = bank token. Preserves BC, HL, trashes AF.
;	Interrupts are held off across the 7 window writes and restored to
;	the kernel's idea of the state (_int_disabled).
;
map_proc_a:
	; Preserves A (the bank token) as well as BC, DE and HL:
	; bankfork relies on it.
	push bc
	push de
	push hl
	ld e, a
	ld a, (_int_disabled)
	ld d, a
	di
	ld a, e
	call mapraw
	ld a, d
	or a
	ld a, e
	jr nz, mapdone
	ei
mapdone:
	pop hl
	pop de
	pop bc
	ret

;
;	Same with interrupts known to be off (never enables them).
;	Preserves AF, BC, HL.
;
map_a_di:
	push af
	push bc
	push hl
	call mapraw
	pop hl
	pop bc
	pop af
	ret

;
;	A = token, interrupts off. Trashes AF, BC, HL.
;
mapraw:
	ld (_curmap), a
	ld l, a
	ld h, #0
	add hl, hl
	add hl, hl
	add hl, hl
	ld bc, #_pmap
	add hl, bc
	ld b, #7
	ld c, #0
maploop:
	ld a, c
	out (0xB4), a
	ld a, (hl)
	out (0xB5), a
	inc hl
	inc c
	djnz maploop
	ret

map_kernel:
map_kernel_restore:
	push af
	xor a
	call map_proc_a
	pop af
	ret

map_kernel_di:
	push af
	xor a
	call map_a_di
	pop af
	ret

;
;	HL = pointer to the bank token, or NULL for the kernel.
;	May corrupt AF, HL.
;
map_proc:
	ld a, h
	or l
	jr z, map_kernel
	ld a, (hl)
	jp map_proc_a

map_proc_di:
	ld a, h
	or l
	jr z, map_kernel_di
	ld a, (hl)
	jp map_a_di

map_proc_always:
	push af
	ld a, (_udata + U_DATA__U_PAGE)
	call map_proc_a
	pop af
	ret

map_proc_always_di:
	push af
	ld a, (_udata + U_DATA__U_PAGE)
	call map_a_di
	pop af
	ret

;
;	Interrupt time: interrupts are already off.
;
map_save_kernel:
	push af
	ld a, (_curmap)
	ld (mapsave), a
	xor a
	call map_a_di
	pop af
	ret

map_restore:
	push af
	ld a, (mapsave)
	call map_a_di
	pop af
	ret

	.area _COMMONDATA

_int_disabled:
	.db 1
_curmap:
	.db 0
dbgpos:
	.dw 960
_userbanks:
	.db 1
mapsave:
	.db 0

;
;	Physical page of each of the 7 switched windows per bank token.
;	Kernel keeps text VRAM (page 38h) in window 6.
;
_pmap:
	.db 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x38, 0x00	; 0 kernel
	; Rows 1-15 belong to the user processes. They are filled in by
	; pagemap.c (8KB pages from a pool); unused windows point at the
	; dummy page 0Eh.
	.ds 120

	.area _CODE

init_early:
	; Entered with the IPLPRO window map: put text VRAM in window 6
	ld a, #6
	out (0xB4), a
	ld a, #0x38
	out (0xB5), a
	ret

init_hardware:
	; Probe the expansion RAM (pages 10h-1Fh). When it is absent the
	; pages alias 00h-0Fh, so a write to page 1Eh shows up in page 0Eh.
	ld a, #6
	out (0xB4), a
	ld a, #0x0E
	out (0xB5), a
	ld a, (0xC000)
	ld d, a			; keep the old byte
	xor a
	ld (0xC000), a
	ld a, #6
	out (0xB4), a
	ld a, #0x1E
	out (0xB5), a
	ld a, #0x5A
	ld (0xC000), a
	ld a, #6
	out (0xB4), a
	ld a, #0x0E
	out (0xB5), a
	ld a, (0xC000)
	ld e, a			; 5Ah = aliased = absent
	ld a, d
	ld (0xC000), a		; restore page 0Eh
	ld a, #6
	out (0xB4), a
	ld a, #0x38
	out (0xB5), a		; text VRAM back into window 6
	ld a, e
	cp #0x5A
	jr z, noexp
noexp:
	; pool of free 8KB pages: 08-0C (page 0Dh = udata stash, 0Eh = dummy)
	; plus 10h-1Fh when the expansion RAM is there.
	ld hl, #128
	ld a, #5
	jr z, ramset
	ld hl, #256
	ld a, #21
ramset:
	ld (_ramsize), hl
	ld (_userbanks), a
	cp #16			; at most 15 processes (PTABSIZE): 120KB
	jr c, procset
	ld a, #15
procset:
	ld l, a
	ld h, #0
	add hl, hl
	add hl, hl
	add hl, hl		; pages * 8 = KB
	ld (_procmem), hl

	; vectors for the kernel bank
	ld hl, #0
	push hl
	call _program_vectors
	pop hl

	call emm_init
	call _mz_video_init

	; interrupts: IM2, table word in common at FFFCh
	ld hl, #interrupt_handler
	ld (VECWORD), hl
	ld a, #0xFF
	ld i, a
	im 2

	; 8253 counter 0: mode 2, divisor 625 (31.25kHz / 625 = 50Hz)
	ld a, #0x34
	out (0xE7), a
	ld a, #0x71
	out (0xE4), a
	ld a, #0x02
	out (0xE4), a
	ld a, #0x40		; set the timer vector
	out (0xC6), a
	ld a, #0xFC
	out (0xC7), a
	ld a, #0x04		; TMIE only
	out (0xC6), a
	ret
