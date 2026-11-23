; Hand written small system calls (formerly SDCC output in k_syscall_*.s).
; SDCC convention: result in HL, IX preserved, others may be destroyed.
; udata: u_ptab +0, u_error +0x0c, u_argn +0x12, u_umask +0x6d, u_gid +0x6f,
;        u_euid +0x71, u_egid +0x73
; p_tab: p_pid +3, p_uid +5, p_pptr +7, p_alarm +9, p_pgrp +0x41
	.module sys_asm
	.globl _udata, _doexit, _doclose, _sync, _switchout, _ptimer_insert, _of_tab
	.globl __getegid, __geteuid, __getgid, __getuid, __getpid, __getppid, __getpgrp
	.globl __sched_yield, ___exit, __alarm, __sync, __nosys, __close, __read, __write
	.globl __umask, _updoff, __acct, __profil
	.area _CODE

__getegid::
	ld hl, (_udata + 0x73)
	ret
__geteuid::
	ld hl, (_udata + 0x71)
	ret
__getgid::
	ld hl, (_udata + 0x6f)
	ret
__getuid::
	ld hl, (_udata + 0)
	ld de, #5
	jr gt_w
__getpid::
	ld hl, (_udata + 0)
	ld de, #3
	jr gt_w
__getpgrp::
	ld hl, (_udata + 0)
	ld de, #0x41
gt_w:				; hl = *(word*)(hl + de)
	add hl, de
	ld a, (hl)
	inc hl
	ld h, (hl)
	ld l, a
	ret
__getppid::
	ld hl, (_udata + 0)
	ld de, #7
	add hl, de
	ld a, (hl)
	inc hl
	ld h, (hl)
	ld l, a			; parent
	ld de, #3
	jr gt_w

__sched_yield::
	call _switchout
	ld hl, #0
	ret

; void _exit(int val): doexit((val & 0xff) << 8)
___exit::
	ld hl, (_udata + 0x12)
	ld b, l
	ld c, #0
	push bc
	call _doexit
	pop af
	ld hl, #0
	ret

; unsigned alarm(unsigned secs): returns the previous p_alarm
__alarm::
	ld hl, (_udata + 0)
	ld de, #9
	add hl, de
	ld c, (hl)
	inc hl
	ld b, (hl)
	push bc			; old value
	ld de, (_udata + 0x12)
	ld (hl), d
	dec hl
	ld (hl), e
	call _ptimer_insert
	pop hl
	ret

__sync::
	call _sync
	ld hl, #0
	ret

__nosys::
__profil::
	ld hl, #0x2a		; ENOSYS
	jr sy_err
__acct::
	ld hl, #0x16		; EINVAL
sy_err:
	ld (_udata + 0x0c), hl
	ld hl, #0xffff
	ret

__close::
	ld a, (_udata + 0x12)
	push af
	inc sp
	call _doclose
	inc sp
	ret

__read::
	ld a, #1
	jr rw_go
__write::
	xor a
rw_go:
	ld hl, (_udata + 22)
	ld e, a
	ld a, h
	or l
	ret z
	bit 7, h
	jr z, rw_1
	ld hl, #0x16
	ld (_udata + 0x0c), hl
	ld hl, #0xffff
	ret
rw_1:
	push de
	ld a, e
	push af
	inc sp
	push hl
	ld hl, (_udata + 20)
	push hl
	call _valaddr
	pop af
	pop af
	inc sp
	ld a, h
	or l
	jr z, rw_fail
	ld hl, #0
	add hl, sp
	ld a, (hl)
	inc hl
	push hl
	push af
	inc sp
	call _rwsetup
	pop af
	inc sp
	ld a, h
	or l
	jr z, rw_fail
	ld c, l
	ld b, h
	pop de
	ld a, d
	push af
	inc sp
	push bc
	ld a, e
	or a
	jr z, rw_w
	call _readi
	jr rw_d
rw_w:
	call _writei
rw_d:
	pop af
	inc sp
	call _updoff
	ld hl, (_udata + 0x99)
	ret
rw_fail:
	pop de
	ld hl, #0xffff
	ret

; int umask(int mask): returns the old mask
__umask::
	ld hl, (_udata + 0x6d)
	ld de, (_udata + 0x12)
	ld a, d
	and #1
	ld d, a
	ld (_udata + 0x6d), de
	ret

; void updoff(void): of_tab[u_files[u_argn]].o_ptr = u_offset
_updoff::
	ld hl, (_udata + 0x12)
	ld de, #(_udata + 125)	; u_files
	add hl, de
	ld l, (hl)
	call	ixh_oft
	push hl
	pop iy
	ld bc, (_udata + 102)	; u_offset (4 bytes)
	ld hl, (_udata + 104)
	ld 0 (iy), c
	ld 1 (iy), b
	ld 2 (iy), l
	ld 3 (iy), h
	ret

; ---- chdir / fchdir / chroot / chmod / fchmod / chown / fchown ----
; inode: c_node.i_mode +6 (2B), i_uid +10, i_gid +12, c_refs +0x46, c_flags +0x49 (CRDONLY 0x40)
; udata: u_argn +0x12, u_argn1 +0x14, u_argn2 +0x16, u_euid +0x71, u_egid +0x73, u_cwd +0x89, u_root +0x8b
	.globl _n_open, _getinode, _i_deref, _getmode, _esuper, _setftime
	.globl __chdir, __fchdir, __chroot, __chmod, __fchmod, __chown, __fchown

; arg_t chdiroot_op(inoptr ino, inoptr *p)   (stack: ino 2(sp), p 4(sp))
cr_op:
	call	ixh_sp2_ed
	push de
	call _getmode
	pop de
	ld a, l
	cp #0x40		; MODE_R(F_DIR)
	jr z, cr_ok
	ld hl, #0x14		; ENOTDIR
	ld (_udata + 0x0c), hl
	push de
	call _i_deref
	pop af
	ld hl, #0xffff
	ret
cr_ok:
	ld hl, #4
	add hl, sp
	ld a, (hl)
	inc hl
	ld h, (hl)
	ld l, a			; hl = p
	ld c, (hl)
	inc hl
	ld b, (hl)
	dec hl
	push hl
	push bc
	call _i_deref		; i_deref(*p)
	pop af
	pop hl
	ld iy, #2
	add iy, sp
	ld a, 0 (iy)		; *p = ino
	ld (hl), a
	inc hl
	ld a, 1 (iy)
	ld (hl), a
	ld hl, #0
	ret

__chdir::
	ld hl, #(_udata + 0x89)
	jr cd_open
__chroot::
	call _esuper
	bit 0, l
	jr z, cd_root
	ld hl, #0xffff
	ret
cd_root:
	ld hl, #(_udata + 0x8b)
cd_open:
	push hl			; &u_cwd / &u_root
	ld hl, (_udata + 0x12)
	ld bc, #0
	push bc
	push hl
	call _n_open
	pop af
	pop af
	ld a, h
	or l
	jr nz, cd_go
	pop af
	ld hl, #0xffff
	ret
cd_go:
	pop bc			; bc = pointer; stack: ino, ptr
	push bc
	push hl
	call cr_op
	pop af
	pop af
	ret

__fchdir::
	call	ixh_getinode_argn
	ld a, h
	or l
	jr nz, fcd_go
	ld hl, #0xffff
	ret
fcd_go:
	ld c, l
	ld b, h
	ld de, #0x46
	add hl, de
	inc (hl)		; i_ref
	ld hl, #(_udata + 0x89)
	push hl
	push bc
	call cr_op
	pop af
	pop af
	ret

; arg_t chmod_op(inoptr ino)
cm_op:
	call	ixh_sp2_cb
	ld hl, #10
	add hl, bc
	ld e, (hl)
	inc hl
	ld d, (hl)		; i_uid
	ld hl, (_udata + 0x71)	; u_euid
	or a
	sbc hl, de
	jr z, cm_1
	push bc
	call _esuper
	pop bc
	bit 0, l
	jr z, cm_1
	ld hl, #0xffff
	ret
cm_1:
	ld hl, #0x49
	add hl, bc
	bit 6, (hl)		; CRDONLY
	jr z, cm_2
	ld hl, #0x1e		; EROFS
	ld (_udata + 0x0c), hl
	ld hl, #0xffff
	ret
cm_2:
	ld hl, #7
	add hl, bc
	ld a, (hl)
	and #0xf0		; keep file type bits
	ld d, a
	ld a, (_udata + 0x15)
	and #0x0f
	or d
	ld (hl), a
	dec hl
	ld a, (_udata + 0x14)
	ld (hl), a
	jp set_ctime

; arg_t chown_op(inoptr ino)
co_op:
	call	ixh_sp2_cb
	ld hl, #0x49
	add hl, bc
	bit 6, (hl)
	jr z, co_1
	ld hl, #0x1e		; EROFS
	ld (_udata + 0x0c), hl
	ld hl, #0xffff
	ret
co_1:
	ld hl, (_udata + 0x14)	; owner
	ld a, l
	and h
	inc a
	jr z, co_noown
	push bc
	call _esuper
	pop bc
	bit 0, l
	jr z, co_o
	ld hl, #0xffff
	ret
co_o:
	ld hl, #10
	add hl, bc
	ld de, (_udata + 0x14)
	ld (hl), e
	inc hl
	ld (hl), d
	jr co_grp
co_noown:
	ld hl, (_udata + 0x16)	; group == -1 too: no-op
	ld a, l
	and h
	inc a
	jr nz, co_grp
	ld hl, #0
	ret
co_grp:
	ld hl, (_udata + 0x16)
	ld a, l
	and h
	inc a
	jr z, co_mode
	ld hl, #10
	add hl, bc
	ld a, (hl)
	inc hl
	ld h, (hl)
	ld l, a			; i_uid
	ld de, (_udata + 0x71)
	or a
	sbc hl, de
	jr nz, co_es
	ld hl, (_udata + 0x16)
	ld de, (_udata + 0x73)	; u_egid
	or a
	sbc hl, de
	jr z, co_g
co_es:
	push bc
	call _esuper
	pop bc
	bit 0, l
	jr z, co_g
	ld hl, #0xffff
	ret
co_g:
	ld hl, #12
	add hl, bc
	ld de, (_udata + 0x16)
	ld (hl), e
	inc hl
	ld (hl), d
co_mode:
	ld hl, #7
	add hl, bc
	ld a, (hl)
	and #0xf3		; clear SET_UID|SET_GID
	ld (hl), a
set_ctime:			; setftime(ino, C_TIME); return 0
	ld a, #4
	push af
	inc sp
	push bc
	call _setftime
	pop af
	inc sp
	ld hl, #0
	ret

__chmod::
	ld hl, #cm_op
	jr pm_open
__chown::
	ld hl, #co_op
pm_open:
	push hl			; op
	ld hl, (_udata + 0x12)
	ld bc, #0
	push bc
	push hl
	call _n_open
	pop af
	pop af
	ld a, h
	or l
	jr nz, pm_go
	pop af
	ld hl, #0xffff
	ret
pm_go:
	pop de			; de = op
	push hl			; ino (for deref)
	push hl			; arg
	ld bc, #pm_ret
	push bc
	push de
	ret			; jump to op with return to pm_ret
pm_ret:
	pop bc			; arg
	pop bc			; ino
	push hl
	push bc
	call _i_deref
	pop af
	pop hl
	ret

__fchmod::
	ld hl, #cm_op
	jr pf_go
__fchown::
	ld hl, #co_op
pf_go:
	push hl
	call	ixh_getinode_argn
	pop de			; op
	ld a, h
	or l
	jr nz, pf_ok
	ld hl, #0xffff
	ret
pf_ok:
	push hl
	ld bc, #pf_ret
	push bc
	push de
	ret
pf_ret:
	pop af
	ret

; ---- stat copy / fstat / getdirent / setpgrp ----
	.globl _uput, _stcpy, __fstat, __getdirent, __setpgrp
	.area _DATA
st_buf:
	.ds 34
	.area _CODE

; arg_t stcpy(inoptr ino, struct _uzistat *buf)  -- builds the stat record, uput()s it
_stcpy::
	call	ixh_sp2_cb
	push bc
	ld hl, #2		; c_dev, c_num
	add hl, bc
	ld de, #st_buf
	ld bc, #4
	ldir
	pop bc
	push bc
	ld hl, #6		; i_mode .. (8 bytes)
	add hl, bc
	ld de, #(st_buf + 4)
	ld bc, #8
	ldir
	pop bc
	push bc
	ld hl, #0x1e		; i_addr[0] (st_rdev)
	add hl, bc
	ld de, #(st_buf + 12)
	ld bc, #2
	ldir
	pop bc
	ld hl, #0x0e		; i_size, times (16 bytes)
	add hl, bc
	ld de, #(st_buf + 14)
	ld bc, #16
	ldir
	call	ixh_sp4_cb
	ld hl, #34
	push hl
	push bc
	ld hl, #st_buf
	push hl
	call _uput
	pop af
	pop af
	pop af
	ret

__fstat::
	call	ixh_getinode_argn
	ld a, h
	or l
	jr nz, fs_go
	ld hl, #0xffff
	ret
fs_go:
	ld bc, (_udata + 0x14)
	push bc
	push hl
	call _stcpy
	pop af
	pop af
	ret

; arg_t getdirent(): read exactly one 32-byte directory entry
__getdirent::
	ld hl, (_udata + 0x16)
	bit 7, h		; negative (as int16) is too small too
	jr nz, gd_err
	ld de, #32
	or a
	sbc hl, de
	jr nc, gd_ok
gd_err:
	ld hl, #0x1c		; ENOSPC
	ld (_udata + 0x0c), hl
	ld hl, #0xffff
	ret
gd_ok:
	ld hl, #32
	ld (_udata + 0x16), hl
	jp __read

; arg_t setpgrp(): pgrp = pid, no controlling tty
__setpgrp::
	ld hl, (_udata + 0)
	ld de, #3
	add hl, de
	ld c, (hl)
	inc hl
	ld b, (hl)		; p_pid
	ld hl, (_udata + 0)
	ld de, #0x41
	add hl, de
	ld (hl), c
	inc hl
	ld (hl), b
	ld hl, (_udata + 0)
	inc hl
	inc hl
	ld (hl), #0		; p_tty
	ld hl, #0
	ret

; ---- stat / dup / dup2 / unlink ----
	.globl _uf_alloc, _unlinki, _lastname, __stat, __dup, __dup2, __unlink
; arg_t stat(path, buf)
__stat::
	ld hl, (_udata + 0x12)
	ld bc, #0
	push bc
	push hl
	call _n_open
	pop af
	pop af
	ld a, h
	or l
	jr nz, st_go
	ld hl, #0xffff
	ret
st_go:
	ld c, l
	ld b, h
	push bc			; ino (for i_deref)
	ld hl, (_udata + 0x14)
	push hl
	push bc
	call _stcpy
	pop af
	pop af
	pop bc
	push hl			; result
	push bc
	call _i_deref
	pop af
	pop hl
	ret

; arg_t dup(int oldd)
__dup::
	call	ixh_getinode_argn
	ld a, h
	or l
	jr nz, dp_1
	ld hl, #0xffff
	ret
dp_1:
	call _uf_alloc
	ld a, l
	inc a
	jr nz, dp_ok
	ld hl, #0xffff
	ret
dp_ok:
	ld c, l			; c = newd
	ld b, #0
	push bc
	ld hl, #(_udata + 125)	; u_files
	add hl, bc
	ex de, hl
	ld hl, (_udata + 0x12)
	ld bc, #(_udata + 125)
	add hl, bc
	ld a, (hl)
	ld (de), a		; u_files[newd] = u_files[oldd]
	call of_ref
	pop hl
	ret
; ++of_tab[a].o_refs
of_ref:
	ld l, a
	ld h, #0
	add hl, hl
	add hl, hl
	add hl, hl
	ld de, #(_of_tab + 7)
	add hl, de
	inc (hl)
	ret

; arg_t dup2(int oldd, int newd)
__dup2::
	call	ixh_getinode_argn
	ld a, h
	or l
	jr nz, d2_1
	ld hl, #0xffff
	ret
d2_1:
	ld bc, (_udata + 0x14)
	bit 7, b
	jr nz, d2_bad
	ld a, b
	or a
	jr nz, d2_bad
	ld a, c
	cp #10			; UFTSIZE
	jr c, d2_2
d2_bad:
	ld hl, #9		; EBADF
	ld (_udata + 0x0c), hl
	ld hl, #0xffff
	ret
d2_2:
	ld hl, (_udata + 0x12)
	or a
	sbc hl, bc
	jr nz, d2_3
	ld hl, (_udata + 0x12)	; newd == oldd: no-op
	ret
d2_3:
	ld hl, #(_udata + 125)
	add hl, bc
	ld a, (hl)
	inc a
	jr z, d2_4		; NO_FILE
	ld a, c
	push af
	inc sp
	call _doclose
	inc sp
d2_4:
	ld bc, (_udata + 0x14)
	ld hl, #(_udata + 125)
	add hl, bc
	ex de, hl
	ld hl, (_udata + 0x12)
	ld bc, #(_udata + 125)
	add hl, bc
	ld a, (hl)
	ld (de), a
	call of_ref
	ld hl, (_udata + 0x14)
	ret

