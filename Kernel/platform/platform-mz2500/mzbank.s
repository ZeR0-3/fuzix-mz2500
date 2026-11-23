;
;	MZ-2500 variant of lib/z80fixedbank-core.s (GPLv2, FUZIX).
;
;	Differences from the stock file:
;	 - a process owns a variable number of 8KB pages (page table _pmap, one
;	   row per bank token); fork copies only the pages in use.
;	 - the udata stash is not inside the process memory but in one shared
;	   stash page (U_STASH_PAGE) holding 512 bytes per token, reached through
;	   window 6 (stash_in / stash_out).
;
;	The caller needs to provide the standard map routines along with
;	map_kernel_a which maps in the kernel bank in a. This code assumes
;	that the bank can be encoded in 8bits.
;
        .module z80fixedbank

        .globl _ptab_alloc
        .globl _makeproc
        .globl _chksigs
        .globl _getproc
        .globl _plt_monitor
        .globl _plt_switchout
        .globl _switchin
        .globl _doexec
        .globl _dofork
        .globl _runticks
        .globl unix_syscall_entry
        .globl interrupt_handler
	.globl _need_resched
	.globl _nready
	.globl _plt_idle
	.globl _int_disabled
	.globl _udata

	.globl map_kernel
	.globl map_proc_a
	.globl map_proc_always
	.globl _curmap
	.globl _pmap


        ; imported debug symbols
        .globl outstring, outde, outhl, outbc, outnewline, outchar, outcharhex

        .include "kernel.def"
        .include "../../cpu-z80/kernel-z80.def"

        .area _COMMONMEM

; __switchout switches out the current process, finds another that is READY,
; possibly the same process, and switches it in.  When a process is
; restarted after calling switchout, it thinks it has just returned
; from switchout().
; 
; This function can have no arguments or auto variables.
;
_plt_switchout:
        ld hl, #0 ; return code set here is ignored, but _switchin can 
        ; return from either _switchout OR _dofork, so they must both write 
        ; U_DATA__U_SP with the following on the stack:
        push hl ; return code
        push ix
        push iy
        ld (_udata + U_DATA__U_SP), sp ; this is where the SP is restored in _switchin

	; Stash the uarea back (shared stash page, indexed by bank token)
	ld a, (_udata + U_DATA__U_PAGE)
	call stash_in

        ; find another process to run (may select this one again)
        call _getproc

        push hl
        call _switchin

        ; we should never get here
        call _plt_monitor

badswitchmsg: .ascii "_switchin: FAIL"
	.db 13, 10, 0
swapped: .ascii "_switchin: SWAPPED"
	.db 13, 10, 0

_switchin:
        di
        pop bc  ; return address
        pop de  ; new process pointer
;
;	FIXME: do we actually *need* to restore the stack !
;
        push de ; restore stack
        push bc ; restore stack

	ld a,#1
	ld (_int_disabled),a

;
;	FIXME: map_kernel_di ?
;
	call map_kernel

        ld hl, #P_TAB__P_PAGE_OFFSET
	add hl, de	; process ptr

.ifne CONFIG_SWAP
	.globl _swapper
	;
	;	Always use the swapstack, otherwise when we call map_kernel
	;	having copied the udata stash back to udata we will crap
	;	somewhere up the stackframe and it's then down to luck
	;	if those bytes are discarded or not.
	;
	;	Yes - this was a bitch to debug, please don't break it !
	;
	ld sp, #_swapstack

        ld a, (hl)

	or a
	jr nz, not_swapped

	;
	;	Re-enable interrupts while we swap. This is ok because
	;	we are not on the IRQ stack when switchin is invoked.
	;
	;	There are two basic cases
	;	#1: pre-emption. Not in a system call, must avoid
	;	re-entering pre-emption logic, Z80 lowlevel code sets U_INSYS
	;	#2: kernel syscall. Also protected by U_DATA__U_INSYS
	;
	ei
	xor a
	ld (_int_disabled),a
	push hl
	push de
	call _swapper
	pop de
	pop hl
	ld a,#1
	ld (_int_disabled),a
	di
.endif
	ld a, (hl)
not_swapped:
	push hl
	ld hl, (_udata + U_DATA__U_PTAB)
	or a
	sbc hl, de
	pop hl
	jr z, skip_copyback	; Tormod's optimisation: don't copy the
				; the stash back if we are the task who
				; last owned the real udata
	ld a,(hl)
	; fetch the stashed uarea of the process we are switching to. The
	; kernel stack lives inside the udata block that is about to be
	; overwritten, so run the copy on a private stack. SP is loaded from
	; the restored udata right after.
	ld sp, #stashstack_top
	call stash_out

	; In the non swap case we must set so before we use the stack
	; otherwise we risk corrupting the restored stack frame
        ld sp, (_udata + U_DATA__U_SP)
	call map_kernel

        ; check u_data->u_ptab matches what we wanted
        ld hl, (_udata + U_DATA__U_PTAB) ; u_data->u_ptab
        or a                    ; clear carry flag
        sbc hl, de              ; subtract, result will be zero if DE==HL
        jr nz, switchinfail

