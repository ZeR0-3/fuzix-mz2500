; devices_asm.s - device switch table and misc device helpers (hand-written)
	.module devices_asm
	.globl _dev_tab, _validdev, _device_init, _sys_close
	.globl _hd_open, _hd_read, _hd_write, _hd_probe
	.globl _fd_open, _fd_read, _fd_write, _fd_ioctl
	.globl _tty_open, _tty_close, _tty_read, _tty_write, _vt_ioctl
	.globl _no_open, _no_close, _no_rdwr, _no_ioctl
	.globl _sys_read, _sys_write, _sys_ioctl
	.area _CODE
; validdev(dev16): TRUE if dev <= 0x04ff
_validdev::
	ld	hl, #3
	add	hl, sp
	ld	a, (hl)
	ld	l, #0
	cp	a, #5
	ret	nc
	inc	l
	ret
_device_init::
	jp	_hd_probe
_sys_close::
	ld	hl, #0
	ret
; open, close, read, write, ioctl per major (read-only)
_dev_tab::
	.dw _hd_open, _no_close, _hd_read, _hd_write, _no_ioctl
	.dw _fd_open, _no_close, _fd_read, _fd_write, _fd_ioctl
	.dw _tty_open, _tty_close, _tty_read, _tty_write, _vt_ioctl
	.dw _no_open, _no_close, _no_rdwr, _no_rdwr, _no_ioctl
	.dw _no_open, _no_close, _sys_read, _sys_write, _sys_ioctl