; arg_t unlink(path)    local: -2 pino
__unlink::
	call ___sdcc_enter_ix
	push af
	ld hl, #0
	add hl, sp
	ex de, hl		; de = &pino
	xor a
	ld -2 (ix), a
	ld -1 (ix), a
	ld hl, (_udata + 0x12)
	push de
	push hl
	call _n_open
	pop af
	pop af
	ld c, l
	ld b, h			; bc = ino
	ld a, -1 (ix)
	or -2 (ix)
	jr z, ul_err
	ld a, b
	or c
	jr nz, ul_ok
ul_err:
	ld a, -1 (ix)
	or -2 (ix)
	jr z, ul_e2
	call	ixh_lh_m2
	call	ixh_p1_i_deref
ul_e2:
	ld hl, (_udata + 0x0c)
	ld a, h
	or l
	jr nz, ul_e3
	ld hl, #2		; ENOENT
	ld (_udata + 0x0c), hl
ul_e3:
	ld hl, #0xffff
	jr ul_ret
ul_ok:
	push bc
	ld hl, #_lastname
	push hl
	call	ixh_lh_m2
	push hl
	push bc
	call _unlinki
	pop af
	pop af
	pop af
	pop bc
	push hl			; result
	push bc
	call	ixh_ed_m2
	push de
	call _i_deref		; i_deref(pino)
	pop af
	call _i_deref		; i_deref(ino)
	pop af
	pop hl
ul_ret:
	jp	ixh_leave

; ---- time / stime / times / pause / setuid / setgid ----
	.globl _rdtime, _wrtime, _uget, _super, _psleep, _ticks
	.globl __time, __stime, __times, __pause, __setuid, __setgid
; arg_t time(void *tvec, int type)    local: t (8 bytes) at -8(ix)
__time::
	call ___sdcc_enter_ix
	ld hl, #-8
	add hl, sp
	ld sp, hl
	ld bc, (_udata + 0x14)	; type
	ld a, b
	or a
	jr nz, tm_bad
	ld a, c
	or a
	jr z, tm_rd
	dec a
	jr nz, tm_bad
	ld hl, (_ticks)		; type 1: t.low = ticks, t.high = 0
	ld -8 (ix), l
	ld -7 (ix), h
	ld hl, (_ticks + 2)
	ld -6 (ix), l
	ld -5 (ix), h
	xor a
	ld -4 (ix), a
	ld -3 (ix), a
	ld -2 (ix), a
	ld -1 (ix), a
	jr tm_put
tm_rd:
	ld hl, #0
	add hl, sp
	push hl
	call _rdtime
	pop af
tm_put:
	ld bc, (_udata + 0x12)
	ld hl, #0
	add hl, sp
	ld de, #8
	push de
	push bc
	push hl
	call _uput
	pop af
	pop af
	pop af
	jr tm_ret
tm_bad:
	ld hl, #0x16		; EINVAL
	ld (_udata + 0x0c), hl
	ld hl, #0xffff
tm_ret:
	jp	ixh_leave

; arg_t stime(void *tvec, int type)
__stime::
	call ___sdcc_enter_ix
	ld hl, #-8
	add hl, sp
	ld sp, hl
	ld de, (_udata + 0x14)
	ld a, d
	or e
	jr z, sti_1
	ld hl, #0x16
	ld (_udata + 0x0c), hl
	ld hl, #0xffff
	jr sti_ret
sti_1:
	ld hl, #0
	add hl, sp
	ex de, hl		; de = &t
	ld hl, (_udata + 0x12)
	push de
	ld bc, #8
	push bc
	push de
	push hl
	call _uget
	pop af
	pop af
	pop af
	pop de
	ld a, h
	or l
	jr nz, sti_err
	push de
	call _esuper
	pop de
	bit 0, l
	jr z, sti_2
sti_err:
	ld hl, #0xffff
	jr sti_ret
sti_2:
	push de
	call _wrtime
	pop af
	ld hl, #0
sti_ret:
	jp	ixh_leave

; arg_t times(struct tms *buf)
__times::
	call ___hard_di
	push hl			; saved irq state
	ld iy, (_udata + 0x12)
	ld hl, (_udata + 0)
	ld de, #0x31		; &p_utime
	add hl, de
	ld de, #16
	push de
	push iy
	push hl
	call _uput
	pop af
	pop af
	pop af
	ld de, (_udata + 0x12)
	ld hl, #16
	add hl, de
	ex de, hl
	ld hl, #4
	push hl
	push de
	ld hl, #_ticks
	push hl
	call _uput
	pop af
	pop af
	pop af
	call ___hard_irqrestore	; arg already on the stack
	pop af
	ld hl, #0
	ret

; arg_t pause(unsigned t)   t == 0: wait for a signal
__pause::
	call ___hard_di
	push hl			; saved irq state
	ld de, (_udata + 0x12)
	ld a, d
	or e
	jr z, pa_1
	ld hl, (_udata + 0)
	push de
	ld de, #0x23
	add hl, de
	pop de
	inc de
	ld (hl), e		; p_timeout = t + 1
	inc hl
	ld (hl), d
	call _ptimer_insert
pa_1:
	ld hl, #0
	push hl
	call _psleep
	pop af
	call ___hard_irqrestore
	pop af
	ld hl, (_udata + 0x12)
	ld a, h
	or l
	jr z, pa_intr
	ld hl, (_udata + 0)
	ld de, #0x23
	add hl, de
	ld c, (hl)
	inc hl
	ld b, (hl)
	ld a, #1
	cp c
	ld a, #0
	sbc a, b
	jr nc, pa_ok		; p_timeout <= 1: timer expired
pa_intr:
	ld hl, #4		; EINTR
	ld (_udata + 0x0c), hl
	ld hl, #0xffff
	ret
pa_ok:
	ld hl, #0
	ret

; arg_t setuid(uid)
__setuid::
	call _super
	bit 0, l
	jr nz, su_ok
	ld hl, (_udata + 0)
	ld de, #5
	add hl, de
	ld e, (hl)
	inc hl
	ld d, (hl)		; p_uid
	ld bc, (_udata + 0x12)
	ld a, e
	sub c
	jr nz, su_1
	ld a, d
	sub b
	jr z, su_ok
su_1:
	ld de, (_udata + 0x71)	; u_euid
	ld a, c
	sub e
	jr nz, su_bad
	ld a, b
	sub d
	jr nz, su_bad
su_ok:
	ld hl, (_udata + 0x71)
	ld a, h
	or l
	jr nz, su_2
	ld hl, (_udata + 0)
	ld de, #5
	add hl, de
	ld de, (_udata + 0x12)
	ld (hl), e
	inc hl
	ld (hl), d
su_2:
	ld bc, (_udata + 0x12)
	ld (_udata + 0x71), bc
	ld hl, #0
	ret
su_bad:
	ld hl, #1		; EPERM
	ld (_udata + 0x0c), hl
	ld hl, #0xffff
	ret

; arg_t setgid(gid)
__setgid::
	call _super
	bit 0, l
	jr nz, sg_ok
	ld de, (_udata + 0x6f)	; u_gid
	ld bc, (_udata + 0x12)
	ld a, e
	sub c
	jp nz, sg_1
	ld a, d
	sub b
	jr z, sg_ok
sg_1:
	ld de, (_udata + 0x73)	; u_egid
	ld a, c
	sub e
	jr nz, sg_bad
	ld a, b
	sub d
	jr nz, sg_bad
sg_ok:
	ld hl, (_udata + 0x73)
	ld a, h
	or l
	jp nz, sg_2
	ld bc, (_udata + 0x12)
	ld (_udata + 0x6f), bc
sg_2:
	ld bc, (_udata + 0x12)
	ld (_udata + 0x73), bc
	ld hl, #0
	ret
sg_bad:
	ld hl, #1
	ld (_udata + 0x0c), hl
	ld hl, #0xffff
	ret

; ---- lseek / ioctl ----
	.globl _getmode, _isdevice, _d_ioctl, __lseek, __ioctl
; arg_t lseek(int file, off_t *offset, int flag)   u_argn file, u_argn1 offset(user ptr), u_argn2 flag
; locals: -2/-1 oft*, -6..-3 n, -10..-7 p, -12/-11 ino
__lseek::
	call ___sdcc_enter_ix
	ld hl, #-12
	add hl, sp
	ld sp, hl
	push ix
	pop hl
	ld de, #-6
	add hl, de
	ex de, hl		; de = &n
	ld hl, (_udata + 0x14)
	ld bc, #4
	push bc
	push de
	push hl
	call _uget
	pop af
	pop af
	pop af
	ld a, h
	or l
	jr z, ls_1
	ld hl, #0xffff
	jp ls_ret
ls_1:
	call	ixh_getinode_argn
	ld a, h
	or l
	jr nz, ls_2
	ld hl, #0xffff
	jp ls_ret
ls_2:
	ld -12 (ix), l
	ld -11 (ix), h
	call	ixh_p1_getmode
	ld a, l
	cp #0x10		; F_PIPE
	jr nz, ls_3
	ld hl, #0x1d		; ESPIPE
	ld (_udata + 0x0c), hl
	ld hl, #0xffff
	jp ls_ret
ls_3:
	ld hl, #(_udata + 125)
	ld de, (_udata + 0x12)
	add hl, de
	ld l, (hl)
	call	ixh_oft
	ld -2 (ix), l
	ld -1 (ix), h
	ld a, (hl)		; p = o->o_ptr
	ld -10 (ix), a
	inc hl
	ld a, (hl)
	ld -9 (ix), a
	inc hl
	ld a, (hl)
	ld -8 (ix), a
	inc hl
	ld a, (hl)
	ld -7 (ix), a
	ld hl, (_udata + 0x16)	; flag
	ld a, h
	or l
	jr z, ls_f0
	ld a, l
	dec a
	or h
	jr z, ls_f1
	ld a, l
	sub #2
	or h
	jr nz, ls_bad
	call	ixh_lh_m12
	ld de, #0x0e
	add hl, de
	ld c, (hl)
	inc hl
	ld b, (hl)
	inc hl
	ld e, (hl)
	inc hl
	ld d, (hl)
	jr ls_add
ls_f1:				; SEEK_CUR
	ld c, -10 (ix)
	ld b, -9 (ix)
	ld e, -8 (ix)
	ld d, -7 (ix)
	jr ls_add
ls_f0:				; SEEK_SET
	ld bc, #0
	ld de, #0
ls_add:
	ld a, c
	add a, -6 (ix)
	ld c, a
	ld a, b
	adc a, -5 (ix)
	ld b, a
	ld a, e
	adc a, -4 (ix)
	ld e, a
	ld a, d
	adc a, -3 (ix)
	ld d, a
	bit 7, d
	jr nz, ls_bad
	ld -10 (ix), c
	ld -9 (ix), b
	ld -8 (ix), e
	ld -7 (ix), d
	call	ixh_lh_m2
	ld (hl), c
	inc hl
	ld (hl), b
	inc hl
	ld (hl), e
	inc hl
	ld (hl), d
	ld hl, #4
	push hl
	ld hl, (_udata + 0x14)
	push hl
	push ix
	pop hl
	ld de, #-10
	add hl, de
	push hl
	call _uput
	pop af
	pop af
	pop af
	ld hl, #0
	jr ls_ret
ls_bad:
	ld hl, #0x16		; EINVAL
	ld (_udata + 0x0c), hl
	ld hl, #0xffff
ls_ret:
	jp	ixh_leave

; arg_t ioctl(int fd, int request, void *data)   locals: -1 rclass, -3/-2 ino, -5/-4 oft
__ioctl::
	call ___sdcc_enter_ix
	push af
	push af
	push af
	ld a, (_udata + 0x15)
	and #0xc0
	ld -1 (ix), a
	call	ixh_getinode_argn
	ld a, h
	or l
	jr nz, io_1
	ld hl, #0xffff
	jp io_ret
io_1:
	ld -3 (ix), l
	ld -2 (ix), h
	ld hl, #(_udata + 125)
	ld de, (_udata + 0x12)
	add hl, de
	ld l, (hl)
	call	ixh_oft
	ld -5 (ix), l
	ld -4 (ix), h
	ld l, -3 (ix)
	ld h, -2 (ix)
	push hl
	call _isdevice
	pop af
	bit 0, l
	jr z, io_nott
	ld a, -1 (ix)
	cp #0x80		; IOCTL_CLASS_KERNEL
	jr nz, io_2
io_nott:
	ld hl, #0x19		; ENOTTY
	ld (_udata + 0x0c), hl
	ld hl, #0xffff
	jr io_ret
io_2:
	ld a, -1 (ix)
	cp #0x40		; IOCTL_CLASS_SUPER
	jr nz, io_3
	call _esuper
	bit 0, l
	jr z, io_3
	ld hl, #0xffff
	jr io_ret
io_3:
	ld a, -1 (ix)
	cp #0xc0		; IOCTL_CLASS_WRONLY
	jr nz, io_4
	call	ixh_lh_m5
	ld de, #6		; o_access
	add hl, de
	ld a, (hl)
	and #3
	jr nz, io_4		; not O_RDONLY
	ld hl, #1		; EPERM
	ld (_udata + 0x0c), hl
	ld hl, #0xffff
	jr io_ret
io_4:
	ld l, -3 (ix)
	ld h, -2 (ix)
	ld de, #0x1e		; i_addr[0] = device number
	add hl, de
	ld c, (hl)
	inc hl
	ld b, (hl)
	ld de, (_udata + 0x16)	; data
	ld hl, (_udata + 0x14)	; request
	push de
	push hl
	push bc
	call _d_ioctl
	pop af
	pop af
	pop af
io_ret:
	jp	ixh_leave

; ---------------------------------------------------------------
; M78: nice, uname
; ---------------------------------------------------------------
	.globl _procmem, _sysinfo, _ticks_per_dsecond, _loadavg, _pagemap_mem_used
	.globl __nice, __uname

; arg_t _nice(void): np = p_nice + pri, clamp -20..19
__nice::
	ld bc, (_udata + 0)		; p
	ld hl, (_udata + 0x12)		; pri
	bit 7, h
	jr z, nc_1
	push bc
	call _esuper
	pop bc
	bit 0, l
	jr nz, nc_1
	ld hl, #0xffff
	ret
nc_1:
	ld iy, #0x43			; p_nice
	add iy, bc
	ld e, 0 (iy)
	ld d, #0
	ld hl, (_udata + 0x12)
	add hl, de
	ex de, hl			; DE = np
	ld hl, #20
	add hl, de
	bit 7, h			; np < -20 ?
	jr z, nc_2
	ld de, #0xffec
nc_2:
	ld hl, #0xffec			; -20
	add hl, de			; np - 20
	bit 7, h
	jr nz, nc_3			; np < 20
	ld de, #19
nc_3:
	ld 0 (iy), e
	ld hl, #0x13			; p_priority
	add hl, bc
	ld c, e
	ld b, d
	sra b
	rr c
	sra b
	rr c
	ld a, #25
	sub c
	ld (hl), a
	inc hl
	ld a, #0
	sbc b
	ld (hl), a
	ld hl, #20
	add hl, de
	ret

; arg_t _uname(void)
__uname::
	ld bc, #0x3c
	ld hl, (_udata + 0x14)		; len
	ld a, l
	sub #0x3c
	ld a, h
	sbc #0
	jr nc, un_1
	ld c, l
	ld b, h
un_1:
	ld hl, (_procmem)
	ld (_sysinfo + 6), hl
	push bc
	call _pagemap_mem_used
	pop bc
	ld (_sysinfo + 8), hl
	ld a, #15
	ld (_sysinfo + 3), a
	ld a, (_ticks_per_dsecond)
	ld l, a
	ld h, #0
	ld e, l
	ld d, h
	add hl, hl
	add hl, hl
	add hl, de
	add hl, hl
	ld (_sysinfo + 4), hl
	ld hl, (_loadavg + 1)
	ld (_sysinfo + 0x0c), hl
	ld hl, (_loadavg + 4)
	ld (_sysinfo + 0x0e), hl
	ld hl, (_loadavg + 7)
	ld (_sysinfo + 0x10), hl
	ld hl, (_udata + 0x12)		; buf
	push bc
	push bc
	push hl
	ld hl, #_sysinfo
	push hl
	call _uput
	pop af
	pop af
	pop af
	pop hl
	ret

; ---------------------------------------------------------------
; M78: mknod, access
; ---------------------------------------------------------------
	.globl _super, _n_open, _newfile, _isdevice, _setftime, _wr_inode
	.globl _i_deref, _lastname, _ugetc, _getperm
	.globl __mknod, __access

; arg_t _mknod(void): name u_argn, mode u_argn1, dev u_argn2
__mknod::
	call ___sdcc_enter_ix
	push af
	push af				; -4/-3 = parent
	ld hl, #0
	ld (_udata + 0x0c), hl
	call _super
	bit 0, l
	jr nz, mk_1
	ld a, (_udata + 0x15)		; mode high byte
	and #0xf0
	cp #0x10			; F_PIPE
	jr z, mk_1
	ld hl, #1			; EPERM
mk_err:
	ld (_udata + 0x0c), hl
mk_fail:
	ld hl, #0xffff
mk_ret:
	jp	ixh_leave
mk_1:
	ld hl, #0
	add hl, sp
	ex de, hl
	ld hl, (_udata + 0x12)
	push de
	push hl
	call _n_open
	pop af
	pop af
	ld a, h
	or l
	jr z, mk_2
	ld de, #0x11			; EEXIST
	ld (_udata + 0x0c), de
	call	ixh_p1_i_deref
	call	ixh_lh_m4
	call	ixh_p1_i_deref
	jr mk_fail
mk_2:
	ld a, -3 (ix)
	or -4 (ix)
	jr nz, mk_3
	ld hl, #2			; ENOENT
	jr mk_err