skip_copyback:
	; wants optimising up a bit
	ld ix, (_udata + U_DATA__U_PTAB)
        ; next_process->p_status = P_RUNNING
        ld P_TAB__P_STATUS_OFFSET(ix), #P_RUNNING

	; Fix the moved page pointers
	; Just do one byte as that is all we use on this platform
	ld a, P_TAB__P_PAGE_OFFSET(ix)
	ld (_udata + U_DATA__U_PAGE), a
        ; runticks = 0
        ld hl, #0
        ld (_runticks), hl

        ; restore machine state -- note we may be returning from either
        ; _switchout or _dofork
        ld sp, (_udata + U_DATA__U_SP)

        pop iy
        pop ix
        pop hl ; return code

        ; enable interrupts, if we didn't pre-empt in an ISR
        ld a, (_udata + U_DATA__U_ININTERRUPT)
	ld (_int_disabled),a
        or a
        ret nz ; Not an ISR, leave interrupts off
        ei
        ret ; return with interrupts on

switchinfail:
	call outhl
        ld hl, #badswitchmsg
        call outstring
	; something went wrong and we didn't switch in what we asked for
        jp _plt_monitor


;
;	Called from _fork. We are in a syscall, the uarea is live as the
;	parent uarea. The kernel is the mapped object.
;
_dofork:
        ; always disconnect the vehicle battery before performing maintenance
        di ; should already be the case ... belt and braces.

	;
	; FIXME: we should no longer need interrupts off for most of a
	; fork() call.
	;
        pop de  ; return address
        pop hl  ; new process p_tab*
        push hl
        push de

        ld (fork_proc_ptr), hl

        ; prepare return value in parent process -- HL = p->p_pid;
        ld de, #P_TAB__P_PID_OFFSET
        add hl, de
        ld a, (hl)
        inc hl
        ld h, (hl)
        ld l, a

        ; Save the stack pointer and critical registers.
        ; When this process (the parent) is switched back in, it will be as if
        ; it returns with the value of the child's pid.
        push hl ; HL still has p->p_pid from above, the return value in the parent
        push ix
        push iy

        ; save kernel stack pointer -- when it comes back in the parent we'll be in
        ; _switchin which will immediately return (appearing to be _dofork()
	; returning) and with HL (ie return code) containing the child PID.
        ; Hurray.

        ld (_udata + U_DATA__U_SP), sp

        ; now we're in a safe state for _switchin to return in the parent
	; process.

        ; --------- copy process ---------

        ld hl, (fork_proc_ptr)
        ld de, #P_TAB__P_PAGE_OFFSET
        add hl, de
        ; load p_page
        ld c, (hl)
	; load existing page ptr
	ld a, (_udata + U_DATA__U_PAGE)

	; FIXME: We will redefine this to expect udata as parent and (hl)
	; as child so it's also clean for multibank. For now just make
	; sure HL happens to be right
	call bankfork			;	do the bank to bank copy
	call map_kernel			;	bankfork leaves the child mapped

	; Copy done

	; We are going to copy the uarea into the PARENT's stash (that is
	; what it is resumed from). We must not touch the parent uarea after
	; this point, any changes only affect the child, which carries on
	; with the live udata.
	ld a, (_udata + U_DATA__U_PAGE)
	call stash_in

        ; now the copy operation is complete we can get rid of the stuff
        ; _switchin will be expecting from our copy of the stack.
        pop bc
        pop bc
        pop bc

        ; Make a new process table entry, etc.
	ld hl,#_udata
	push hl
        ld  hl, (fork_proc_ptr)
        push hl
        call _makeproc
        pop bc 
	pop bc

        ; runticks = 0;
        ld hl, #0
        ld (_runticks), hl
        ; in the child process, fork() returns zero.
	;
	; And we exit, with the kernel mapped, the child now being deemed
	; to be the live uarea. The parent is frozen in time and space as
	; if it had done a switchout().
        ret

	.area _COMMONDATA
stashstack:
	.ds 24
stashstack_top:
;
;	For the moment
;
bouncebuffer:
	.ds 256
;
;	We can keep a stack in common because we will complete our
;	use of it before we switch common block. In this case we have
;	a true common so it's even easier. This can share with the bounce
;	buffer used by bankfork as we won't switchin mid way through the
;	banked fork() call.
;
_swapstack:
_need_resched:	.db 0
fork_proc_ptr: .dw 0 ; (C type is struct p_tab *) -- address of child process p_tab entry

