#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
#include <errno.h>
#include <signal.h>
#include <sys/wait.h>

/* fork until failure, then reap everything and fork again */
int main(void)
{
	int n = 0, e, i, st, ok = 0;
	pid_t p, pids[110];
	for (;;) {
		p = fork();
		if (p == 0) {
			for (;;)
				pause();
		}
		if (p < 0)
			break;
		pids[n++] = p;
		if (n > 100)
			break;
	}
	e = errno;
	printf("forked %d err %d\n", n, e);
	for (i = 0; i < n; i++)
		kill(pids[i], SIGKILL);
	for (i = 0; i < n; i++)
		if (wait(&st) > 0)
			ok++;
	printf("reaped %d of %d\n", ok, n);
	p = fork();
	if (p == 0)
		_exit(7);
	e = errno;
	wait(&st);
	printf("again pid %d st %d err %d\n", p > 0, (st >> 8) & 0xff, e);
	puts("done");
	return 0;
}
