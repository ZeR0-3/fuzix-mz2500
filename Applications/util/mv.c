#include <stdio.h>
#include <string.h>
#include <unistd.h>
#include <syscalls.h>
#include <sys/stat.h>
#include <fcntl.h>
#include <errno.h>
#include <dirent.h>

static int copyfile(const char *from, const char *to, mode_t mode)
{
    static char blk[512];
    int in, out, n;

    if ((in = open(from, O_RDONLY)) < 0)
        return -1;
    if ((out = open(to, O_WRONLY | O_CREAT | O_TRUNC, mode & 07777)) < 0) {
        close(in);
        return -1;
    }
    while ((n = read(in, blk, sizeof(blk))) > 0)
        if (write(out, blk, n) != n) {
            n = -1;
            break;
        }
    close(in);
    if (close(out) < 0)
        n = -1;
    return n < 0 ? -1 : 0;
}


/* Copy a directory tree (regular files and directories only), then remove the source. Returns 0 on success. */
static int movetree(const char *from, const char *to)
{
    DIR *d;
    struct dirent *e;
    struct stat st;
    char f[80], t[80];
    int fl = strlen(from), tl = strlen(to), r = 0, n;

    if (stat(from, &st) || mkdir(to, st.st_mode & 07777))
        return -1;
    if (!(d = opendir(from)))
        return -1;
    while (!r && (e = readdir(d)) != NULL) {
        if (!strcmp(e->d_name, ".") || !strcmp(e->d_name, ".."))
            continue;
        n = strlen(e->d_name);
        if (fl + n + 2 > sizeof(f) || tl + n + 2 > sizeof(t)) {
            errno = ENAMETOOLONG;
            r = -1;
            break;
        }
        strcpy(f, from); f[fl] = '/'; strcpy(f + fl + 1, e->d_name);
        strcpy(t, to); t[tl] = '/'; strcpy(t + tl + 1, e->d_name);
        if (stat(f, &st)) {
            r = -1;
        } else if ((st.st_mode & S_IFMT) == S_IFDIR) {
            r = movetree(f, t);
        } else if ((st.st_mode & S_IFMT) == S_IFREG) {
            if (!(r = copyfile(f, t, st.st_mode)))
                r = unlink(f);
        } else {
            errno = EXDEV;
            r = -1;
        }
    }
    closedir(d);
    return r ? r : rmdir(from);
}

/* mv src dst: rename(); across filesystems copy + unlink (regular files only). If dst is a directory, use its basename. */
int main(int argc, char *argv[])
{
    static char buf[80];
    struct stat st;
    char *dst = argv[2], *b;

    if (argc != 3) {
        write(2, "usage: mv src dst\n", 18);
        return 1;
    }
    if (stat(dst, &st) == 0 && (st.st_mode & S_IFMT) == S_IFDIR) {
        b = strrchr(argv[1], '/');
        b = b ? b + 1 : argv[1];
        if (strlen(dst) + strlen(b) + 2 > sizeof(buf)) {
            write(2, "mv: name too long\n", 18);
            return 1;
        }
        strcpy(buf, dst);
        strcat(buf, "/");
        strcat(buf, b);
        dst = buf;
    }
    if (rename(argv[1], dst)) {
        /* different filesystem: copy the file, then remove the original */
        if (errno == EXDEV && stat(argv[1], &st) == 0 && (st.st_mode & S_IFMT) == S_IFREG) {
            if (copyfile(argv[1], dst, st.st_mode)) {
                perror("mv");
                unlink(dst);
                return 1;
            }
            if (unlink(argv[1])) {
                perror("mv");
                return 1;
            }
            return 0;
        }
        if (errno == EXDEV && stat(argv[1], &st) == 0 && (st.st_mode & S_IFMT) == S_IFDIR) {
            if (movetree(argv[1], dst)) {
                perror("mv");
                return 1;
            }
            return 0;
        }
        perror("mv");
        return 1;
    }
    return 0;
}
