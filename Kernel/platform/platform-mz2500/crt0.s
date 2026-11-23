; Sharp MZ-2500 FUZIX start-up.
; The image is loaded flat by the IPLPRO boot block: kernel bank pages
; (windows 0-5) plus the common page (window 7), so no relocation is needed.
	.module crt0

	.area _CODE
	.area _HOME
	.area _CODE2
	.area _CONST
	.area _INITIALIZED
	.area _DATA
	.area _BSEG
	.area _BSS
	.area _HEAP
	.area _GSINIT
	.area _GSFINAL
	.area _DISCARD
	.area _INITIALIZER
	.area _COMMONMEM
	.area _COMMONDATA

	.globl _fuzix_main
	.globl init_early
	.globl init_hardware
	.globl s__DATA
	.globl l__DATA
	.globl s__INITIALIZER
	.globl s__INITIALIZED
	.globl l__INITIALIZED
	.globl kstack_top

	.area _CODE
init:
	di
	ld sp, #0x0100
	; the loader staged the common image in page 0Eh: copy it to the
	; fixed common page (window 7 = page 0Fh) via window 6
	ld a, #6
	out (0xB4), a
	ld a, #0x0E
	out (0xB5), a
	ld hl, #0xC000
	ld de, #0xE000
	ld bc, #0x2000
	ldir
	ld sp, #kstack_top
	call init_early
	; initialised data: the image carries the values in _INITIALIZER
	ld hl, #s__INITIALIZER
	ld de, #s__INITIALIZED
	ld bc, #l__INITIALIZED
	ldir
	; zero the data area
	ld hl, #s__DATA
	ld de, #s__DATA + 1
	ld bc, #l__DATA - 1
	ld (hl), #0
	ldir
	call init_hardware
	call _fuzix_main
	di
stop:	halt
	jr stop
