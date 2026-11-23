#include <stdio.h>
#include <fcntl.h>
#include <unistd.h>
#include <string.h>
int main(void)
{
	char b[100];
	int i, fd = open("/tmp/ft", O_RDWR|O_CREAT|O_TRUNC, 0644);
	off_t e;
	memset(b, 'x', 100);
	for (i = 0; i < 10; i++) write(fd, b, 100);
	printf("ft1=%d\n", ftruncate(fd, 300));
	e = lseek(fd, 0, SEEK_END);
	printf("size=%ld\n", (long)e);
	printf("ft2=%d\n", ftruncate(fd, 700));
	e = lseek(fd, 0, SEEK_END);
	printf("size=%ld\n", (long)e);
	printf("getfl=%x\n", fcntl(fd, F_GETFL));
	printf("setfl=%d\n", fcntl(fd, F_SETFL, O_APPEND));
	printf("getfl=%x\n", fcntl(fd, F_GETFL));
	printf("getfd=%x\n", fcntl(fd, F_GETFD));
	printf("setfd=%d\n", fcntl(fd, F_SETFD, FD_CLOEXEC));
	printf("getfd=%x\n", fcntl(fd, F_GETFD));
	printf("bad=%d\n", fcntl(fd, 99, 0));
	printf("dupfd=%d\n", fcntl(fd, F_DUPFD, 5));
	printf("badfd=%d\n", fcntl(77, F_GETFL));
	close(fd);
	fd = open("/tmp/ft", O_RDONLY);
	printf("rdonly ft=%d\n", ftruncate(fd, 10));
	return 0;
}
