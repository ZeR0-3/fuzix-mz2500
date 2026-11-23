#include <stdio.h>
#include <fcntl.h>
#include <unistd.h>
#include <errno.h>
#include <sys/file.h>
int main(void)
{
	int a = open("/tmp/fl", O_RDWR|O_CREAT, 0644);
	int b = open("/tmp/fl", O_RDWR);
	printf("a EX=%d\n", flock(a, LOCK_EX));
	printf("a EX again=%d\n", flock(a, LOCK_EX));
	printf("b EX|NB=%d e=%d\n", flock(b, LOCK_EX|LOCK_NB), errno);
	printf("b SH|NB=%d e=%d\n", flock(b, LOCK_SH|LOCK_NB), errno);
	printf("a SH=%d\n", flock(a, LOCK_SH));
	printf("b SH|NB=%d\n", flock(b, LOCK_SH|LOCK_NB));
	printf("b EX|NB=%d e=%d\n", flock(b, LOCK_EX|LOCK_NB), errno);
	printf("a UN=%d\n", flock(a, LOCK_UN));
	printf("b EX|NB=%d\n", flock(b, LOCK_EX|LOCK_NB));
	printf("b UN=%d\n", flock(b, LOCK_UN));
	printf("bad=%d\n", flock(a, 7));
	return 0;
}