mk_3:
	ld hl, #_lastname
	push hl
	call	ixh_lh_m4
	push hl
	call _newfile
	pop af
	pop af
	ld c, l
	ld b, h
	ld a, h
	or l
	jp z, mk_fail
	ld iy, #6			; i_mode
	add iy, bc
	ld hl, (_udata + 0x14)
	ld de, (_udata + 0x6d)		; umask
	ld a, e
	cpl
	and l
	ld l, a
	ld a, d
	cpl
	and h
	ld h, a
	ld 0 (iy), l
	ld 1 (iy), h
	push bc
	push bc
	call _isdevice
	pop af
	pop bc
	ld de, #0
	bit 0, l
	jr z, mk_4
	ld de, (_udata + 0x16)		; dev
mk_4:
	ld hl, #0x1e			; i_addr[0]
	add hl, bc
	ld (hl), e
	inc hl
	ld (hl), d
	push bc
	ld a, #7			; A_TIME|M_TIME|C_TIME
	push af
	inc sp
	push bc
	call _setftime
	pop af
	inc sp
	pop bc
	push bc
	push bc
	call _wr_inode
	pop af
	call _i_deref
	pop af
	ld hl, #0
	jp mk_ret

; arg_t _access(void): path u_argn, mode u_argn1
__access::
	call ___sdcc_enter_ix
	push af
	push af
	push af				; -2/-1 egid, -4/-3 euid, -6/-5 ino
	ld a, (_udata + 0x14)
	and #7
	jr z, ac_1
	ld hl, (_udata + 0x12)
	push hl
	call _ugetc
	pop af
	ld a, h
	or l
	jr nz, ac_1
	ld hl, #2			; ENOENT
	ld (_udata + 0x0c), hl
	ld hl, #0xffff
	jr ac_ret
ac_1:
	ld hl, (_udata + 0x71)
	ld -4 (ix), l
	ld -3 (ix), h
	ld hl, (_udata + 0x73)
	ld -2 (ix), l
	ld -1 (ix), h
	ld hl, (_udata + 0)
	ld de, #5			; p_uid
	add hl, de
	ld e, (hl)
	inc hl
	ld d, (hl)
	ld (_udata + 0x71), de
	ld de, (_udata + 0x6f)		; u_gid
	ld (_udata + 0x73), de
	ld hl, (_udata + 0x12)
	ld de, #0
	push de
	push hl
	call _n_open
	pop af
	pop af
	ld bc, #0xffff
	ld a, h
	or l
	jr z, ac_3
	ld -6 (ix), l
	ld -5 (ix), h
	push hl
	call _getperm
	pop af
	ld a, l
	cpl
	ld l, a
	ld a, (_udata + 0x14)
	and #7
	and l
	ld bc, #0
	jr z, ac_2
	ld hl, #0x0d			; EACCES
	ld (_udata + 0x0c), hl
	ld bc, #0xffff
ac_2:
	push bc
	call	ixh_lh_m6
	call	ixh_p1_i_deref
	pop bc
ac_3:
	call	ixh_lh_m4
	ld (_udata + 0x71), hl
	call	ixh_lh_m2
	ld (_udata + 0x73), hl
	ld h, b
	ld l, c
ac_ret:
	jp	ixh_leave

; ---------------------------------------------------------------
; M78: utime, statfs
; ---------------------------------------------------------------
	.globl _valaddr_r, _uget, _fs_tab_get, _uputw
	.globl __utime, __statfs

; arg_t _utime(void): file u_argn, buf u_argn1.  t[2] (16 B) at ix-22, ino at ix-6
__utime::
	call ___sdcc_enter_ix
	ld hl, #-22
	add hl, sp
	ld sp, hl
	ld hl, (_udata + 0x12)
	ld de, #0
	push de
	push hl
	call _n_open
	pop af
	pop af
	ld -6 (ix), l
	ld -5 (ix), h
	ld a, h
	or l
	jr nz, ut_1
	ld hl, #0xffff
	jp ut_ret
ut_1:
	ld de, #0x49			; c_flags
	add hl, de
	bit 6, (hl)			; CRDONLY
	jr z, ut_2
	ld hl, #0x1e			; EROFS
	ld (_udata + 0x0c), hl
	jp ut_out2
ut_2:
	ld hl, (_udata + 0x14)
	ld a, h
	or l
	jr z, ut_now
	call	ixh_lh_m6
	ld de, #0x0a			; i_uid
	add hl, de
	ld e, (hl)
	inc hl
	ld d, (hl)
	ld hl, (_udata + 0x71)		; u_euid
	or a
	sbc hl, de
	jr z, ut_3
	call _esuper
	bit 0, l
	jp nz, ut_out
ut_3:
	ld hl, (_udata + 0x14)
	ld bc, #0x10
	push bc
	push hl
	call _valaddr_r
	pop af
	pop af
	ld a, h
	or l
	jp z, ut_out2
	ld hl, #0
	add hl, sp
	ex de, hl
	ld hl, (_udata + 0x14)
	ld bc, #0x10
	push bc
	push de
	push hl
	call _uget
	pop af
	pop af
	pop af
	jr ut_set
ut_now:
	call	ixh_lh_m6
	push hl
	call _getperm
	pop af
	bit 1, l			; OTH_WR
	jp z, ut_out
	ld hl, #0
	add hl, sp
	push hl
	call _rdtime
	pop de				; DE = &t[0]
	ld hl, #8
	add hl, de
	ex de, hl			; HL = t[0], DE = t[1]
	ld bc, #8
	ldir
ut_set:
	call	ixh_lh_m6
	ld de, #0x12			; i_atime, followed by i_mtime
	add hl, de
	ex de, hl
	push ix
	pop hl
	ld bc, #-22
	add hl, bc			; HL = t
	ld bc, #4
	ldir
	ld bc, #4
	add hl, bc			; HL = t[1]
	ld bc, #4
	ldir
	ld a, #4			; C_TIME
	push af
	inc sp
	call	ixh_lh_m6
	push hl
	call _setftime
	pop af
	inc sp
	call	ixh_lh_m6
	call	ixh_p1_i_deref
	ld hl, #0
	jp ut_ret
ut_out:
	ld hl, #1			; EPERM
	ld (_udata + 0x0c), hl
ut_out2:
	call	ixh_lh_m6
	call	ixh_p1_i_deref
	ld hl, #0xffff
ut_ret:
	jp	ixh_leave

; arg_t _statfs(void): path u_argn, buf u_argn1
__statfs::
	ld hl, (_udata + 0x12)
	ld de, #0
	push de
	push hl
	call _n_open
	pop af
	pop af
	ld a, h
	or l
	jr nz, sf_1
	ld hl, #0xffff
	ret
sf_1:
	push hl				; ino
	inc hl
	inc hl
	ld e, (hl)			; c_dev
	inc hl
	ld d, (hl)
	push de
	call _fs_tab_get
	pop af
	ex de, hl			; DE = m
	pop bc				; ino
	push de
	push bc
	call _i_deref
	pop af
	pop de
	ld hl, (_udata + 0x14)
	ld bc, #0xdd			; sizeof(struct filesys)
	add hl, bc
	ld b, h
	ld c, l
	ld l, e
	ld h, d
	inc hl
	inc hl
	ld a, (hl)			; m_flags
	inc hl
	ld h, (hl)
	ld l, a
	push de
	push bc
	push hl
	call _uputw
	pop af
	pop af
	pop de
	ld bc, (_udata + 0x14)
	ld hl, #6
	add hl, de
	ld de, #0xdd
	push de
	push bc
	push hl
	call _uput
	pop af
	pop af
	pop af
	ret

; ---------------------------------------------------------------
; M79: pipe
; ---------------------------------------------------------------
	.globl _oft_alloc, _oft_deref, _i_open, _root_dev, _uputw
	.globl __pipe

; arg_t _pipe(void): locals -1 u1, -2 u2, -3 oft1, -4 oft2, -6/-5 ino
__pipe::
	call ___sdcc_enter_ix
	push af
	push af
	push af
	call _uf_alloc
	ld -1 (ix), l
	inc l
	jp z, pp_fail
	call _oft_alloc
	ld -3 (ix), l
	inc l
	jp z, pp_fail
	ld a, -1 (ix)
	call pp_slot
	ld a, -3 (ix)
	ld (hl), a
	call _uf_alloc
	ld -2 (ix), l
	inc l
	jp z, pp_ng2
	call _oft_alloc
	ld -4 (ix), l
	inc l
	jp z, pp_ng2
	ld hl, #0
	push hl
	ld hl, (_root_dev)
	push hl
	call _i_open
	pop af
	pop af
	ld a, h
	or l
	jr nz, pp_1
	ld a, -4 (ix)
	push af
	inc sp
	call _oft_deref
	inc sp
	jp pp_ng2
pp_1:
	ld -6 (ix), l
	ld -5 (ix), h
	push hl
	pop iy
	bit 6, 73 (iy)			; CRDONLY
	jr z, pp_2
	ld hl, #0x1e			; EROFS
	ld (_udata + 0x0c), hl
	jp pp_ng3
pp_2:
	ld a, -2 (ix)
	call pp_slot
	ld a, -4 (ix)
	ld (hl), a
	ld a, -3 (ix)
	ld c, #0			; O_RDONLY
	call pp_fill
	ld a, -4 (ix)
	ld c, #1			; O_WRONLY
	call pp_fill
	inc 0x46 (iy)			; c_refs
	ld 6 (iy), #0xff		; i_mode = F_PIPE | 0777
	ld 7 (iy), #0x11
	xor a
	ld 8 (iy), a			; i_nlink = 0
	ld 9 (iy), a
	inc 0x47 (iy)			; c_readers
	inc 0x48 (iy)			; c_writers
	ld hl, (_udata + 0x12)
	ld c, -1 (ix)
	ld b, #0
	push hl
	push bc
	call _uputw
	pop af
	pop af
	ld hl, (_udata + 0x12)
	inc hl
	inc hl
	ld c, -2 (ix)
	ld b, #0
	push hl
	push bc
	call _uputw
	pop af
	pop af
	ld hl, #0
	jr pp_ret
pp_ng3:
	call	ixh_lh_m6
	call	ixh_p1_i_deref
pp_ng2:
	ld a, -3 (ix)
	push af
	inc sp
	call _oft_deref
	inc sp
	ld a, -1 (ix)
	call pp_slot
	ld (hl), #0xff			; NO_FILE
pp_fail:
	ld hl, #0xffff
pp_ret:
	jp	ixh_leave

; A = index -> HL = &udata.u_files[A]
pp_slot:
	ld e, a
	ld d, #0
	ld hl, #_udata + 0x7d
	add hl, de
	ret

; A = oft index, C = access; ino at -6/-5 (ix): of_tab[A] = {0, ino, access}
pp_fill:
	ld l, a
	call	ixh_oft
	xor a
	ld (hl), a
	inc hl
	ld (hl), a
	inc hl
	ld (hl), a
	inc hl
	ld (hl), a
	inc hl
	ld a, -6 (ix)
	ld (hl), a
	inc hl
	ld a, -5 (ix)
	ld (hl), a
	inc hl
	ld (hl), c
	ret

; ---------------------------------------------------------------
; M79: umount, do_umount
; ---------------------------------------------------------------
	.globl _fs_tab_get, _i_tab, _validdev, _getmode
	.globl _do_umount, __umount

; int do_umount(uint16_t dev)  (dev at 4(ix)); flags = u_argn1
; struct mount: m_dev +0, m_flags +2, m_mntpt +4, m_fs +6 (s_fmod at +0xd8)
_do_umount::
	call ___sdcc_enter_ix
	call	ixh_lh_p4
	push hl
	call _fs_tab_get
	pop af
	ld c, l
	ld b, h				; BC = mnt
	ld a, h
	or l
	jr nz, du_1
	ld hl, #0x16			; EINVAL
	ld (_udata + 0x0c), hl
du_fail:
	ld hl, #0xffff
du_ret:
	pop ix
	ret
du_1:
	ld a, (_udata + 0x14)
	and #0x81			; MS_RDONLY|MS_REMOUNT
	cp #0x81
	jr nz, du_2
	ld de, #_i_tab
du_l1:
	ld a, e
	sub #<(_i_tab + 0x5dc)
	ld a, d
	sbc #>(_i_tab + 0x5dc)
	jr nc, du_2
	push de
	pop iy
	ld a, 70 (iy)			; c_refs
	or a
	jr z, du_n1
	ld a, 2 (iy)			; c_dev
	cp 4 (ix)
	jr nz, du_n1
	ld a, 3 (iy)
	cp 5 (ix)
	jr nz, du_n1
	push bc
	push de
	push de
	call _isdevice
	pop af
	pop de
	pop bc
	bit 0, l
	jr nz, du_n1
	push de
	pop iy
	ld a, 72 (iy)			; c_writers
	or a
	jr nz, du_busy
	ld a, 8 (iy)			; i_nlink
	or 9 (iy)
	jr nz, du_n1
du_busy:
	ld hl, #0x10			; EBUSY
	ld (_udata + 0x0c), hl
	jp du_fail
du_n1:
	ld hl, #0x4b
	add hl, de
	ex de, hl
	jr du_l1
du_2:
	ld de, #_i_tab
du_l2:
	ld a, e
	sub #<(_i_tab + 0x5dc)
	ld a, d
	sbc #>(_i_tab + 0x5dc)
	jr nc, du_3
	push de
	pop iy
	ld a, 2 (iy)
	cp 4 (ix)
	jr nz, du_n2
	ld a, 3 (iy)
	cp 5 (ix)
	jr nz, du_n2
	ld a, (_udata + 0x14)
	and #0x80			; MS_REMOUNT
	jr z, du_nr
	res 6, 73 (iy)			; ~CRDONLY
	ld a, (_udata + 0x14)
	rrca				; MS_RDONLY -> carry
	jr nc, du_n2
	set 6, 73 (iy)
	jr du_n2
du_nr:
	ld a, 70 (iy)
	or a
	jr z, du_n2
	ld hl, #0x10			; EBUSY
	ld (_udata + 0x0c), hl
	jp du_fail
du_n2:
	ld hl, #0x4b
	add hl, de
	ex de, hl
	jr du_l2
du_3:
	ld a, (_udata + 0x14)
	and #0x80
	jr nz, du_rm
	ld hl, #0xd8			; s_fmod = FMOD_GO_CLEAN
	add hl, bc
	ld (hl), #0
	push bc
	call _sync
	pop bc
	ld hl, #4
	add hl, bc
	ld e, (hl)
	inc hl
	ld d, (hl)
	push bc
	push de
	call _i_deref
	pop af
	pop bc
	ld a, #0xff			; m_dev = NO_DEVICE
	ld (bc), a
	inc bc
	ld (bc), a
	ld hl, #0
	jp du_ret
du_rm:
	push bc
	call _sync
	pop bc
	ld hl, #2
	add hl, bc
	ld a, (hl)
	and #0xfc
	ld e, a
	ld a, (_udata + 0x14)
	and #3
	or e
	ld (hl), a
	rrca
	jr nc, du_ok
	ld hl, #0xd8
	add hl, bc
	ld (hl), #0
du_ok:
	ld hl, #0
	jp du_ret

; arg_t _umount(void)
__umount::
	call _esuper
	bit 0, l
	jr z, um_1
	ld hl, #0xffff
	ret
um_1:
	ld hl, (_udata + 0x12)
	ld de, #0
	push de
	push hl
	call _n_open
	pop af
	pop af
	ld a, h
	or l
	jr nz, um_2
	ld hl, #0xffff
	ret
um_2:
	push hl
	call	ixh_p1_getmode
	pop de				; DE = ino
	ld a, l
	cp #0x60			; MODE_R(F_BDEV)
	jr z, um_3
	ld hl, #0x0f			; ENOTBLK
	ld (_udata + 0x0c), hl
	ld bc, #0xffff
	jr um_end
um_3:
	ld hl, #0x1e			; i_addr[0]
	add hl, de
	ld c, (hl)
	inc hl
	ld b, (hl)
	push de
	push bc
	push bc
	call _validdev
	pop af
	pop bc
	pop de
	bit 0, l
	jr nz, um_4
	ld hl, #6			; ENXIO
	ld (_udata + 0x0c), hl
	ld bc, #0xffff
	jr um_end
um_4:
	push de
	push bc
	call _do_umount
	pop af
	ld c, l
	ld b, h
	pop de
um_end:
	push bc
	push de
	call _i_deref
	pop af
	pop hl
	ret

; ---------------------------------------------------------------
; M80: mount
; ---------------------------------------------------------------
	.globl _d_open, _fmount, __mount

; arg_t _mount(void): spec u_argn, dir u_argn1, flags u_argn2
; locals: -2/-1 dino, -4/-3 sino
__mount::
	call ___sdcc_enter_ix
	push af
	push af
	call _esuper
	bit 0, l
	jr z, mt_1
mt_fail:
	ld hl, #0xffff
mt_ret:
	jp	ixh_leave
mt_1:
	ld hl, (_udata + 0x12)
	ld de, #0
	push de
	push hl
	call _n_open
	pop af
	pop af
	ld -4 (ix), l
	ld -3 (ix), h
	ld a, h
	or l
	jr z, mt_fail
	ld hl, (_udata + 0x14)
	ld de, #0
	push de
	push hl
	call _n_open
	pop af
	pop af
	ld -2 (ix), l
	ld -1 (ix), h
	ld a, h
	or l
	jr nz, mt_2
	call	ixh_lh_m4
	call	ixh_p1_i_deref
	jr mt_fail
