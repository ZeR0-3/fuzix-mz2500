#include <stdio.h>
#include <unistd.h>
#include <signal.h>
#include <sys/wait.h>

static void h(int s) { _exit(60 + s); }

static void t(const char *n, int sig, int mode)
{
	int pid, st = -1, i;
	pid = fork();
	if (pid == 0) {
		if (mode == 1) signal(sig, h);
		if (mode == 2) signal(sig, SIG_IGN);
		for (;;) pause();
	}
	sleep(1);
	kill(pid, sig);
	sleep(1);
	if (mode == 2) kill(pid, SIGKILL);
	i = waitpid(pid, &st, 0);
	printf("%s r%d st%x\n", n, i == pid, st);
}

int main(void)
{
	t("term_dfl", SIGTERM, 0);
	t("kill", SIGKILL, 0);
	t("int_dfl", SIGINT, 0);
	t("term_hnd", SIGTERM, 1);
	t("term_ign", SIGTERM, 2);
	return 0;
}
