#include <stdio.h>
#include <unistd.h>
#include <fcntl.h>
#include <errno.h>
#include <signal.h>
#include <string.h>
#include <sys/wait.h>

int main(void)
{
	int i, n = 0, fds[2], pid, st;
	char c = 'x', b[8];

	for (i = 0; i < 40; i++) {
		if (open("/etc/passwd", O_RDONLY) < 0)
			break;
		n++;
	}
	printf("open_max %d e%d\n", n, errno);
	for (i = 3; i < 40; i++) close(i);

	signal(SIGPIPE, SIG_IGN);
	printf("pipe %d\n", pipe(fds));
	printf("w1 %d\n", (int)write(fds[1], &c, 1));
	printf("r1 %d\n", (int)read(fds[0], b, 8));
	close(fds[1]);
	printf("r_eof %d\n", (int)read(fds[0], b, 8));
	close(fds[0]);
	pipe(fds);
	close(fds[0]);
	errno = 0;
	i = (int)write(fds[1], &c, 1);
	printf("w_epipe %d e%d\n", i, errno);
	close(fds[1]);

	pid = fork();
	if (pid == 0)
		_exit(42);
	i = waitpid(pid, &st, 0);
	printf("wait %d st%x\n", i == pid, st);
	errno = 0;
	i = wait(&st);
	printf("wait_none %d e%d\n", i, errno);
	pid = fork();
	if (pid == 0) {
		signal(SIGTERM, SIG_DFL);
		pause();
		_exit(0);
	}
	sleep(1);
	i = kill(pid, SIGTERM);
	printf("kill %d\n", i);
	waitpid(pid, &st, 0);
	printf("sig %x\n", st);
	errno = 0;
	i = kill(9999, SIGTERM);
	printf("kill_bad %d e%d\n", i, errno);
	return 0;
}