mt_2:
	call	ixh_lh_m4
	call	ixh_p1_getmode
	ld a, l
	cp #0x60			; MODE_R(F_BDEV)
	jr z, mt_3
	ld hl, #0x0f			; ENOTBLK
mt_err:
	ld (_udata + 0x0c), hl
mt_ng:
	call mt_deref
	jp mt_fail
mt_3:
	call	ixh_lh_m2
	call	ixh_p1_getmode
	ld a, l
	cp #0x40			; MODE_R(F_DIR)
	jr z, mt_4
	ld hl, #0x14			; ENOTDIR
	jr mt_err
mt_4:
	call	ixh_lh_m4
	ld de, #0x1e			; i_addr[0]
	add hl, de
	ld e, (hl)
	inc hl
	ld d, (hl)			; DE = dev
	push de
	push de
	call _validdev
	pop af
	pop de
	bit 0, l
	jr z, mt_nx
	ld a, (_udata + 0x16)
	rrca				; MS_RDONLY -> carry
	ld a, #2			; O_RDWR
	jr nc, mt_5
	xor a				; O_RDONLY
mt_5:
	push de
	push af
	inc sp
	push de
	call _d_open
	pop af
	inc sp
	pop de
	ld a, h
	or l
	jr z, mt_6
mt_nx:
	ld hl, #6			; ENXIO
	jr mt_err
mt_6:
	push de
	push de
	call _fs_tab_get
	pop af
	pop de
	ld a, h
	or l
	jr nz, mt_busy
	call	ixh_lh_m2
	push hl
	pop iy
	ld a, 70 (iy)			; c_refs
	dec a
	jr nz, mt_busy
	ld a, 4 (iy)			; c_num == ROOTINODE
	dec a
	or 5 (iy)
	jr nz, mt_7
mt_busy:
	ld hl, #0x10			; EBUSY
	jr mt_err
mt_7:
	push de
	call _sync
	pop de
	ld hl, (_udata + 0x16)
	push hl
	call	ixh_lh_m2
	push hl
	push de
	call _fmount
	pop af
	pop af
	pop af
	ld a, h
	or l
	jp z, mt_ng
	call mt_deref
	ld hl, #0
	jp mt_ret

mt_deref:
	call	ixh_lh_m2
	call	ixh_p1_i_deref
	call	ixh_lh_m4
	call	ixh_p1_i_deref
	ret

; ---------------------------------------------------------------
; M81: mkdir, rmdir
; ---------------------------------------------------------------
	.globl _ch_link, _emptydir, _f_trunc, _kputs, _kprintf
	.globl __mkdir, __rmdir

md_nul:
	.db 0
md_dot:
	.asciz "."
md_dotdot:
	.asciz ".."
md_msg:
	.asciz "_mkdir: bad rec\n"
rd_msg:
	.asciz "_rmdir: bad nlink\n"

; arg_t _mkdir(void): name u_argn, mode u_argn1
; locals: -6/-5 parent (&parent = SP after 3 pushes), -2/-1 ino
__mkdir::
	call ___sdcc_enter_ix
	push af
	push af
	push af
	ld hl, #0
	add hl, sp
	ex de, hl
	ld hl, (_udata + 0x12)
	push de
	push hl
	call _n_open
	pop af
	pop af
	ld a, h
	or l
	jr z, md_1
	ld de, #0x11			; EEXIST
	ld (_udata + 0x0c), de
	call	ixh_p1_i_deref
	jr md_ng2
md_1:
	ld a, -5 (ix)
	or -6 (ix)
	jr nz, md_2
	ld hl, #2			; ENOENT
	ld (_udata + 0x0c), hl
md_fail:
	ld hl, #0xffff
md_ret:
	jp	ixh_leave
md_ng2:
	call	ixh_lh_m6
	call	ixh_p1_i_deref
	jr md_fail
md_2:
	call	ixh_lh_m6
	push hl
	pop iy
	ld a, 8 (iy)			; i_nlink == 0xffff ?
	and 9 (iy)
	inc a
	jr nz, md_3
	ld hl, #0x1f			; EMLINK
	ld (_udata + 0x0c), hl
	jr md_ng2
md_3:
	inc 0x46 (iy)			; i_ref(parent)
	ld hl, #_lastname
	push hl
	call	ixh_lh_m6
	push hl
	call _newfile
	pop af
	pop af
	ld a, h
	or l
	jr z, md_ng2
	ld -2 (ix), l
	ld -1 (ix), h
	push hl
	pop iy
	ld 6 (iy), #0x80		; F_DIR | 0200
	ld 7 (iy), #0x40
	ld a, #7			; A_TIME|M_TIME|C_TIME
	push af
	inc sp
	push hl
	call _setftime
	pop af
	inc sp
	ld hl, #md_dot
	call	ixh_ed_m2
	call md_chl
	bit 0, l
	jr z, md_clean
	ld hl, #md_dotdot
	call	ixh_ed_m6
	call md_chl
	bit 0, l
	jr z, md_clean
	call	ixh_lh_m2
	push hl
	pop iy
	ld 8 (iy), #2			; i_nlink = 2
	ld 9 (iy), #0
	call	ixh_lh_m6
	push hl
	pop iy
	ld l, 8 (iy)			; parent->i_nlink++
	ld h, 9 (iy)
	inc hl
	ld 8 (iy), l
	ld 9 (iy), h
	ld hl, (_udata + 0x14)		; mode & ~umask & MODE_MASK | F_DIR
	ld de, (_udata + 0x6d)
	ld a, e
	cpl
	and l
	ld l, a
	ld a, d
	cpl
	and h
	and #0x0f
	or #0x40
	ld h, a
	call	ixh_ed_m2
	push de
	pop iy
	ld 6 (iy), l
	ld 7 (iy), h
	call	ixh_lh_m6
	call	ixh_p1_i_deref
	call	ixh_lh_m2
	push hl
	call _wr_inode
	call _i_deref
	pop af
	ld hl, #0
	jp md_ret
md_clean:
	call	ixh_lh_m2
	push hl
	pop iy
	ld 8 (iy), #0
	ld 9 (iy), #0
	push hl
	call _wr_inode
	call _i_deref
	pop af
	ld hl, #0
	push hl
	ld hl, #md_nul
	push hl
	ld hl, #_lastname
	push hl
	call	ixh_lh_m6
	push hl
	call _ch_link
	pop af
	pop af
	pop af
	pop af
	bit 0, l
	jr nz, md_c2
	ld hl, #md_msg
	push hl
	call _kprintf
	pop af
md_c2:
	jp md_ng2

; ch_link(ino, "", HL = newname, DE = nindex) -> L
md_chl:
	push de
	push hl
	ld hl, #md_nul
	push hl
	call	ixh_lh_m2
	push hl
	call _ch_link
	pop af
	pop af
	pop af
	pop af
	ret

; arg_t _rmdir(void): path u_argn.  locals: -4/-3 parent (&parent = SP), -2/-1 ino
__rmdir::
	call ___sdcc_enter_ix
	push af
	push af
	ld hl, #0
	add hl, sp
	ex de, hl
	ld hl, (_udata + 0x12)
	push de
	push hl
	call _n_open
	pop af
	pop af
	ld -2 (ix), l
	ld -1 (ix), h
	ld a, -3 (ix)
	or -4 (ix)
	jr z, rd_1
	ld a, h
	or l
	jr nz, rd_2
rd_1:
	ld hl, (_udata + 0x0c)
	ld a, h
	or l
	jr nz, rd_early
	ld hl, #2			; ENOENT
	ld (_udata + 0x0c), hl
rd_early:
	ld a, -3 (ix)
	or -4 (ix)
	jr z, rd_fail
	call	ixh_lh_m4
	call	ixh_p1_i_deref
rd_fail:
	ld hl, #0xffff
rd_ret:
	jp	ixh_leave
rd_2:
	ld a, (_lastname)
	cp #0x2e
	jr nz, rd_3
	ld a, (_lastname + 1)
	or a
	jr nz, rd_3
	ld hl, #0x16			; EINVAL
	ld (_udata + 0x0c), hl
	call	ixh_lh_m2
	call	ixh_p1_i_deref
	jr rd_early
rd_3:
	call	ixh_lh_m2
	push hl
	pop iy
	ld a, 4 (iy)			; c_num == ROOTINODE ?
	dec a
	or 5 (iy)
	jr nz, rd_4
	ld hl, #0x10			; EBUSY
rd_err:
	ld (_udata + 0x0c), hl
rd_ng:
	call	ixh_lh_m4
	call	ixh_p1_i_deref
	call	ixh_lh_m2
	call	ixh_p1_i_deref
	jr rd_fail
rd_4:
	call	ixh_lh_m2
	call	ixh_p1_getmode
	ld a, l
	cp #0x40			; MODE_R(F_DIR)
	jr z, rd_5
	ld hl, #0x14			; ENOTDIR
	jr rd_err
rd_5:
	call	ixh_lh_m2
	push hl
	pop iy
	ld a, 8 (iy)			; i_nlink != 2 ?
	sub #2
	or 9 (iy)
	jr nz, rd_ne
	push hl
	call _emptydir
	pop af
	bit 0, l
	jr nz, rd_6
rd_ne:
	ld hl, #0x24			; ENOTEMPTY
	jr rd_err
rd_6:
	call	ixh_lh_m4
	push hl
	call _getperm
	pop af
	bit 1, l			; OTH_WR
	jr z, rd_ng
	ld hl, #0
	push hl
	ld hl, #md_nul
	push hl
	ld hl, #_lastname
	push hl
	call	ixh_lh_m4
	push hl
	call _ch_link
	pop af
	pop af
	pop af
	pop af
	bit 0, l
	jr z, rd_ng
	call	ixh_lh_m2
	push hl
	pop iy
	ld 8 (iy), #0			; ino->i_nlink = 0
	ld 9 (iy), #0
	call	ixh_lh_m4
	push hl
	pop iy
	ld l, 8 (iy)			; parent->i_nlink--
	ld h, 9 (iy)
	ld a, h
	or l
	dec hl
	ld 8 (iy), l
	ld 9 (iy), h
	jr nz, rd_7
	inc hl				; was 0: bad nlink
	inc hl
	ld 8 (iy), l
	ld 9 (iy), h
	ld hl, #rd_msg
	call	ixh_p1_kputs
rd_7:
	ld a, #4			; C_TIME
	push af
	inc sp
	call	ixh_lh_m2
	push hl
	call _setftime
	pop af
	inc sp
	call	ixh_lh_m2
	push hl
	call _f_trunc
	pop af
	call	ixh_lh_m4
	call	ixh_p1_wr_inode
	call	ixh_lh_m2
	call	ixh_p1_wr_inode
	call	ixh_lh_m4
	call	ixh_p1_i_deref
	call	ixh_lh_m2
	call	ixh_p1_i_deref
	ld hl, #0
	jp rd_ret

; ---------------------------------------------------------------
; M82: link, rename
; ---------------------------------------------------------------
	.globl __link, __rename, _unlinki, _getperm, _esuper
	.globl __rename_srci_65536_290, __rename_srcp_65536_290, __rename_dsti_65536_290, __rename_dstp_65536_290

rn_msg:
	.asciz "WARNING: rename: unlink fail\n"

; arg_t _link(void): name1 u_argn, name2 u_argn1.  locals -2/-1 ino, -4/-3 parent2
__link::
	call ___sdcc_enter_ix
	push af
	push af
	ld hl, (_udata + 0x12)
	ld de, #0
	push de
	push hl
	call _n_open
	pop af
	pop af
	ld a, h
	or l
	jr nz, lk_1
lk_fail:
	ld hl, #0xffff
lk_ret:
	jp	ixh_leave
lk_1:
	ld -2 (ix), l
	ld -1 (ix), h
	call	ixh_p1_getmode
	ld a, l
	cp #0x40
	jr nz, lk_2
	ld hl, #0x15			; EISDIR
lk_err:
	ld (_udata + 0x0c), hl
lk_ng:
	call	ixh_lh_m2
	call	ixh_p1_i_deref
	jr lk_fail
lk_2:
	call	ixh_lh_m2
	ld de, #8			; i_nlink == 0xffff ?
	add hl, de
	ld a, (hl)
	inc hl
	and (hl)
	inc a
	jr nz, lk_3
	ld hl, #0x1f			; EMLINK
	jr lk_err
lk_3:
	ld hl, #0
	add hl, sp
	ex de, hl
	ld hl, (_udata + 0x14)
	push de
	push hl
	call _n_open
	pop af
	pop af
	ld a, h
	or l
	jr z, lk_4
	call	ixh_p1_i_deref
	call	ixh_lh_m4
	call	ixh_p1_i_deref
	ld hl, #0x11			; EEXIST
	jr lk_err
lk_4:
	ld a, -3 (ix)
	or -4 (ix)
	jr z, lk_ng
	call	ixh_lh_m2
	push hl
	pop iy
	call	ixh_lh_m4
	inc hl
	inc hl
	ld a, (hl)
	cp 2 (iy)
	jr nz, lk_xd
	inc hl
	ld a, (hl)
	cp 3 (iy)
	jr z, lk_5
lk_xd:
	call	ixh_lh_m4
	call	ixh_p1_i_deref
	ld hl, #0x12			; EXDEV
	jp lk_err
lk_5:
	call	ixh_lh_m2
	push hl
	ld hl, #_lastname
	push hl
	ld hl, #md_nul
	push hl
	call	ixh_lh_m4
	push hl
	call _ch_link
	pop af
	pop af
	pop af
	pop af
	bit 0, l
	jr nz, lk_6
	call	ixh_lh_m4
	call	ixh_p1_i_deref
	jp lk_ng
lk_6:
	call	ixh_lh_m2
	push hl
	pop iy
	ld l, 8 (iy)
	ld h, 9 (iy)
	inc hl
	ld 8 (iy), l
	ld 9 (iy), h
	call	ixh_lh_m2
	call	ixh_p1_wr_inode
	ld a, #4			; C_TIME
	push af
	inc sp
	call	ixh_lh_m2
	push hl
	call _setftime
	pop af
	inc sp
	call	ixh_lh_m4
	call	ixh_p1_i_deref
	call	ixh_lh_m2
	call	ixh_p1_i_deref
	ld hl, #0
	jp lk_ret

; arg_t _rename(void): src u_argn, dst u_argn1.  fname[31] at ix-35, -2/-1 ret, -4/-3 &fname
; state in __rename_srci_65536_290/__rename_srcp_65536_290/__rename_dsti_65536_290/__rename_dstp_65536_290 (srci, srcp, dsti, dstp), u_rename = udata+0x8d
__rename::
	call ___sdcc_enter_ix
	ld hl, #-35
	add hl, sp
	ld sp, hl
	ld hl, #__rename_srcp_65536_290
	push hl
	ld hl, (_udata + 0x12)
	push hl
	call _n_open
	pop af
	pop af
	ld (__rename_srci_65536_290), hl
	ld a, h
	or l
	jr nz, rn_1
	ld hl, (__rename_srcp_65536_290)
	ld a, h
	or l
	jr z, rn_f
	call	ixh_p1_i_deref
rn_f:
	ld hl, #0xffff
rn_ret:
	jp	ixh_leave
rn_1:
	ld hl, #0
	add hl, sp
	ld -4 (ix), l
	ld -3 (ix), h
	ex de, hl
	ld hl, #_lastname
	ld bc, #0x1f
	ldir
	ld hl, (__rename_srci_65536_290)
	ld (_udata + 0x8d), hl
	ld hl, #__rename_dstp_65536_290
	push hl
	ld hl, (_udata + 0x14)
	push hl
	call _n_open
	pop af
	pop af
	ld (__rename_dsti_65536_290), hl
	ld de, (__rename_srci_65536_290)
	or a
	sbc hl, de
	jr nz, rn_2
	ld -2 (ix), #0
	ld -1 (ix), #0
	jp rn_done
rn_2:
	ld -2 (ix), #0xff
	ld -1 (ix), #0xff
	ld hl, (__rename_dstp_65536_290)
	ld a, h
	or l
	jp z, rn_done
	ld hl, (__rename_srci_65536_290)
	inc hl
	inc hl
	ld c, (hl)
	inc hl
	ld b, (hl)
	ld hl, (__rename_dstp_65536_290)
	inc hl
	inc hl
	ld e, (hl)
	inc hl
	ld d, (hl)
	ld a, c
	cp e
	jr nz, rn_xd
	ld a, b
	cp d
	jr z, rn_3
rn_xd:
	ld hl, #0x12			; EXDEV
rn_err:
	ld (_udata + 0x0c), hl
rn_ng:
	ld hl, (__rename_dsti_65536_290)
	ld a, h
	or l
	jr z, rn_ng2
	call	ixh_p1_i_deref
rn_ng2:
	ld hl, (__rename_dstp_65536_290)
	call	ixh_p1_i_deref
rn_done:
	ld hl, (__rename_srci_65536_290)
	call	ixh_p1_i_deref
	ld hl, (__rename_srcp_65536_290)
	call	ixh_p1_i_deref
	call	ixh_lh_m2
	jp rn_ret
rn_3:
	ld hl, (__rename_srci_65536_290)
	call	ixh_p1_getmode
	ld a, l
	cp #0x40
	jr nz, rn_4
	ld hl, (__rename_dsti_65536_290)
	ld a, h
	or l
	jr z, rn_3b
	ld hl, #0x11			; EEXIST
	jr rn_err
