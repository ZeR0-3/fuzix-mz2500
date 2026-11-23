;
;	MZ-2500 platform hooks (assembler version of the old main.c)
;
	.module platform

	.globl _ramtop
	.globl _plt_idle
	.globl _plt_interrupt
	.globl _map_init
	.globl _plt_param
	.globl _kbd_interrupt
	.globl _fd_tick
	.globl _timer_interrupt

	.area _CODE

_ramtop:
	.dw 0xE000		; PROGTOP (kept in the code area: no init copy)

; nothing to poll yet: wait for the next interrupt
_plt_idle:
	halt
	ret

_plt_interrupt:
	call _kbd_interrupt
	call _fd_tick
	jp _timer_interrupt

_map_init:
	ret

; uint_fast8_t plt_param(char *p): no platform parameters
_plt_param:
	ld l, #0
	ret
