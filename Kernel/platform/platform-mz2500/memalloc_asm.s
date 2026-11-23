; memalloc_asm.s - memalloc/memfree system calls: no user-visible allocator
	.module memalloc_asm
	.globl __memalloc, __memfree, _udata
	.area _CODE
__memalloc::
__memfree::
	ld	hl, #12			; ENOMEM
	ld	(_udata + 0x0c), hl	; u_error
	ld	hl, #0xffff
	ret
