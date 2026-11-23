/* fdcopy SRC DST [blocks]: copy 512-byte blocks between devices or files (default 1280 = a whole
   2DD disk when used with the whole-disk nodes /dev/fdw0, /dev/fdw1: boot area included). */
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
#include <fcntl.h>

int main(int argc, char *argv[])
{
    static char blk[512];
    int in, out, n;
    unsigned b, count = 1280;

    if (argc < 3 || argc > 4) {
        write(2, "usage: fdcopy src dst [blocks]\n", 31);
        return 1;
    }
    if (argc == 4)
        count = atoi(argv[3]);
    if ((in = open(argv[1], O_RDONLY)) < 0) {
        perror(argv[1]);
        return 1;
    }
    if ((out = open(argv[2], O_WRONLY | O_CREAT, 0644)) < 0) {
        perror(argv[2]);
        return 1;
    }
    for (b = 0; b < count; b++) {
        if ((n = read(in, blk, 512)) != 512) {
            printf("\nfdcopy: read error at block %u\n", b);
            return 1;
        }
        if (write(out, blk, 512) != 512) {
            printf("\nfdcopy: write error at block %u\n", b);
            return 1;
        }
        if (!(b & 15)) {
            printf("\r%u/%u ", b, count);
            fflush(stdout);
        }
    }
    printf("\rcopied %u blocks   \n", count);
    close(in);
    sync();
    return close(out) ? 1 : 0;
}
