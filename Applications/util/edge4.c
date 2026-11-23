#include <stdio.h>
#include <unistd.h>
#include <fcntl.h>
#include <errno.h>
#include <string.h>

static char blk[4096];

int main(void)
{
	int fd, n = 0, i, e;
	char name[32];

	memset(blk, 'z', sizeof(blk));
	fd = open("/tmp/fill", O_WRONLY | O_CREAT | O_TRUNC, 0644);
	printf("fill fd %d\n", fd);
	for (;;) {
		i = (int)write(fd, blk, sizeof(blk));
		if (i != (int)sizeof(blk))
			break;
		n++;
		if (n % 50 == 0)
			printf("n=%d\n", n);
	}
	e = errno;
	printf("fill chunks %d last %d e%d\n", n, i, e);
	close(fd);
	n = 0;
	for (;;) {
		sprintf(name, "/tmp/f%d", n);
		fd = open(name, O_WRONLY | O_CREAT, 0644);
		if (fd < 0)
			break;
		close(fd);
		n++;
		if (n >= 300)
			break;
	}
	e = errno;
	printf("files %d e%d\n", n, fd < 0 ? e : 0);
	for (i = 0; i < n; i++) {
		sprintf(name, "/tmp/f%d", i);
		unlink(name);
	}
	printf("unlink fill %d\n", unlink("/tmp/fill"));
	fd = open("/tmp/after", O_WRONLY | O_CREAT, 0644);
	i = (int)write(fd, blk, sizeof(blk));
	printf("after write %d\n", i);
	close(fd);
	unlink("/tmp/after");
	return 0;
}
