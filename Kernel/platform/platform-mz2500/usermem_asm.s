; usermem_asm.s - user memory access with address validation
;   valaddr(base, size[, is_write]) -> usable size (0 + EFAULT if none)
;   uget/ugetc/ugetw/uput/uputc/uputw/uzero validate then tail-jump to the
;   raw copy routines in umem.s with the caller's argument frame intact.
	.module usermem_asm
	.globl _valaddr, _valaddr_r, _valaddr_w
	.globl _uget, _ugetc, _ugetw, _uput, _uputc, _uputw, _uzero
	.globl __uget, __ugetc, __ugetw, __uput, __uputc, __uputw, __uzero
	.globl _udata
	.area _CODE
; va_core: de = base, bc = size -> hl = size, Z if zero. keeps de.
va_core:
	ld	h, d
	ld	l, e
	add	hl, bc
	jr	nc, va_1
	ld	hl, #0
	or	a, a
	sbc	hl, de			; size = 0x10000 - base
	ld	b, h
	ld	c, l
va_1:
	ld	a, d
	or	a, e
	jr	z, va_bad		; NULL
	ld	hl, (_udata + 0x1c)	; u_top
	or	a, a
	sbc	hl, de
	jr	c, va_bad		; base > top
	push	hl			; hl = room above base
	or	a, a
	sbc	hl, bc
	pop	hl
	jr	nc, va_chk
	ld	b, h			; size = room
	ld	c, l
	jr	va_chk
va_bad:
	ld	bc, #0
va_chk:
	ld	a, b
	or	a, c
	jr	nz, va_ok
	ld	hl, #14			; EFAULT
	ld	(_udata + 0x0c), hl
va_ok:
	ld	h, b
	ld	l, c
	ld	a, b
	or	a, c
	ret
; valaddr(base, size, is_write)
_valaddr::
_valaddr_r::
_valaddr_w::
	ld	hl, #2
	add	hl, sp
	ld	e, (hl)
	inc	hl
	ld	d, (hl)
	inc	hl
	ld	c, (hl)
	inc	hl
	ld	b, (hl)
	jr	va_core
_uget::
	ld	hl, #6
	add	hl, sp
	ld	c, (hl)
	inc	hl
	ld	b, (hl)
	ld	hl, #2
	add	hl, sp
	ld	e, (hl)
	inc	hl
	ld	d, (hl)
	call	va_core
	jr	z, u_fail
	jp	__uget
_ugetc::
	ld	bc, #1
	call	u_arg1
	jr	z, u_fail
	ex	de, hl
	jp	__ugetc
_ugetw::
	ld	bc, #2
	call	u_arg1
	jr	z, u_fail
	ex	de, hl
	jp	__ugetw
; u_arg1: de = first stack argument (caller frame), validate (de, bc)
u_arg1:
	ld	hl, #4
	add	hl, sp
	ld	e, (hl)
	inc	hl
	ld	d, (hl)
	jr	va_core
_uput::
	ld	hl, #4
	add	hl, sp
	ld	e, (hl)
	inc	hl
	ld	d, (hl)
	inc	hl
	ld	c, (hl)
	inc	hl
	ld	b, (hl)
	call	va_core
	jr	z, u_fail
	jp	__uput
_uputc::
	ld	bc, #1
	call	u_arg2
	jr	z, u_fail
	jp	__uputc
_uputw::
	ld	bc, #2
	call	u_arg2
	jr	z, u_fail
	jp	__uputw
; u_arg2: de = second stack argument (user pointer), validate (de, bc)
u_arg2:
	ld	hl, #6
	add	hl, sp
	ld	e, (hl)
	inc	hl
	ld	d, (hl)
	jp	va_core
_uzero::
	ld	hl, #2
	add	hl, sp
	ld	e, (hl)
	inc	hl
	ld	d, (hl)
	inc	hl
	ld	c, (hl)
	inc	hl
	ld	b, (hl)
	call	va_core
	jr	z, u_fail
	jp	__uzero
u_fail:
	ld	hl, #0xffff
	ret
