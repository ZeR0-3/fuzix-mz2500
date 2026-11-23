#include <stdio.h>
#include <unistd.h>
#include <fcntl.h>
#include <errno.h>
#include <string.h>
#include <sys/ioctl.h>
#include <stdlib.h>

static void r(const char *n, int v)
{
	printf("%s %d e%d\n", n, v, v < 0 ? errno : 0);
}

int main(void)
{
	int fd;
	char buf[64];
	static char big[600];

	fd = open("/etc/passwd", O_RDONLY);
	r("open", fd);
	errno = 0; r("read_null", read(fd, (void *)0, 10));
	errno = 0; r("read_hi", read(fd, (void *)0xFFF0, 100));
	errno = 0; r("read_ok", read(fd, buf, 8));
	errno = 0; r("write_null", write(1, (void *)0, 4));
	errno = 0; r("open_null", open((char *)0, O_RDONLY));
	errno = 0; r("open_hi", open((char *)0xFFFE, O_RDONLY));
	errno = 0; r("ioctl_bad", ioctl(fd, 0x1234, buf));
	errno = 0; r("lseek_bad", (int)lseek(fd, 0, 9));
	errno = 0; r("close99", close(99));
	errno = 0; r("dup99", dup(99));
	errno = 0; r("dup2_99", dup2(fd, 99));
	errno = 0; r("stat_null", stat((char *)0, (void *)buf));
	memset(big, 'a', sizeof(big) - 1);
	{
		char *av[3];
		av[0] = "echo"; av[1] = big; av[2] = 0;
		errno = 0; r("exec_big", execv("/bin/echo", av));
	}
	errno = 0; r("exec_none", execv("/nonexistent", (char **)0));
	errno = 0; r("mkdir_exist", mkdir("/tmp", 0755));
	errno = 0; r("unlink_dir", unlink("/tmp"));
	errno = 0; r("rmdir_file", rmdir("/etc/passwd"));
	errno = 0; r("chdir_file", chdir("/etc/passwd"));
	errno = 0; r("open_dir_w", open("/tmp", O_WRONLY));
	errno = 0; r("mount_bad", mount("/dev/hdz", "/tmp", 0));
	return 0;
}
