#include <stdio.h>
#include <unistd.h>
#include <string.h>
static void p(const char *s) { write(1, s, strlen(s)); }
int main(void)
{
	p("\033E");
	p("ABC\tD\b\bX\r\nline2\r\n");
	p("\033Y%*"); /* row 5 (0x25-0x20), col 10 (0x2a-0x20) */
	p("Z");
	p("\033A\033C\033C?");
	p("\033B\033D\033D\033D!");
	p("\033Y#!KILL-ME-HERE\033Y#(\033K");
	p("\033Y+ 12345678\033Y+\"\033J");
	p("\033Y7 bottom\r\n\r\nscrolled");
	p("\033H<H>");
	p("\033Y2 1\033I");
	p("\033Y8 end");
	return 0;
}
