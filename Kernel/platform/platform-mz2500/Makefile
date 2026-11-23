CSRCS =

ASRCS = crt0.s mz2500.s
ASRCS += ixh_asm.s lowlevel_asm.s usermem_asm.s memalloc_asm.s version_asm.s data_asm.s tricks.s commonmem.s emm.s video.s sasi.s platform.s pagemap.s umem.s kbd.s bufcache.s fs_asm.s inode_asm.s q_asm.s proc_asm.s sys_asm.s kprint_asm.s tty_asm.s devfd.s bmap.s devtty_asm.s devices_asm.s devhd_asm.s open_asm.s vt_asm.s start_asm.s devio_asm.s 

AOBJS = $(ASRCS:.s=.rel)
COBJS = $(CSRCS:.c=.rel)

OBJS  = $(AOBJS) $(COBJS)

JUNK = *.rel *.lst *.asm *.sym *.rst

all:	$(OBJS)

$(AOBJS): %.rel: %.s
	$(CROSS_AS) $(ASOPTS) -g $<

$(COBJS): %.rel: %.c
	$(CROSS_CC) $(CROSS_CCOPTS) -c $<

clean:
	rm -f $(OBJS) $(JUNK) core *~

# The boot image is built by tools in the port tree (mkimage), not here.
image:
