/* fdformat [-n] /dev/fdN [tracks]: low-level format of a 2DD disk (16 x 256 bytes per track),
   then read the filesystem area back (unless -n). Super-user only. */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <fcntl.h>

#define FDFORMAT 0x4600	/* + physical track number (cylinder * 2 + side) */

int main(int argc, char *argv[])
{
    static char blk[512];
    int verify = 1, tracks = 160, fd, t, bad = 0;
    unsigned n;

    if (argc > 1 && !strcmp(argv[1], "-n")) {
        verify = 0;
        argc--;
        argv++;
    }
    if (argc < 2 || argc > 3) {
        write(2, "usage: fdformat [-n] /dev/fdN [tracks]\n", 39);
        return 1;
    }
    if (argc == 3) {
        tracks = atoi(argv[2]);
        if (tracks < 1 || tracks > 160) {
            write(2, "fdformat: tracks must be 1-160\n", 31);
            return 1;
        }
    }
    if ((fd = open(argv[1], O_RDWR)) < 0) {
        perror(argv[1]);
        return 1;
    }
    for (t = 0; t < tracks; t++) {
        printf("\rformat track %d/%d ", t + 1, tracks);
        fflush(stdout);
        if (ioctl(fd, FDFORMAT + t, 0) < 0) {
            printf("\n");
            perror("fdformat");
            return 1;
        }
    }
    printf("\rformatted %d tracks      \n", tracks);
    if (verify) {
        /* filesystem blocks start at record 256 (cylinder 8) */
        lseek(fd, 0L, SEEK_SET);
        for (n = 0; n < 1152 && (n * 2 + 256) / 32 < (unsigned)tracks / 2; n++) {
            if (read(fd, blk, 512) != 512) {
                printf("verify: block %u unreadable\n", n);
                bad++;
                lseek(fd, (long)(n + 1) * 512L, SEEK_SET);
            }
        }
        if (bad) {
            printf("%d bad blocks\n", bad);
            return 1;
        }
        printf("verify ok\n");
    }
    close(fd);
    return 0;
}
