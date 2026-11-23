#include <stdio.h>
#include <unistd.h>
#include <syscalls.h>

int main(int argc, char *argv[])
{
    if (argc != 3) {
        write(2, "usage: ln src dst\n", 18);
        return 1;
    }
    if (link(argv[1], argv[2])) {
        perror("ln");
        return 1;
    }
    return 0;
}