rn_3b:
	call	ixh_lh_m4
	ld a, (hl)
	cp #0x2e
	jr nz, rn_4
	inc hl
	ld a, (hl)
	or a
	jr z, rn_inv
	cp #0x2e
	jr nz, rn_4
	inc hl
	ld a, (hl)
	or a
	jr nz, rn_4
rn_inv:
	ld hl, #0x16			; EINVAL
	jr rn_err
rn_4:
	ld hl, (_udata + 0x8d)
	ld a, h
	or l
	jr nz, rn_5
	ld hl, #0x16
	jr rn_err
rn_5:
	ld hl, (__rename_srcp_65536_290)
	push hl
	call _getperm
	pop af
	bit 1, l
	jr nz, rn_6
	call _esuper
	bit 0, l
	jr z, rn_6
	ld hl, #0x0d			; EACCES
	jp rn_err
rn_6:
	ld hl, (__rename_dsti_65536_290)
	ld a, h
	or l
	jr z, rn_9
	call	ixh_p1_getmode
	ld a, l
	cp #0x40
	jr nz, rn_7
	ld hl, #0x15			; EISDIR
	jp rn_err
rn_7:
	ld hl, #_lastname
	push hl
	ld hl, (__rename_dstp_65536_290)
	push hl
	ld hl, (__rename_dsti_65536_290)
	push hl
	call _unlinki
	pop af
	pop af
	pop af
	inc l
	jr nz, rn_8
	inc h
	jp z, rn_ng
rn_8:
	ld hl, (__rename_dsti_65536_290)
	call	ixh_p1_i_deref
rn_9:
	ld hl, (__rename_srci_65536_290)
	push hl
	ld hl, #_lastname
	push hl
	ld hl, #md_nul
	push hl
	ld hl, (__rename_dstp_65536_290)
	push hl
	call _ch_link
	pop af
	pop af
	pop af
	pop af
	bit 0, l
	jp z, rn_ng2
	ld hl, (__rename_srcp_65536_290)
	ld de, (__rename_dstp_65536_290)
	or a
	sbc hl, de
	jr z, rn_10
	ld hl, (__rename_srci_65536_290)
	call	ixh_p1_getmode
	ld a, l
	cp #0x40
	jr nz, rn_10
	ld hl, (__rename_dstp_65536_290)
	push hl
	ld hl, #md_dotdot
	push hl
	push hl
	ld hl, (__rename_srci_65536_290)
	push hl
	call _ch_link
	pop af
	pop af
	pop af
	pop af
	bit 0, l
	jr nz, rn_11
	ld hl, #0
	push hl
	ld hl, #md_nul
	push hl
	ld hl, #_lastname
	push hl
	ld hl, (__rename_dstp_65536_290)
	push hl
	call _ch_link
	pop af
	pop af
	pop af
	pop af
	jp rn_ng2
rn_11:
	ld hl, (__rename_dstp_65536_290)
	ld de, #8
	add hl, de
	inc (hl)
	jr nz, rn_12
	inc hl
	inc (hl)
rn_12:
	ld hl, (__rename_srcp_65536_290)
	ld de, #8
	add hl, de
	ld a, (hl)
	sub #1
	ld (hl), a
	inc hl
	ld a, (hl)
	sbc #0
	ld (hl), a
rn_10:
	call	ixh_cb_m4
	ld hl, #0
	push hl
	ld hl, #md_nul
	push hl
	push bc
	ld hl, (__rename_srcp_65536_290)
	push hl
	call _ch_link
	pop af
	pop af
	pop af
	pop af
	bit 0, l
	jr nz, rn_13
	ld hl, #rn_msg
	call	ixh_p1_kputs
	jp rn_ng2
rn_13:
	ld hl, (__rename_dstp_65536_290)
	call	ixh_p1_wr_inode
	ld hl, (__rename_srcp_65536_290)
	call	ixh_p1_wr_inode
	call _sync
	ld -2 (ix), #0
	ld -1 (ix), #0
	jp rn_ng2

; ---------------------------------------------------------------
; M83: fcntl, ftruncate
; ---------------------------------------------------------------
	.globl _getinode, _uf_alloc_n, _f_trunc_blocks
	.globl __fcntl, __ftruncate

; arg_t _fcntl(void): fd u_argn, request u_argn1, data u_argn2
; (F_SETFD / F_DUPFD keep the upstream semantics, see progress doc)
__fcntl::
	call ___sdcc_enter_ix
	call	ixh_getinode_argn
	ld a, h
	or l
	jr nz, fc_1
	ld hl, #0xffff
fc_ret:
	pop ix
	ret
fc_1:
	ld a, (_udata + 0x12)
	ld e, a
	ld d, #0
	ld hl, #_udata + 0x7d
	add hl, de
	ld l, (hl)
	ld h, #0
	add hl, hl
	add hl, hl
	add hl, hl
	ld de, #_of_tab + 6		; &o_access
	add hl, de
	push hl
	pop iy
	ld hl, (_udata + 0x14)		; request
	ld a, h
	or a
	jr nz, fc_def
	ld a, l
	or a
	jr z, fc_getfl
	dec a
	jr z, fc_setfl
	dec a
	jr z, fc_getfd
	dec a
	jr z, fc_setfd
	dec a
	jr z, fc_dupfd
fc_def:
	ld hl, #0x16			; EINVAL
	ld (_udata + 0x0c), hl
	ld hl, #0xffff
	jr fc_ret
fc_getfl:
	ld l, 0 (iy)
	ld h, #0
	jr fc_ret
fc_setfl:
	ld a, 0 (iy)
	and #0xeb			; ~(O_APPEND|O_NDELAY)
	ld c, a
	ld a, (_udata + 0x16)
	and #0x14
	or c
	ld 0 (iy), a
	ld hl, #0
	jr fc_ret
fc_bit:					; HL = 1 << fd
	ld a, (_udata + 0x12)
	ld hl, #1
	or a
	ret z
fc_b1:
	add hl, hl
	dec a
	jr nz, fc_b1
	ret
fc_getfd:
	call fc_bit
	ld de, (_udata + 0x87)		; u_cloexec
	ld a, l
	and e
	ld l, a
	ld a, h
	and d
	or l
	ld hl, #0
	jr z, fc_ret
	ld hl, #0x1000			; O_CLOEXEC
	jr fc_ret
fc_setfd:
	call fc_bit
	ld de, (_udata + 0x87)
	ld a, (_udata + 0x17)
	bit 4, a			; data & O_CLOEXEC
	jr z, fc_sf2
	ld a, e
	or l
	ld e, a
	ld a, d
	or h
	ld d, a
	jr fc_sf3
fc_sf2:
	ld a, e
	and l
	ld e, a
	ld a, d
	and h
	ld d, a
fc_sf3:
	ld (_udata + 0x87), de
	ld hl, #0
	jp fc_ret
fc_dupfd:
	ld a, (_udata + 0x16)
	push af
	inc sp
	call _uf_alloc_n
	inc sp
	inc l
	jr nz, fc_d1
	ld hl, #0xffff
	jp fc_ret
fc_d1:
	dec l
	ld h, #0
	ld de, #_udata + 0x7d
	add hl, de
	ex de, hl			; DE = &u_files[newd]
	ld a, (_udata + 0x12)
	ld l, a
	ld h, #0
	ld bc, #_udata + 0x7d
	add hl, bc
	ld a, (hl)			; u_files[fd]
	ld (de), a
	ld l, a
	ld h, #0
	add hl, hl
	add hl, hl
	add hl, hl
	ld bc, #_of_tab + 7		; o_refs
	add hl, bc
	inc (hl)
	ld hl, #0
	jp fc_ret

; arg_t _ftruncate(void): file u_argn, offset(ptr to 32 bit) u_argn1
; locals: n at -12..-9, ino -8/-7, old size -4..-1
__ftruncate::
	call ___sdcc_enter_ix
	ld hl, #-12
	add hl, sp
	ld sp, hl
	ld hl, #0
	add hl, sp
	ld c, l
	ld b, h
	ld hl, (_udata + 0x14)
	ld de, #4
	push de
	push bc
	push hl
	call _uget
	pop af
	pop af
	pop af
	ld a, h
	or l
	jr z, ft_1
ft_fail:
	ld hl, #0xffff
ft_ret:
	jp	ixh_leave
ft_1:
	call	ixh_getinode_argn
	ld -8 (ix), l
	ld -7 (ix), h
	ld a, h
	or l
	jr z, ft_fail
	ld hl, (_udata + 0x12)
	ld de, #_udata + 0x7d
	add hl, de
	ld l, (hl)
	call	ixh_oft
	push hl
	pop iy
	ld a, -9 (ix)			; n < 0 or n too large
	and #0xfe
	jr nz, ft_inv
	ld a, 6 (iy)			; O_RDONLY ?
	and #3
	jr z, ft_inv
	call	ixh_lh_m8
	call	ixh_p1_getmode
	ld a, l
	cp #0x80			; MODE_R(F_REG)
	jr z, ft_3
ft_inv:
	ld hl, #0x16			; EINVAL
	ld (_udata + 0x0c), hl
	jr ft_fail
ft_3:
	call	ixh_lh_m8
	ld de, #0x0e			; i_size
	add hl, de
	ld c, (hl)
	inc hl
	ld b, (hl)
	inc hl
	ld e, (hl)
	inc hl
	ld d, (hl)
	ld -4 (ix), c
	ld -3 (ix), b
	ld -2 (ix), e
	ld -1 (ix), d
	ld c, -12 (ix)
	ld b, -11 (ix)
	ld e, -10 (ix)
	ld d, -9 (ix)
	ld a, -4 (ix)
	sub c
	jr nz, ft_ne
	ld a, -3 (ix)
	sub b
	jr nz, ft_ne
	ld a, -2 (ix)
	sub e
	jr nz, ft_ne
	ld a, -1 (ix)
	sub d
	jr nz, ft_ne
	ld hl, #0
	jp ft_ret
ft_ne:
	ld a, c
	sub -4 (ix)
	ld a, b
	sbc a, -3 (ix)
	ld a, e
	sbc a, -2 (ix)
	ld a, d
	sbc a, -1 (ix)
	jr nc, ft_4			; n >= size: just set the size
	ld a, -12 (ix)			; (n + 511) >> 9
	add a, #0xff
	ld c, a
	ld a, -11 (ix)
	adc a, #1
	ld b, a
	ld a, -10 (ix)
	adc a, #0
	ld e, a
	ld a, -9 (ix)
	adc a, #0
	ld d, a
	ld a, #9
ft_sh:
	sra d
	rr e
	rr b
	rr c
	dec a
	jr nz, ft_sh
	push bc
	call	ixh_lh_m8
	push hl
	call _f_trunc_blocks
	pop af
	pop af
ft_4:
	call	ixh_lh_m8
	ld de, #0x0e
	add hl, de
	ex de, hl
	push ix
	pop hl
	ld bc, #-12
	add hl, bc
	ld bc, #4
	ldir
	ld a, #6			; M_TIME|C_TIME
	push af
	inc sp
	call	ixh_lh_m8
	push hl
	call _setftime
	pop af
	inc sp
	call	ixh_lh_m8
	call	ixh_p1_wr_inode
	ld hl, #0
	jp ft_ret

; ---------------------------------------------------------------
; M84: brk_extend, brk, sbrk
; ---------------------------------------------------------------
	.globl _brk_extend, __brk, __sbrk, _uzero

be_msg:
	.asciz "%d: out of memory by %d\n"

; int brk_extend(uaddr_t addr)  (addr at 4(ix))
_brk_extend::
	call ___sdcc_enter_ix
	ld hl, (_udata + 0x20)
	ld a, 4 (ix)
	sub l
	ld a, 5 (ix)
	sbc h
	jr nc, be_1
	ld hl, #0x16			; EINVAL
	jr be_ret
be_1:
	ld hl, (_udata + 8)
	ld c, l
	ld a, h
	add #0xfe
	ld b, a
	ld a, 4 (ix)
	sub c
	ld a, 5 (ix)
	sbc b
	jr c, be_ok
	ld a, 4 (ix)			; out of memory by (addr - limit)
	sub c
	ld c, a
	ld a, 5 (ix)
	sbc b
	ld b, a
	ld hl, (_udata + 0)
	inc hl
	inc hl
	inc hl
	ld e, (hl)			; p_pid
	inc hl
	ld d, (hl)
	push bc
	push de
	ld hl, #be_msg
	push hl
	call _kprintf
	pop af
	pop af
	pop af
	ld hl, #0x0c			; ENOMEM
	jr be_ret
be_ok:
	ld hl, #0
be_ret:
	pop ix
	ret

; arg_t _brk(void): addr u_argn
__brk::
	ld hl, (_udata + 0x12)
	push hl
	call _brk_extend
	pop af
	ld (_udata + 0x0c), hl
	ld a, h
	or l
	jr z, bk_1
	ld hl, #0xffff
	ret
bk_1:
	ld bc, (_udata + 0x12)
	ld de, (_udata + 0x1e)		; u_break
	ld a, e
	sub c
	ld a, d
	sbc b
	jr nc, bk_2
	ld (_udata + 0x1e), bc
	ld hl, (_udata + 0x12)
	or a
	sbc hl, de
	push hl
	push de
	call _uzero
	pop af
	pop af
bk_2:
	ld bc, (_udata + 0x12)
	ld (_udata + 0x1e), bc
	ld hl, #0
	ret

; arg_t _sbrk(void): incr u_argn
__sbrk::
	call ___sdcc_enter_ix
	push af
	ld de, (_udata + 0x12)
	ld hl, (_udata + 0x1e)
	ld c, l
	ld b, h				; BC = oldbrk
	add hl, de
	ld (_udata + 0x12), hl
	ld a, d
	or e
	jr z, sb_ok
	bit 7, d
	jr nz, sb_neg
	or a				; inc > 0: wrap if new < old
	sbc hl, bc
	jr c, sb_err
	jr sb_ok
sb_neg:
	ld hl, (_udata + 0x12)		; inc < 0: wrap if old < new
	ld a, c
	sub l
	ld a, b
	sbc h
	jr nc, sb_ok
sb_err:
	ld hl, #0x16			; EINVAL
	ld (_udata + 0x0c), hl
	ld hl, #0xffff
	jr sb_ret
sb_ok:
	push bc
	call __brk
	pop bc
	ld a, h
	or l
	jr z, sb_ok2
	ld hl, #0xffff
	jr sb_ret
sb_ok2:
	ld l, c
	ld h, b
sb_ret:
	pop af
	pop ix
	ret

; ---------------------------------------------------------------
; M84: waitpid
; ---------------------------------------------------------------
	.globl _chksigs, _ptab, _ptab_end, _valaddr_w, __waitpid

; arg_t _waitpid(void): pid u_argn, statloc u_argn1, options u_argn2
; locals: -2/-1 p, -5 found
; p_tab: status +0, pid +3, pptr +7, exitval +0x0b, utime +0x31, stime +0x35,
;        cutime +0x39, cstime +0x3d, pgrp +0x41, event +0x44
__waitpid::
	call ___sdcc_enter_ix
	ld hl, #-6
	add hl, sp
	ld sp, hl
	ld de, (_udata + 0x14)
	ld a, d
	or e
	jr z, wp_p0
	ld hl, #2
	push hl
	push de
	call _valaddr_w
	pop af
	pop af
	ld a, h
	or l
	jr nz, wp_p0
	ld hl, #0x0e			; EFAULT
	ld (_udata + 0x0c), hl
wp_fail:
	ld hl, #0xffff
wp_ret:
	jp	ixh_leave
wp_p0:
	ld hl, (_udata + 0x12)
	ld a, h
	or l
	jr nz, wp_loop
	ld hl, (_udata + 0)
	ld de, #0x41			; pid 0 -> -pgrp
	add hl, de
	ld c, (hl)
	inc hl
	ld b, (hl)
	xor a
	sub c
	ld c, a
	ld a, #0
	sbc b
	ld b, a
	ld (_udata + 0x12), bc
wp_loop:
	call _chksigs
	ld a, (_udata + 0x11)
	or a
	jr z, wp_1
	ld hl, #4			; EINTR
	ld (_udata + 0x0c), hl
	jr wp_fail
wp_1:
	xor a
	ld -5 (ix), a
	ld hl, #_ptab
	ld -2 (ix), l
	ld -1 (ix), h
wp_scan:
	call	ixh_ed_m2
	ld hl, (_ptab_end)
	ld a, e
	sub l
	ld a, d
	sbc h
	jp nc, wp_end
	ld a, (de)
	or a
	jp z, wp_next
	push de
	pop iy
	ld l, 7 (iy)			; p_pptr == current?
	ld h, 8 (iy)
	ld de, (_udata + 0)
	or a
	sbc hl, de
	jp nz, wp_next
	ld a, #1
	ld -5 (ix), a
	ld hl, (_udata + 0x12)		; pid == -1 ?
	ld a, h
	and l
	inc a
	jr z, wp_match
	ld e, 3 (iy)			; p_pid == pid ?
	ld d, 4 (iy)
	or a
	sbc hl, de
	jr z, wp_match
	ld hl, (_udata + 0x12)		; p_pgrp == -pid ?
	xor a
	sub l
	ld l, a
	ld a, #0
	sbc h
	ld h, a
	ld e, 0x41 (iy)
	ld d, 0x42 (iy)
	or a
	sbc hl, de
	jp nz, wp_next
