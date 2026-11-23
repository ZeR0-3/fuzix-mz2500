# Inittab with login (init parses in place: keep a leading comment line)
id:3:initdefault:
rc::bootwait:/etc/rc
01:3:respawn:getty -L /dev/tty1
