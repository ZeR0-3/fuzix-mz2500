#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
#include <fcntl.h>
#include <errno.h>
#include <string.h>

/* inode exhaustion: create empty files until failure, then recover */
static char name[32];
int main(void)
{
	int n = 0, e, fd, i, ok = 0;
	for (;;) {
		sprintf(name, "/tmp/f%d", n);
		fd = open(name, O_WRONLY | O_CREAT, 0600);
		if (fd < 0)
			break;
		close(fd);
		n++;
		if (n % 100 == 0)
			printf("n=%d\n", n);
		if (n > 3000)
			break;
	}
	e = errno;
	printf("created %d err %d\n", n, e);
	for (i = 0; i < n; i++) {
		sprintf(name, "/tmp/f%d", i);
		if (unlink(name) == 0)
			ok++;
	}
	printf("unlinked %d of %d\n", ok, n);
	fd = open("/tmp/again", O_WRONLY | O_CREAT, 0600);
	e = errno;
	printf("again fd %d err %d\n", fd >= 0, e);
	if (fd >= 0) {
		close(fd);
		unlink("/tmp/again");
	}
	puts("done");
	return 0;
}