wp_match:
	ld a, 0 (iy)
	cp #7				; P_ZOMBIE
	jr nz, wp_notz
	ld bc, (_udata + 0x14)
	ld a, b
	or c
	jr z, wz_1
	ld l, 0x0b (iy)			; p_exitval
	ld h, 0x0c (iy)
	push bc
	push hl
	call _uputw
	pop af
	pop af
wz_1:
	call	ixh_ed_m2
	push de
	pop iy
	ld c, 3 (iy)			; retval = p_pid
	ld b, 4 (iy)
	ld 0 (iy), #0			; P_EMPTY
	push bc
	ld a, #0x31			; utime -> parent cutime
	call wp_acc4
	ld a, #0x35			; stime -> parent cstime
	call wp_acc4
	pop hl
	jp wp_ret
wp_notz:
	ld a, 0x44 (iy)			; p_event && (options & WUNTRACED)
	or a
	jr z, wp_next
	ld a, (_udata + 0x16)
	and #2
	jr z, wp_next
	ld h, 0x44 (iy)
	ld l, #0xff			; _WSTOPPED
	ld 0x44 (iy), #0
	jp wp_ret
wp_next:
	call	ixh_lh_m2
	ld de, #0x4b
	add hl, de
	ld -2 (ix), l
	ld -1 (ix), h
	jp wp_scan
wp_end:
	ld a, -5 (ix)
	or a
	jr nz, wp_found
	ld hl, #0x0a			; ECHILD
	ld (_udata + 0x0c), hl
	jp wp_fail
wp_found:
	ld a, (_udata + 0x16)
	bit 0, a			; WNOHANG
	jr nz, wp_nohang
	ld hl, (_udata + 0)
	push hl
	call _psleep
	pop af
	jp wp_loop
wp_nohang:
	ld hl, #4			; EINTR
	ld (_udata + 0x0c), hl
	jp wp_fail

; parent(+A+8) += child(+A) + child(+A+8), 32 bit each; child = p at -2/-1 (ix)
wp_acc4:
	ld e, a
	ld d, #0
	call	ixh_lh_m2
	add hl, de
	push hl
	ld hl, (_udata + 0)
	ld a, e
	add a, #8
	ld e, a
	add hl, de
	ex de, hl			; DE = parent field
	pop hl				; HL = child field
	push hl
	push de
	call wp_add32
	pop de
	pop hl
	ld bc, #8
	add hl, bc
wp_add32:				; (DE) += (HL), 32 bit
	ld b, #4
	or a
wp_a1:
	ld a, (de)
	adc a, (hl)
	ld (de), a
	inc hl
	inc de
	djnz wp_a1
	ret

; ---------------------------------------------------------------
; M85: fork  (the saved irq state lives on the stack top, addressed
; via SP only: dofork returns in the child with a copied stack)
; ---------------------------------------------------------------
	.globl _ptab_alloc, _dofork, _pagemap_free, _nproc, _nready, ___hard_di, ___hard_irqrestore
	.globl __fork

__fork::
	call ___sdcc_enter_ix
	push af
	ld hl, (_udata + 0x12)		; flags
	ld a, h
	or l
	jr z, fk_1
	ld hl, #0x16			; EINVAL
	ld (_udata + 0x0c), hl
fk_fail:
	ld hl, #0xffff
fk_ret:
	pop af
	pop ix
	ret
fk_1:
	call _ptab_alloc
	ld c, l
	ld b, h
	ld a, h
	or l
	jr z, fk_fail
	push bc
	call ___hard_di
	pop bc
	pop af
	push hl				; saved irq state
	ld hl, (_udata + 0)
	ld (hl), #2			; P_READY
	push bc
	push bc
	call _dofork
	pop af
	ex de, hl
	pop bc
	ld a, e
	inc a
	jr nz, fk_2
	ld a, d
	inc a
	jr nz, fk_2
	ld hl, (_udata + 0)
	ld (hl), #1			; P_RUNNING
	push bc
	push de
	push bc
	call _pagemap_free
	pop af
	pop de
	pop bc
	xor a
	ld (bc), a			; new process P_EMPTY
	ld hl, #0x0c			; ENOMEM
	ld (_udata + 0x0c), hl
	ld hl, (_nproc)
	dec hl
	ld (_nproc), hl
	ld hl, #_nready
	dec (hl)
fk_2:
	pop hl
	push hl
	push de
	call	ixh_p1___hard_irqrestore
	pop hl
	jr fk_ret

; ---------------------------------------------------------------
; M85: signal, sigdisp, kill
; p_sig[2] at p_tab+0x15, 6 bytes each: pending +0, ignored +2, held +4
; ---------------------------------------------------------------
	.globl _valaddr_r, _recalc_cursig, _ssig, _super
	.globl __signal, __sigdisp, __kill

; A = sig -> BC = 1 << (sig & 15)
sn_mask:
	and #0x0f
	ld bc, #1
	ret z
sn_m1:
	sla c
	rl b
	dec a
	jr nz, sn_m1
	ret

; arg_t _signal(void): sig u_argn, func u_argn1.  locals -2/-1 irq, -4/-3 old vector
__signal::
	call ___sdcc_enter_ix
	push af
	push af
	ld hl, (_udata + 0x12)
	ld a, h
	or a
	jr nz, sn_inv
	ld a, l
	or a
	jr z, sn_inv
	cp #0x20			; NSIGS
	jp c, sn_1
sn_inv:
	ld hl, #0x16			; EINVAL
	ld (_udata + 0x0c), hl
sn_fail:
	ld hl, #0xffff
sn_ret:
	jp	ixh_leave
sn_1:
	ld de, (_udata + 0)
	ld hl, #0x15
	add hl, de
	ex de, hl			; DE = &p_sig[0]
	ld a, (_udata + 0x12)
	cp #16
	jp c, sn_2
	ld hl, #6
	add hl, de
	ex de, hl
sn_2:
	push de
	call ___hard_di
	pop de
	ld -2 (ix), l
	ld -1 (ix), h
	inc de
	inc de				; DE = &s_ignored
	ld hl, (_udata + 0x14)		; func
	ld a, h
	or a
	jr nz, sn_func
	ld a, l
	cp #1				; SIG_IGN
	jr nz, sn_func
	ld a, (_udata + 0x12)
	cp #9				; SIGKILL
	jr z, sn_3
	cp #0x13			; SIGSTOP
	jr z, sn_3
	call sn_mask
	ld a, (de)
	or c
	ld (de), a
	inc de
	ld a, (de)
	or b
	ld (de), a
	jr sn_3
sn_func:
	ld a, h
	or l
	jr z, sn_clr
	push de
	ld bc, #1
	push bc
	push hl
	call _valaddr_r
	pop af
	pop af
	pop de
	ld a, h
	or l
	jr nz, sn_clr
	ld hl, #0x0e			; EFAULT
	ld (_udata + 0x0c), hl
	call sn_rest
	jr sn_fail
sn_clr:
	ld a, (_udata + 0x12)
	call sn_mask
	ld a, c
	cpl
	ld c, a
	ld a, b
	cpl
	ld b, a
	ld a, (de)
	and c
	ld (de), a
	inc de
	ld a, (de)
	and b
	ld (de), a
sn_3:
	ld hl, (_udata + 0x12)
	add hl, hl
	ld de, #_udata + 34
	add hl, de
	ex de, hl			; DE = &u_sigvec[sig]
	ld l, e
	ld h, d
	ld c, (hl)
	inc hl
	ld b, (hl)
	ld -4 (ix), c
	ld -3 (ix), b
	ld a, (_udata + 0x12)
	cp #9
	jr z, sn_4
	cp #0x13
	jr z, sn_4
	ld hl, (_udata + 0x14)
	ld a, l
	ld (de), a
	inc de
	ld a, h
	ld (de), a
sn_4:
	call _recalc_cursig
	call sn_rest
	call	ixh_lh_m4
	jp sn_ret
sn_rest:
	call	ixh_lh_m2
	call	ixh_p1___hard_irqrestore
	ret

; arg_t _sigdisp(void): sig u_argn, disp u_argn1  (sighold/sigrelse)
__sigdisp::
	ld hl, (_udata + 0x12)
	ld a, h
	or a
	jr nz, sd_inv
	ld a, l
	or a
	jr z, sd_inv
	cp #0x20
	jr nc, sd_inv
	cp #9
	jr z, sd_inv
	cp #0x13
	jr nz, sd_1
sd_inv:
	ld hl, #0x16			; EINVAL
	ld (_udata + 0x0c), hl
	ld hl, #0xffff
	ret
sd_1:
	ld de, (_udata + 0)
	ld hl, #0x19			; &p_sig[0].s_held
	add hl, de
	ex de, hl
	cp #16
	jr c, sd_2
	ld hl, #6
	add hl, de
	ex de, hl
sd_2:
	call sn_mask
	ld hl, (_udata + 0x14)
	ld a, h
	or a
	jr nz, sd_clr
	ld a, l
	dec a
	jr nz, sd_clr
	ld a, (de)
	or c
	ld (de), a
	inc de
	ld a, (de)
	or b
	ld (de), a
	jr sd_3
sd_clr:
	ld a, c
	cpl
	ld c, a
	ld a, b
	cpl
	ld b, a
	ld a, (de)
	and c
	ld (de), a
	inc de
	ld a, (de)
	and b
	ld (de), a
sd_3:
	call _recalc_cursig
	ld hl, #0
	ret

; arg_t _kill(void): pid u_argn, sig u_argn1.  locals -2/-1 p, -3 found, -4 signalled
__kill::
	call ___sdcc_enter_ix
	push af
	push af
	xor a
	ld -3 (ix), a
	ld -4 (ix), a
	ld hl, (_udata + 0x14)
	ld a, h
	or a
	jr nz, kl_inv
	ld a, l
	cp #0x20
	jr c, kl_1
kl_inv:
	ld hl, #0x16			; EINVAL
	ld (_udata + 0x0c), hl
kl_fail:
	ld hl, #0xffff
kl_ret:
	jp	ixh_leave
kl_1:
	ld hl, (_udata + 0x12)
	ld a, h
	or l
	jr nz, kl_2
	ld hl, (_udata + 0)
	ld de, #0x41			; pid 0 -> -pgrp
	add hl, de
	ld e, (hl)
	inc hl
	ld d, (hl)
	xor a
	sub e
	ld e, a
	ld a, #0
	sbc d
	ld d, a
	ld (_udata + 0x12), de
kl_2:
	ld hl, #_ptab
	ld -2 (ix), l
	ld -1 (ix), h
kl_loop:
	call	ixh_ed_m2
	ld hl, (_ptab_end)
	ld a, e
	sub l
	ld a, d
	sbc h
	jp nc, kl_end
	push de
	pop iy
	ld c, 0x41 (iy)			; -p_pgrp == pid ?
	ld b, 0x42 (iy)
	xor a
	sub c
	ld c, a
	ld a, #0
	sbc b
	ld b, a
	ld hl, (_udata + 0x12)
	or a
	sbc hl, bc
	jr z, kl_match
	ld hl, (_udata + 0x12)		; p_pid == pid ?
	ld c, 3 (iy)
	ld b, 4 (iy)
	or a
	sbc hl, bc
	jr nz, kl_next
kl_match:
	ld a, #1
	ld -3 (ix), a
	ld hl, (_udata + 0)		; can_signal: same uid or super
	ld de, #5
	add hl, de
	ld c, (hl)
	inc hl
	ld b, (hl)
	ld l, 5 (iy)
	ld h, 6 (iy)
	or a
	sbc hl, bc
	jr z, kl_ok
	call _super
	bit 0, l
	jr z, kl_next
kl_ok:
	ld hl, (_udata + 0x14)
	ld a, h
	or l
	jr z, kl_s
	ld a, l
	push af
	inc sp
	call	ixh_lh_m2
	push hl
	call _ssig
	pop af
	inc sp
kl_s:
	ld a, #1
	ld -4 (ix), a
	ld hl, (_udata + 0x12)
	bit 7, h
	jr nz, kl_next
	ld a, h
	or l
	jr z, kl_next
	ld hl, #0
	jp kl_ret
kl_next:
	call	ixh_lh_m2
	ld de, #0x4b
	add hl, de
	ld -2 (ix), l
	ld -1 (ix), h
	jp kl_loop
kl_end:
	ld a, -4 (ix)
	or a
	jr z, kl_nf
	ld hl, #0
	jp kl_ret
kl_nf:
	ld hl, #3			; ESRCH
	ld (_udata + 0x0c), hl
	ld a, -3 (ix)
	or a
	jp z, kl_fail
	ld hl, #1			; EPERM
	ld (_udata + 0x0c), hl
	jp kl_fail

; ---------------------------------------------------------------
; M86: flock
; ---------------------------------------------------------------
	.globl _deflock, _psleep_flags, _wakeup, __flock

; arg_t _flock(void): file u_argn, lockop u_argn1
; locals: -1 lock, -2 c, -3 self, -5/-4 ino, -7/-6 o.  CFLOCK=0x0f, CFMAX=14, CFLEX=15, O_FLOCK=0x80
__flock::
	call ___sdcc_enter_ix
	push af
	push af
	push af
	push af
	ld a, (_udata + 0x14)
	and #0xef			; ~LOCK_NB
	ld -1 (ix), a
	xor a
	ld -3 (ix), a
	ld a, #2			; LOCK_UN
	sub -1 (ix)
	jr nc, fl_1
	ld hl, #0x16			; EINVAL
	ld (_udata + 0x0c), hl
fl_fail:
	ld hl, #0xffff
fl_ret:
	jp	ixh_leave
fl_1:
	call	ixh_getinode_argn
	ld -5 (ix), l
	ld -4 (ix), h
	ld a, h
	or l
	jr z, fl_fail
	ld hl, (_udata + 0x12)
	ld de, #_udata + 0x7d
	add hl, de
	ld l, (hl)
	call	ixh_oft
	ld -7 (ix), l
	ld -6 (ix), h
	call	ixh_lh_m5
	ld de, #0x49			; c_flags
	add hl, de
	ld a, (hl)
	and #0x0f
	ld -2 (ix), a
	call	ixh_lh_m7
	ld de, #6			; o_access
	add hl, de
	bit 7, (hl)			; O_FLOCK
	jr z, fl_2
	ld a, #1
	ld -3 (ix), a
	ld a, -1 (ix)
	or a
	jr nz, fl_ex
	ld a, -2 (ix)			; downgrade to shared
	cp #0x0f
	jp nz, fl_done
	ld a, #1
	ld -2 (ix), a
	jp fl_done
fl_ex:
	ld a, -2 (ix)			; exclusive -> exclusive: no-op
	cp #0x0f
	jr nz, fl_2
	ld a, -1 (ix)
	dec a
	jr nz, fl_2
	ld hl, #0
	jr fl_ret
fl_2:
	ld hl, (_udata + 0x14)
	ld a, l
	sub #2
	or h
	jr nz, fl_loop
	call	ixh_lh_m7
	ld de, #6
	add hl, de
	res 7, (hl)
	call	ixh_lh_m7
	push hl
	call _deflock
	pop af
	ld hl, #0
	jp fl_ret
fl_loop:
	ld a, -2 (ix)
	cp -3 (ix)			; c == self && lock == LOCK_EX
	jr nz, fl_3
	ld a, -1 (ix)
	dec a
	jr nz, fl_3
	ld a, #0x0f
	ld -2 (ix), a
	jr fl_done
fl_3:
	ld a, -2 (ix)
	cp #0x0e
	jr nc, fl_4
	inc a
	ld -2 (ix), a
	jr fl_done
fl_4:
	jr nz, fl_5
	ld hl, #0x23			; ENOLCK
	ld (_udata + 0x0c), hl
	jp fl_fail
fl_5:
	ld a, (_udata + 0x14)
	and #0x10			; LOCK_NB
	push af
	inc sp
	call	ixh_lh_m5
	ld de, #0x49
	add hl, de
	push hl
	call _psleep_flags
	pop af
	inc sp
	ld a, h
	or l
	jp nz, fl_fail
	call	ixh_lh_m5
	ld de, #0x49
	add hl, de
	ld a, (hl)
	and #0x0f
	ld -2 (ix), a
	jr fl_loop
fl_done:
	call	ixh_lh_m7
	ld de, #6
	add hl, de
	bit 7, (hl)
	jr z, fl_6
	call	ixh_lh_m7
	push hl
	call _deflock
	pop af
fl_6:
	call	ixh_lh_m5
	ld de, #0x49
	add hl, de
	ld a, (hl)
	and #0xf0
	or -2 (ix)
	ld (hl), a
	push hl
	call	ixh_lh_m7
	ld de, #6
	add hl, de
	set 7, (hl)
	pop hl
	call	ixh_p1_wakeup
	ld hl, #0
	jp fl_ret

;
;	M87: rargs / wargs (exec argument block copy). argblk: argc +0,
;	arglen +2, a_buf +6 (size 0x200, limit buf+0x1f4)
;
_rargs::
	call	___sdcc_enter_ix
	ld	hl, #-8
	add	hl, sp
	ld	sp, hl
	call	ixh_ed_p6
	ld	l, e
	ld	h, d
	xor	a
	ld	(hl), a
	inc	hl
	ld	(hl), a
	ld	hl, #6
	add	hl, de
	ld	-2 (ix), l
	ld	-1 (ix), h
	ld	bc, #0x01f4
	add	hl, bc
	ld	-4 (ix), l
	ld	-3 (ix), h
ra_lp:
	call	ixh_lh_p4
	push	hl
	call	_ugetw
	pop	af
	ld	a, h
	or	l
	jp	z, ra_done
	ld	-6 (ix), l
	ld	-5 (ix), h
	ld	a, 4 (ix)
	add	a, #2
	ld	4 (ix), a
	jr	nc, ra_n1
	inc	5 (ix)
ra_n1:
	call	ixh_lh_p6
	ld	c, (hl)
	inc	hl
	ld	b, (hl)
	inc	bc
	ld	(hl), b
	dec	hl
	ld	(hl), c
ra_ch:
	call	ixh_lh_m6
	push	hl
	call	_ugetc
	pop	af
	ld	-7 (ix), l
	inc	-6 (ix)
	jr	nz, ra_n2
	inc	-5 (ix)
ra_n2:
	call	ixh_ed_m2
	ld	a, l
	ld	(de), a
	inc	de
	ld	-2 (ix), e
	ld	-1 (ix), d
	ld	a, -4 (ix)
	sub	e
	ld	a, -3 (ix)
	sbc	a, d
	jr	c, ra_ovf
	ld	a, -7 (ix)
	or	a
	jr	nz, ra_ch
	jr	ra_lp
ra_ovf:
	ld	hl, #7
	ld	(_udata + 0x000c), hl
	ld	l, #1
	jr	ra_out
ra_done:
	call	ixh_ed_p6
	ld	hl, #6
	add	hl, de
	ld	a, -2 (ix)
	sub	l
	ld	c, a
	ld	a, -1 (ix)
	sbc	a, h
	ld	b, a
	inc	de
	inc	de
	ld	a, c
	ld	(de), a
	inc	de
	ld	a, b
	ld	(de), a
	ld	l, #0
ra_out:
	jp	ixh_leave

_wargs::
	call	___sdcc_enter_ix
	ld	hl, #-8
	add	hl, sp
	ld	sp, hl
	call	ixh_ed_p6
	ld	hl, #6
	add	hl, de
	ld	-6 (ix), l
	ld	-5 (ix), h
	ex	de, hl
	inc	hl
	inc	hl
	ld	c, (hl)
	inc	hl
	ld	b, (hl)
	ld	a, 4 (ix)
	sub	c
	ld	4 (ix), a
	ld	a, 5 (ix)
	sbc	a, b
	ld	5 (ix), a
	ld	a, b
	or	c
	jr	z, wa_1
	push	bc
	call	ixh_lh_p4
	push	hl
	call	ixh_lh_m6
	push	hl
	call	__uput
	pop	af
	pop	af
	pop	af
wa_1:
	call	ixh_lh_p6
	ld	c, (hl)
	inc	hl
	ld	b, (hl)
	ld	-4 (ix), c
	ld	-3 (ix), b
	ld	l, c
	ld	h, b
	inc	hl
	add	hl, hl
	ld	a, 4 (ix)
	sub	l
	ld	l, a
	ld	a, 5 (ix)
	sbc	a, h
	ld	h, a
	ld	-2 (ix), l
	ld	-1 (ix), h
	ld	-8 (ix), l
	ld	-7 (ix), h
	ld	a, 9 (ix)
	or	8 (ix)
	jr	z, wa_2
	call	ixh_lh_p8
	ld	(hl), c
	inc	hl
	ld	(hl), b
wa_2:
	ld	a, -4 (ix)
	or	-3 (ix)
	jr	z, wa_end
	call	ixh_lh_m4
	dec	hl
	ld	-4 (ix), l
	ld	-3 (ix), h
	call	ixh_lh_m2
	push	hl
	call	ixh_lh_p4
	push	hl
	call	_uputw
	pop	af
	pop	af
	ld	a, -2 (ix)
	add	a, #2
	ld	-2 (ix), a
	jr	nc, wa_n1
	inc	-1 (ix)
wa_n1:
	ld	a, -4 (ix)
	or	-3 (ix)
	jr	z, wa_2
	call	ixh_ed_m6
	call	ixh_cb_p4
wa_3:
	inc	bc
	ld	a, (de)
	inc	de
	or	a
	jr	nz, wa_3
	ld	4 (ix), c
	ld	5 (ix), b
	ld	-6 (ix), e
	ld	-5 (ix), d
	jr	wa_2
wa_end:
	call	ixh_lh_m2
	push	hl
	ld	hl, #0
	push	hl
	call	_uputw
	pop	af
	pop	af
	call	ixh_lh_m8
	jp	ixh_leave

;
;	M88: _execve (with header_ok and close_on_exec folded in).
;	exec header: magic +0, cpu +2, feat +3, base +4, text +6, data +8,
;	bss +10, entry +12, size +13.
;	Locals (IX): -2 bin_size  -4 bss  -6 progload  -8 progptr
;	  -10 abuf  -12 ebuf  -14 nargv  -16 nenvp  -18 argc  -19 mflags
;
__execve::
	call	___sdcc_enter_ix
	ld	hl, #-20
	add	hl, sp
	ld	sp, hl
	ld	hl, (_ramtop)
	ld	(ex_top), hl
	ld	hl, (_udata + 18)
	ld	bc, #0
	push	bc
	push	hl
	call	_n_open
	pop	af
	pop	af
	ld	a, h
	or	l
	jr	nz, ex_1
	ld	hl, #0xffff
	jp	ex_ret
ex_1:
	ld	(ex_ino), hl
	push	hl
	call	_getperm
	pop	af
	bit	0, l
	jr	z, ex_eacc
	ld	hl, (ex_ino)
	ld	de, #6
	add	hl, de
	ld	c, (hl)
	inc	hl
	bit	7, (hl)
	jr	z, ex_eacc
	ld	a, c
	and	#0x49
	jr	nz, ex_2
ex_eacc:
	ld	hl, #13
ex_err:
	ld	(_udata + 0x0c), hl
	jp	ex_fail
ex_2:
	ld	hl, (ex_ino)
	ld	de, #74
	add	hl, de
	ld	e, (hl)
	ld	d, #0
	ld	l, e
	ld	h, d
	add	hl, hl
	add	hl, de
	add	hl, hl
	add	hl, de
	add	hl, hl
	add	hl, hl
	add	hl, hl
	add	hl, hl
	add	hl, de
	add	hl, hl
	add	hl, de
	ld	bc, #_fs_tab + 2
	add	hl, bc
	ld	a, (hl)
	ld	-19 (ix), a
	bit	2, a
	jr	nz, ex_eacc
	ld	a, #1
	push	af
	inc	sp
	ld	hl, (ex_ino)
	push	hl
	call	_setftime
	pop	af
	inc	sp
	ld	hl, #0
	ld	(_udata + 0x66), hl
	ld	(_udata + 0x68), hl
	ld	l, #0x10
	ld	(_udata + 0x64), hl
	ld	hl, #ex_hdr
	ld	(_udata + 0x62), hl
	ld	a, #1
	ld	(_udata + 0x6c), a
	xor	a
	push	af
	inc	sp
	ld	hl, (ex_ino)
	push	hl
	call	_readi
	pop	af
	inc	sp
	ld	hl, (_udata + 0x99)
	ld	a, l
	sub	#0x10
	or	h
	jr	nz, ex_enoexec
;	header_ok
	ld	hl, (ex_hdr)
	ld	de, #0x80a8
	or	a
	sbc	hl, de
	jr	nz, ex_enoexec
	ld	a, (ex_hdr + 2)
	ld	hl, #_sys_cpu
	cp	(hl)
	jr	nz, ex_enoexec
	ld	a, (ex_hdr + 3)
	ld	c, a
	ld	hl, #_sys_cpu_feat
	and	(hl)
	cp	c
	jr	z, ex_3
ex_enoexec:
	ld	hl, #8
	jp	ex_err
ex_3:
	ld	hl, #ex_hdr
	push	hl
	call	_pagemap_prepare
	pop	af
	bit	7, h
	jp	nz, ex_fail
	ld	a, (ex_hdr + 4)
	ld	-5 (ix), a
	ld	-6 (ix), #0
	ld	hl, #ex_hdr + 13
	add	a, (hl)
	ld	(ex_top + 1), a
	xor	a
	ld	(ex_top), a
	ld	hl, (ex_hdr + 10)
	ld	-4 (ix), l
	ld	-3 (ix), h
	ld	hl, (ex_hdr + 6)
	ld	de, (ex_hdr + 8)
	add	hl, de
	ld	-2 (ix), l
	ld	-1 (ix), h
	ld	de, (ex_hdr + 6)
	or	a
	sbc	hl, de
	jr	c, ex_enomem
	ld	hl, (ex_top)
	call	ixh_ed_m6
	or	a
	sbc	hl, de
	jr	c, ex_enomem
;	hl = top - progload
	call	ixh_ed_m2
	push	hl
	call	ixh_lh_m4
	add	hl, de
	jr	c, ex_enomem1
;	progptr = bin_size + 0x400 + bss  (bc)
	call	ixh_cb_m4
	ld	a, d
	add	a, #4
	ld	d, a
	ex	de, hl
	add	hl, bc
	ld	b, h
	ld	c, l
;	checks: bin_size >= 64, progload >= 0x100, avail >= progptr, no wrap
	call	ixh_lh_m2
	ld	de, #0x40
	or	a
	sbc	hl, de
	jr	c, ex_enomem1
	ld	a, -5 (ix)
	or	a
	jr	z, ex_enomem1
	pop	hl
	or	a
	sbc	hl, bc
	jr	c, ex_enomem
	ld	l, c
	ld	h, b
	call	ixh_ed_m2
	or	a
	sbc	hl, de
	jr	nc, ex_4
ex_enomem:
	ld	hl, #12
	jp	ex_err
ex_enomem1:
	pop	hl
	jr	ex_enomem
ex_4:
	ld	hl, (_udata)
	ld	(hl), #8
	call	_tmpbuf
	ld	-10 (ix), l
	ld	-9 (ix), h
	call	_tmpbuf
	ld	-12 (ix), l
	ld	-11 (ix), h
	ld	hl, (_udata + 20)
	ld	c, -10 (ix)
	ld	b, -9 (ix)
	push	bc
	push	hl
	call	_rargs
	pop	af
	pop	af
	bit	0, l
	jp	nz, ex_ng3
	ld	hl, (_udata + 22)
	ld	c, -12 (ix)
	ld	b, -11 (ix)
	push	bc
	push	hl
	call	_rargs
	pop	af
	pop	af
	bit	0, l
	jp	nz, ex_ng3
	ld	hl, (ex_top)
	push	hl
	ld	hl, #ex_hdr
	push	hl
	call	_pagemap_realloc
	pop	af
	pop	af
	ld	a, h
	or	l
	jp	nz, ex_ng3
;	committed
	ld	hl, (ex_top)
	ld	(_udata + 0x1c), hl
	ex	de, hl
	ld	hl, (_udata)
	ld	bc, #0x45
	add	hl, bc
	ld	(hl), e
	inc	hl
	ld	(hl), d
	bit	1, -19 (ix)
	jr	nz, ex_5
	ld	iy, (ex_ino)
	bit	3, 7 (iy)
	jr	z, ex_6
	ld	l, 10 (iy)
	ld	h, 11 (iy)
	ld	(_udata + 0x71), hl
ex_6:
	bit	2, 7 (iy)
	jr	z, ex_5
	ld	l, 12 (iy)
	ld	h, 13 (iy)
	ld	(_udata + 0x73), hl
ex_5:
	call	ixh_lh_m6
	ld	(_udata + 0x20), hl
	ld	de, #0x10
	push	de
	push	hl
	ld	hl, #_sys_stubs
	push	hl
	call	_uput
	pop	af
	pop	af
	pop	af
;	close_on_exec
	ld	bc, #0x0200
	ld	d, #9
ex_c1:
	ld	hl, (_udata + 0x87)
	ld	a, l
	and	c
	ld	e, a
	ld	a, h
	and	b
	or	e
	jr	z, ex_c2
	push	bc
	push	de
	push	de
	inc	sp
	call	_doclose
	inc	sp
	pop	de
	pop	bc
ex_c2:
	srl	b
	rr	c
	dec	d
	bit	7, d
	jr	z, ex_c1
	ld	hl, #0
	ld	(_udata + 0x87), hl
;	read the program image
	call	ixh_lh_m6
	ld	de, #0x10
	add	hl, de
	ld	-8 (ix), l
	ld	-7 (ix), h
	ld	(_udata + 0x62), hl
	call	ixh_lh_m2
	or	a
	sbc	hl, de
	ld	-2 (ix), l
	ld	-1 (ix), h
	ld	(_udata + 0x64), hl
	xor	a
	ld	(_udata + 0x6c), a
	push	hl
	call	ixh_lh_m8
	push	hl
	call	_valaddr_r
	pop	af
	pop	af
	call	ixh_ed_m2
	or	a
	sbc	hl, de
	ld	a, h
	or	l
	jp	nz, ex_ng4
	xor	a
	push	af
	inc	sp
	ld	hl, (ex_ino)
	push	hl
	call	_readi
	pop	af
	inc	sp
	ld	hl, (_udata + 0x99)
	call	ixh_ed_m2
	or	a
	sbc	hl, de
	ld	a, h
	or	l
	jp	nz, ex_ng4
	call	ixh_lh_m8
	add	hl, de
	ld	-8 (ix), l
	ld	-7 (ix), h
	call	ixh_ed_m4
	push	de
	push	hl
	call	_uzero
	pop	af
	pop	af
	call	ixh_lh_m8
	call	ixh_ed_m4
	add	hl, de
	ld	(_udata + 0x1e), hl
;	clear signal vectors
	ld	hl, #_udata + 0x22
	ld	b, #0x40
ex_z:
	ld	(hl), #0
	inc	hl
	djnz	ex_z
;	argument / environment blocks
	push	ix
	pop	hl
	ld	de, #-18
	add	hl, de
	push	hl
	call	ixh_lh_m10
	push	hl
	ld	hl, (ex_top)
	dec	hl
	dec	hl
	push	hl
	call	_wargs
	pop	af
	pop	af
	pop	af
	ld	-14 (ix), l
	ld	-13 (ix), h
	ld	hl, #0
	push	hl
	call	ixh_lh_m12
	push	hl
	ld	l, -14 (ix)
	ld	h, -13 (ix)
	push	hl
	call	_wargs
	pop	af
	pop	af
	pop	af
	ld	-16 (ix), l
	ld	-15 (ix), h
	ld	l, -14 (ix)
	ld	h, -13 (ix)
	push	hl
	call	_ugetw
	pop	af
	ld	de, #8
	push	de
	ld	de, #_udata + 0x75
	push	de
	push	hl
	call	_uget
	pop	af
	pop	af
	pop	af
	ld	hl, (_udata)
	ld	de, #0x25
	add	hl, de
	ex	de, hl
	ld	hl, #_udata + 0x75
	ld	bc, #8
	ldir
	call	ixh_lh_m10
	push	hl
	call	_tmpfree
	pop	af
	call	ixh_lh_m12
	push	hl
	call	_tmpfree
	pop	af
	ld	hl, (ex_ino)
	call	ixh_p1_i_deref
;	argc / argv below envp
	ld	l, -16 (ix)
	ld	h, -15 (ix)
	dec	hl
	dec	hl
	ld	-8 (ix), l
	ld	-7 (ix), h
	push	hl
	ld	l, -14 (ix)
	ld	h, -13 (ix)
	push	hl
	call	_uputw
	pop	af
	pop	af
	ld	l, -16 (ix)
	ld	h, -15 (ix)
	dec	hl
	dec	hl
	dec	hl
	dec	hl
	ld	(_udata + 0x1a), hl
	push	hl
	ld	l, -18 (ix)
	ld	h, -17 (ix)
	push	hl
	call	_uputw
	pop	af
	pop	af
	ld	hl, (_udata)
	ld	(hl), #1
	call	ixh_ed_m6
	ld	a, (ex_hdr + 12)
	ld	l, a
	ld	h, #0
	add	hl, de
	push	hl
	call	_doexec
	pop	af
ex_ng4:
	ld	hl, (_udata)
	ld	a, #9
	push	af
	inc	sp
	push	hl
	call	_ssig
	pop	af
	inc	sp
ex_ng3:
	ld	hl, (_udata)
	ld	(hl), #1
	call	ixh_lh_m10
	push	hl
	call	_tmpfree
	pop	af
	call	ixh_lh_m12
	push	hl
	call	_tmpfree
	pop	af
ex_fail:
	ld	hl, (ex_ino)
	call	ixh_p1_i_deref
	ld	hl, #0xffff
ex_ret:
	jp	ixh_leave

	.area	_DATA
ex_hdr:
	.ds	16
ex_ino:
	.ds	2
ex_top:
	.ds	2
	.area	_CODE

__uadmin::
	call _esuper
	bit 0, l
	jr z, ua_1
	ld hl, #0xffff
	ret
ua_1:
	ld hl, (_udata + 20)
	ld a, l
	dec a
	or h
	call nz, _sync
	ld hl, (_udata + 0x12)
	ld a, l
	dec a
	or h
	jr z, ua_halt
	ld a, l
	sub #3
	or h
	jr nz, ua_2
ua_halt:
	ld hl, #ua_msg
	call	ixh_p1_kputs
	call _plt_monitor
ua_2:
	ld hl, (_udata + 0x12)
	ld a, l
	sub #2
	or h
	jr nz, ua_3
	call _plt_reboot
ua_3:
	ld hl, #0x16
	ld (_udata + 0x0c), hl
	ld hl, #0xffff
	ret
ua_msg:
	.ascii "Halted."
	.db 0x0a, 0x00