;
;	Copy the memory of the parent (token in A) to the child (token in C).
;	Only the pages the process really owns are copied: u_top rounded up
;	to 8KB, in 256 byte blocks through the bounce buffer.
;
	.area _COMMONMEM

bankfork:
	push af			; parent token
	ld hl, (_udata + U_DATA__U_TOP)
	ld de, #0x1FFF
	add hl, de
	ld a, h
	and #0xE0		; pages = (top + 1FFF) >> 13
	rrca
	rrca
	rrca
	rrca
	rrca
	ld (bf_np), a
	ld a, c
	ld (bf_child), a
	pop af
	ld (bf_parent), a
	call map_proc_a		; parent mapped; copy page i of window i into the
				; child's page through a spare window (6, or 5 for i=6)
	xor a
	ld (bf_i), a
bf_page:
	ld a, (bf_i)
	ld hl, #bf_np
	cp (hl)
	ret nc
	ld e, #6
	cp #6
	jr nz, bf_w6
	ld e, #5
bf_w6:
	ld a, e
	ld (bf_w), a
	ld a, (bf_child)
	call bf_row
	ld a, (bf_i)
	ld c, a
	ld b, #0
	add hl, bc
	ld a, (hl)
	ld (bf_cp), a		; child page for this window index
	ld a, (bf_parent)
	call bf_row
	ld a, (bf_w)
	ld c, a
	ld b, #0
	add hl, bc
	ld a, (hl)
	ld (bf_pp), a		; parent page the spare window normally holds
	ld a, (bf_i)		; source = i * 0x2000
	rlca
	rlca
	rlca
	rlca
	rlca
	ld h, a
	ld l, #0
	ld a, (bf_w)		; dest = w * 0x2000
	rlca
	rlca
	rlca
	rlca
	rlca
	ld d, a
	ld e, #0
	ld b, #8		; 8 chunks of 1KB, interrupts held off per chunk
bf_chunk:
	push bc
	ld a, (_int_disabled)
	push af
	di
	ld a, (bf_w)
	out (0xB4), a
	ld a, (bf_cp)
	out (0xB5), a
	ld bc, #1024
	ldir
	ld a, (bf_w)
	out (0xB4), a
	ld a, (bf_pp)
	out (0xB5), a
	pop af
	or a
	jr nz, bf_noei
	ei
bf_noei:
	pop bc
	djnz bf_chunk
	ld hl, #bf_i
	inc (hl)
	jr bf_page

bf_row:				; A = token -> HL = &_pmap[token][0]
	ld l, a
	ld h, #0
	add hl, hl
	add hl, hl
	add hl, hl
	ld bc, #_pmap
	add hl, bc
	ret

	.area _COMMONDATA
bf_np:		.db 0
bf_child:	.db 0
bf_parent:	.db 0
bf_i:		.db 0
bf_w:		.db 0
bf_cp:		.db 0
bf_pp:		.db 0
	.area _COMMONMEM

;
;	udata stash: one shared page (U_STASH_PAGE), 512 bytes per bank token,
;	reached by temporarily putting the page in window 6 (C000). All
;	registers except AF are preserved. Interrupts are held off while
;	window 6 is not the text VRAM.
;
;	stash_in:  token in A, copies _udata to the stash
;	stash_out: token in A, copies the stash to _udata
;
stash_in:
	push bc
	push de
	push hl
	ld c, a
	ld a, (_int_disabled)
	push af
	di
	call stash_map
	ld d, h			; DE = stash of this token (set by stash_map)
	ld e, l
	ld hl, #_udata
	ld bc, #U_DATA__TOTALSIZE
	ldir
	jr stash_done

stash_out:
	push bc
	push de
	push hl
	ld c, a
	ld a, (_int_disabled)
	push af
	di
	call stash_map
	ld de, #_udata
	ld bc, #U_DATA__TOTALSIZE
	ldir
stash_done:
	call stash_unmap
	pop af
	or a
	jr nz, stash_ret
	ei
stash_ret:
	pop hl
	pop de
	pop bc
	ret

;	C = token. Maps the stash page into window 6 and returns HL = stash
;	address of the token. Trashes A.
stash_map:
	ld a, #6
	out (0xB4), a
	ld a, #U_STASH_PAGE
	out (0xB5), a
	ld a, c
	add a, a		; token * 0x200 = high byte token * 2
	add a, #0xC0
	ld h, a
	ld l, #0
	ret

;	Put window 6 back as the current bank map has it
stash_unmap:
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
	ret
