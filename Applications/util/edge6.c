#include <stdio.h>
#include <unistd.h>
#include <fcntl.h>
#include <errno.h>
#include <string.h>

/* user address validation near the top of memory */
static void t(const char *nm, int r, int e)
{
	printf("%s r=%d e=%d\n", nm, r, e);
}
int main(void)
{
	int fd, r, e;
	char *top = (char *)0xFFF0;
	fd = open("/etc/passwd", O_RDONLY);
	if (fd < 0) fd = open("/init", O_RDONLY);
	errno = 0; r = read(fd, top, 100); e = errno; t("rd-cross-top", r, e);
	errno = 0; r = read(fd, (char *)0xFF00, 0x200); e = errno; t("rd-wrap", r, e);
	errno = 0; r = read(fd, (char *)0xFFFF, 1); e = errno; t("rd-lastbyte", r, e);
	errno = 0; r = read(fd, (char *)0x0000, 0); e = errno; t("rd-zero", r, e);
	errno = 0; r = write(1, top, 100); e = errno; t("wr-cross-top", r, e);
	errno = 0; r = write(1, (char *)0xFFFF, 0xFFFF); e = errno; t("wr-huge", r, e);
	errno = 0; r = read(fd, (char *)0x8000, 0x7FFF); e = errno; t("rd-ok-large", r > 0, e);
	puts("done");
	return 0;
}