;
;	M90: filesys leftovers: emptydir super esuper getmode newfstab
;	fmount magic. (struct mount is 0xe3 bytes: m_dev +0, m_flags +2,
;	m_mntpt +4, m_fs +6 (superblock 0xdd bytes copied))
;
_emptydir::
	call	___sdcc_enter_ix
	ld	hl, #-32
	add	hl, sp
	ld	sp, hl
	ld	hl, #0x40
	ld	(_udata + 0x66), hl
	ld	hl, #0
	ld	(_udata + 0x68), hl
ed_lp:
	ld	hl, #0x20
	ld	(_udata + 0x64), hl
	push	ix
	pop	hl
	ld	de, #-32
	add	hl, de
	ld	(_udata + 0x62), hl
	ld	a, #1
	ld	(_udata + 0x6c), a
	xor	a
	push	af
	inc	sp
	call	ixh_lh_p4
	push	hl
	call	_readi
	pop	af
	inc	sp
	ld	a, -30 (ix)
	or	a
	ld	l, #0
	jr	nz, ed_out
	ld	hl, (_udata + 0x99)
	ld	a, l
	sub	#0x20
	or	h
	jr	z, ed_lp
	ld	l, #1
ed_out:
	jp	ixh_leave

_super::
	ld	hl, (_udata + 0x71)
	ld	a, h
	or	l
	ld	l, #0
	ret	nz
	inc	l
	ret

_esuper::
	ld	hl, (_udata + 0x71)
	ld	a, h
	or	l
	ld	l, #0
	ret	z
	ld	hl, #1
	ld	(_udata + 0x0c), hl
	ret

_getmode::
	call	ixh_sp2_ed
	ex	de, hl
	ld	de, #7
	add	hl, de
	ld	a, (hl)
	and	#0xf0
	ld	l, a
	ret

_newfstab::
	ld	hl, #_fs_tab
	ld	bc, #0xe3
	ld	d, #4
nf_lp:
	ld	a, (hl)
	inc	hl
	and	(hl)
	dec	hl
	inc	a
	ret	z
	add	hl, bc
	dec	d
	jr	nz, nf_lp
	ld	hl, #0
	ret

_magic::
	call	ixh_sp2_ed
	ld	a, (de)
	inc	de
	cp	#0x91
	jr	nz, mg_bad
	ld	a, (de)
	cp	#0x60
	ret	z
mg_bad:
	ld	hl, #mg_msg
	call	ixh_p1_panic
	ret
mg_msg:
	.ascii	"corrupt inode"
	.db	0x00

_fmount::
	call	___sdcc_enter_ix
	ld	hl, #-4
	add	hl, sp
	ld	sp, hl
	xor	a
	push	af
	inc	sp
	call	ixh_lh_p4
	push	hl
	call	_d_open
	pop	af
	inc	sp
	ld	a, h
	or	l
	ld	hl, #0
	jp	nz, fm_out
	call	_newfstab
	ld	a, h
	or	l
	jr	nz, fm_2
	ld	hl, #0x18
	ld	(_udata + 0x0c), hl
	jp	fm_out
fm_2:
	ld	-2 (ix), l
	ld	-1 (ix), h
	ld	de, #6
	add	hl, de
	ld	-4 (ix), l
	ld	-3 (ix), h
	xor	a
	push	af
	inc	sp
	ld	hl, #1
	push	hl
	call	ixh_lh_p4
	push	hl
	call	_bread
	pop	af
	pop	af
	inc	sp
	ld	a, h
	or	l
	jr	nz, fm_3
	ld	hl, #0
	jp	fm_out
fm_3:
	push	hl
	call	ixh_ed_m4
	ld	bc, #0xdd
	ldir
	call	_brelse
	pop	af
	call	ixh_lh_m4
	ld	a, (hl)
	cp	#0xc6
	jr	nz, fm_bad
	inc	hl
	ld	a, (hl)
	cp	#0x31
	jr	nz, fm_bad
	inc	hl
	ld	e, (hl)
	inc	hl
	ld	d, (hl)
	inc	hl
	ld	c, (hl)
	inc	hl
	ld	b, (hl)
	ex	de, hl
	or	a
	sbc	hl, bc
	jr	nc, fm_bad
	call	ixh_lh_m4
	ld	de, #0xdc
	add	hl, de
	ld	a, (hl)
	or	a
	jr	z, fm_4
fm_bad:
	ld	hl, #0x16
	ld	(_udata + 0x0c), hl
	ld	hl, #0
	jr	fm_out
fm_4:
	ld	de, #0xd2 - 0xdc
	add	hl, de
	ld	a, (hl)
	dec	a
	jr	nz, fm_5
	push	hl
	ld	hl, #fm_msg
	call	ixh_p1_kputs
	pop	hl
	set	0, 8 (ix)
fm_5:
	ld	(hl), #1
	bit	0, 8 (ix)
	jr	z, fm_6
	ld	(hl), #2
fm_6:
	call	ixh_lh_m2
	ld	de, #4
	add	hl, de
	call	ixh_ed_p6
	ld	(hl), e
	inc	hl
	ld	(hl), d
	ld	a, d
	or	e
	jr	z, fm_7
	ld	hl, #0x46
	add	hl, de
	inc	(hl)
fm_7:
	call	ixh_lh_m2
	ld	a, 4 (ix)
	ld	(hl), a
	inc	hl
	ld	a, 5 (ix)
	ld	(hl), a
	inc	hl
	ld	a, 8 (ix)
	ld	(hl), a
	inc	hl
	ld	a, 9 (ix)
	ld	(hl), a
	call	_sync
	call	ixh_lh_m2
fm_out:
	jp	ixh_leave
fm_msg:
	.ascii	"warning: mounting dirty file system, forcing r/o."
	.db	0x0a, 0x00

;	baddev(struct filesys *fs): true if the superblock magic is wrong
_baddev::
	call	ixh_sp2_ed
	ld	a, (de)
	inc	de
	cp	#0xc6
	jr	nz, bd_bad
	ld	a, (de)
	cp	#0x31
	jr	nz, bd_bad
	ld	l, #0
	ret
bd_bad:
	ld	l, #1
	ret

;
;	M91: uputblk(src, off, len) / ugetblk(dst, off, len): block copy
;	to/from the current process (memcpy when u_sysio, else uput/uget).
;	Return len.
;
_uputblk::
	call	ixh_sp2_ed
	inc	hl
	ld	c, (hl)
	inc	hl
	ld	b, (hl)
	inc	hl
	ld	a, (hl)
	inc	hl
	ld	h, (hl)
	ld	l, a
	push	hl
	ex	de, hl
	add	hl, bc
	ld	a, (_udata + 108)
	rra
	jr	nc, ub_user
	push	hl
	ld	hl, (_udata + 98)
	push	hl
	call	___memcpy
	jr	ub_done
ub_user:
	ld	de, (_udata + 98)
	push	de
	push	hl
	call	__uput
ub_done:
	pop	af
	pop	af
	pop	af
	jr	blk_ret
_ugetblk::
	call	ixh_sp2_ed
	inc	hl
	ld	c, (hl)
	inc	hl
	ld	b, (hl)
	inc	hl
	ld	a, (hl)
	inc	hl
	ld	h, (hl)
	ld	l, a
	push	hl
	ex	de, hl
	add	hl, bc
	ld	a, (_udata + 108)
	rra
	jr	nc, gb_user
	ld	de, (_udata + 98)
	push	de
	push	hl
	call	___memcpy
	jr	gb_done
gb_user:
	push	hl
	ld	hl, (_udata + 98)
	push	hl
	call	__uget
gb_done:
	pop	af
	pop	af
	pop	af
blk_ret:
	ld	hl, #6
	add	hl, sp
	ld	a, (hl)
	inc	hl
	ld	h, (hl)
	ld	l, a
	ret

;
;	blk512 inode helpers (64-byte disk inodes, 8 per 512-byte block,
;	inode table starts at block 2)
;
;	inode_blocks(ino): (i_size + 511) >> 9  (16 bit result)
_inode_blocks::
	call	ixh_sp2_ed
	ex	de, hl
	ld	de, #0x0e
	add	hl, de
	ld	c, (hl)
	inc	hl
	ld	b, (hl)
	inc	hl
	ld	e, (hl)
	inc	hl
	ld	d, (hl)
	ld	a, c
	add	a, #0xff
	ld	a, b
	adc	a, #1
	ld	l, a
	jr	nc, ib_1
	inc	de
ib_1:
	ld	h, e
	ld	c, d
	srl	c
	rr	h
	rr	l
	ret

;	breadi(dev, n, dst): read disk inode n into dst, returns 1 on error
_breadi::
	call	ixh_sp2_cb
	inc	hl
	ld	e, (hl)
	inc	hl
	ld	d, (hl)
	inc	hl
	ld	a, (hl)
	inc	hl
	ld	h, (hl)
	ld	l, a
	push	hl
	push	de
	ex	de, hl
	srl	h
	rr	l
	srl	h
	rr	l
	srl	h
	rr	l
	inc	hl
	inc	hl
	xor	a
	push	af
	inc	sp
	push	hl
	push	bc
	call	_bread
	pop	af
	pop	af
	inc	sp
	ld	a, h
	or	l
	jr	nz, bi_ok
	pop	af
	pop	af
	ld	l, #1
	ret
bi_ok:
	ld	c, l
	ld	b, h
	pop	de
	ld	a, e
	pop	de
	and	#7
	ld	l, a
	ld	h, #0
	add	hl, hl
	add	hl, hl
	add	hl, hl
	add	hl, hl
	add	hl, hl
	add	hl, hl
	add	hl, bc
	push	bc
	ld	bc, #0x40
	ldir
	call	_brelse
	pop	af
	ld	l, #0
	ret

;	bwritei(ino): write the in-core disk inode back, returns 1 on error
_bwritei::
	call	ixh_sp2_ed
	ld	hl, #4
	add	hl, de
	ld	c, (hl)
	inc	hl
	ld	b, (hl)
	push	bc
	srl	b
	rr	c
	srl	b
	rr	c
	srl	b
	rr	c
	inc	bc
	inc	bc
	push	de
	ld	l, e
	ld	h, d
	inc	hl
	inc	hl
	ld	a, (hl)
	inc	hl
	ld	h, (hl)
	ld	l, a
	xor	a
	push	af
	inc	sp
	push	bc
	push	hl
	call	_bread
	pop	af
	pop	af
	inc	sp
	ld	a, h
	or	l
	jr	nz, bw_ok
	pop	af
	pop	af
	ld	l, #1
	ret
bw_ok:
	ld	c, l
	ld	b, h
	pop	de
	pop	hl
	ld	a, l
	and	#7
	ld	l, a
	ld	h, #0
	add	hl, hl
	add	hl, hl
	add	hl, hl
	add	hl, hl
	add	hl, hl
	add	hl, hl
	add	hl, bc
	ex	de, hl
	ld	a, l
	add	a, #6
	ld	l, a
	jr	nc, bw_1
	inc	h
bw_1:
	push	bc
	ld	bc, #0x40
	ldir
	pop	bc
	ld	a, #2
	push	af
	inc	sp
	push	bc
	call	_bfree
	pop	af
	inc	sp
	ld	l, #0
	ret

;
;	M92: timer.  tod = 8 bytes (two 32 bit counters), tod_deci counts
;	tenths up to a second.
;
;	set_timer_duration(d): returns ticks + d, complains if d < 0
_set_timer_duration::
	call	ixh_sp2_cb
	bit	7, b
	jr	z, st_ok
	push	bc
	ld	hl, #st_msg
	push	hl
	call	_kprintf
	pop	af
	pop	bc
st_ok:
	ld	hl, (_ticks)
	add	hl, bc
	ret
st_msg:
	.ascii	"bad timer duration 0x%x"
	.db	0x0a, 0x00

;	timer_expired(t): 1 if t < ticks
_timer_expired::
	call	ixh_sp2_ed
	ld	hl, (_ticks)
	ld	a, e
	sub	l
	ld	a, d
	sbc	a, h
	ld	a, #0
	rla
	ld	l, a
	ret

;	rdtime(ptr) / rdtime32(ptr) / wrtime(ptr)
_rdtime::
	ld	bc, #8
	jr	rt_rd
_rdtime32::
	ld	bc, #4
rt_rd:
	push	bc
	call	___hard_di
	pop	bc
	push	hl
	call	ixh_sp4_ed
	ld	hl, #_tod
	ldir
	call	___hard_irqrestore
	pop	af
	ret

_wrtime::
	call	___hard_di
	push	hl
	call	ixh_sp4_ed
	ex	de, hl
	ld	de, #_tod
	ld	bc, #8
	ldir
	call	___hard_irqrestore
	pop	af
	ret

_updatetod::
_tick_clock::
	ld	hl, #_tod_deci
	inc	(hl)
	ld	a, (hl)
	sub	#10
	ret	nz
	ld	(hl), a
	ld	hl, #_tod
	inc	(hl)
	jr	nz, tc_s
	inc	hl
	inc	(hl)
	jr	nz, tc_s
	inc	hl
	inc	(hl)
	jr	nz, tc_s
	inc	hl
	inc	(hl)
	jr	nz, tc_s
	ld	hl, #_tod + 4
	inc	(hl)
	jr	nz, tc_s
	inc	hl
	inc	(hl)
	jr	nz, tc_s
	inc	hl
	inc	(hl)
	jr	nz, tc_s
	inc	hl
	inc	(hl)
tc_s:
	ld	hl, #_rtcsec
	inc	(hl)
	ret

;
;	/dev/null(0) /dev/mem(1) /dev/zero(2) /dev/proc(3)
;	sys_read/sys_write(minor byte, rawflag, flag); sys_ioctl(minor, req, ptr)
;
_sys_read::
	ld	hl, #2
	add	hl, sp
	ld	a, (hl)
	or	a
	jr	z, sr_null
	dec	a
	jr	z, sr_mem
	dec	a
	jr	z, sr_zero
	dec	a
	jr	z, sr_proc
	jp	sx_enxio
sr_null:
	ld	hl, #0
	ret
sr_mem:
	ld	hl, (_udata + 0x64)
	push	hl
	ld	hl, (_udata + 98)
	push	hl
	ld	hl, (_udata + 102)
	push	hl
	call	_uput
	jr	sx_cp
sr_zero:
	ld	hl, (_udata + 0x64)
	push	hl
	ld	de, (_udata + 98)
	ld	a, (_udata + 108)
	rra
	jr	nc, sr_z1
	ld	hl, #0
	push	hl
	push	de
	call	_memset
	pop	af
	jr	sr_z2
sr_z1:
	push	de
	call	_uzero
sr_z2:
	pop	af
	pop	af
	ld	hl, (_udata + 0x64)
	ret
sr_proc:
	ld	hl, (_udata + 0x64)
	ld	de, #0x4b
	or	a
	sbc	hl, de
	jr	c, sr_p1
	ld	(_udata + 0x64), de
sr_p1:
	ld	hl, (_udata + 104)
	ld	a, h
	or	l
	jr	nz, sr_none
	ld	hl, (_udata + 102)
	ld	de, (_udata + 0x64)
	add	hl, de
	jr	c, sr_none
	ld	bc, #0x0465
	or	a
	sbc	hl, bc
	jr	z, sr_p2
	jr	nc, sr_none
sr_p2:
	push	de
	ld	hl, (_udata + 98)
	push	hl
	ld	hl, (_udata + 102)
	ld	de, #_ptab
	add	hl, de
	push	hl
	call	_uput
sx_cp:
	pop	af
	pop	af
	pop	af
	ld	a, h
	or	l
	jr	z, sx_ok
	ld	hl, #0xffff
	ret
sx_ok:
	ld	hl, (_udata + 0x64)
	push	hl
	call	_umove
	pop	af
	ret
sr_none:
	ld	hl, #0
	ret
sx_enxio:
	ld	hl, #6
sx_err:
	ld	(_udata + 0x0c), hl
	ld	hl, #0xffff
	ret

_sys_write::
	ld	hl, #2
	add	hl, sp
	ld	a, (hl)
	or	a
	jr	z, sw_cnt
	dec	a
	jr	z, sw_mem
	dec	a
	jr	z, sw_cnt
	dec	a
	jr	z, sw_proc
	jr	sx_enxio
sw_cnt:
	ld	hl, (_udata + 0x64)
	ret
sw_mem:
	ld	hl, (_udata + 0x64)
	push	hl
	ld	hl, (_udata + 98)
	push	hl
	ld	hl, (_udata + 102)
	push	hl
	call	_uget
	jr	sx_cp
sw_proc:
	ld	hl, #0x16
	jr	sx_err

_sys_ioctl::
	ld	hl, #2
	add	hl, sp
	ld	a, (hl)
	sub	#3
	jr	z, si_1
	ld	hl, #0xffff
	ret
si_1:
	ld	hl, #5
	add	hl, sp
	ld	c, (hl)
	inc	hl
	ld	b, (hl)
	ld	hl, #3
	add	hl, sp
	ld	a, (hl)
	inc	hl
	ld	h, (hl)
	ld	l, a
	dec	l
	jr	nz, si_2
	ld	a, h
	or	a
	jr	nz, si_bad
	ld	hl, (_maxproc)
	jr	si_put
si_2:
	dec	l
	jr	nz, si_bad
	ld	a, h
	or	a
	jr	nz, si_bad
	ld	hl, #0x4b
si_put:
	push	bc
	push	hl
	call	_uputw
	pop	af
	pop	af
	ld	hl, #0
	ret
si_bad:
	ld	hl, #0xffff
	ret
