/* named pipes: mknod(S_IFIFO) / mknodat / mkfifo, stat + readdir type, blocking and non-blocking open, data across fork, O_RDWR.
 * busybox mkfifo and shell `mkfifo` need exactly this. */
#define TNAME "fifo"
#include "t.h"
#include <dirent.h>
#include <fcntl.h>
#include <stdlib.h>
#include <sys/stat.h>
#include <sys/syscall.h>
#include <sys/types.h>
#include <sys/wait.h>
#include <unistd.h>

#define N_MKNODAT 259
#define FIFO_A "/tmp/ffa"
#define FIFO_B "/tmp/ffb"
#define FIFO_C "/tmp/ffc"
#define SETTLE_US 150000

static int dirent_type(const char *dir, const char *name)
{
    DIR *d = opendir(dir);
    if (!d) return -1;
    int type = -2;
    struct dirent *e;
    while ((e = readdir(d)) != NULL)
        if (!strcmp(e->d_name, name)) type = e->d_type;
    closedir(d);
    return type;
}

static void check_creation(void)
{
    struct stat st;
    long r;
    umask(0);
    unlink(FIFO_A); unlink(FIFO_B); unlink(FIFO_C); unlink("/tmp/ffreg");

    errno = 0; r = mknod(FIFO_A, S_IFIFO | 0600, 0);
    CHECKC("mknod_fifo", r == 0);
    errno = 0; r = stat(FIFO_A, &st);
    CHECK("stat_is_fifo", r == 0 && S_ISFIFO(st.st_mode) && !S_ISREG(st.st_mode), "r=%ld mode=%o", r, (unsigned)st.st_mode);
    CHECK("stat_mode_bits", r == 0 && (st.st_mode & 07777) == 0600, "mode=%o", (unsigned)st.st_mode);
    errno = 0; r = mknod(FIFO_A, S_IFIFO | 0600, 0);
    CHECK("mknod_exists", r < 0 && errno == EEXIST, "r=%ld errno=%d", r, errno);
    errno = 0; r = mkfifo(FIFO_B, 0644);
    CHECKC("mkfifo_libc", r == 0);
    errno = 0; r = syscall(N_MKNODAT, (long)AT_FDCWD, FIFO_C, (long)(S_IFIFO | 0640), 0L);
    CHECKC("mknodat_fifo", r == 0);
    errno = 0; r = mknod("/tmp/ffreg", S_IFREG | 0644, 0);
    CHECKC("mknod_regular", r == 0);
    CHECK("regular_is_regular", stat("/tmp/ffreg", &st) == 0 && S_ISREG(st.st_mode), "mode=%o", (unsigned)st.st_mode);
    errno = 0; r = mknod("/tmp/ffchr", S_IFCHR | 0600, 0);
    CHECK("mknod_char_refused", r < 0 && errno == EPERM, "r=%ld errno=%d", r, errno);
    errno = 0; r = mknod("/tmp/nodir/ff", S_IFIFO | 0600, 0);
    CHECK("mknod_missing_parent", r < 0 && errno == ENOENT, "r=%ld errno=%d", r, errno);
    CHECK("readdir_type_fifo", dirent_type("/tmp", "ffa") == DT_FIFO, "type=%d", dirent_type("/tmp", "ffa"));
    CHECK("readdir_type_regular", dirent_type("/tmp", "ffreg") == DT_REG, "type=%d", dirent_type("/tmp", "ffreg"));
    errno = 0; r = chmod(FIFO_A, 0644);
    CHECK("chmod_keeps_fifo", r == 0 && stat(FIFO_A, &st) == 0 && S_ISFIFO(st.st_mode) && (st.st_mode & 07777) == 0644,
          "r=%ld mode=%o", r, (unsigned)st.st_mode);
}

static void check_nonblocking(void)
{
    char b[8];
    errno = 0;
    int w = open(FIFO_A, O_WRONLY | O_NONBLOCK);
    CHECK("nb_write_open_no_reader_enxio", w < 0 && errno == ENXIO, "fd=%d errno=%d", w, errno);
    if (w >= 0) close(w);
    errno = 0;
    int r = open(FIFO_A, O_RDONLY | O_NONBLOCK);
    CHECKC("nb_read_open_ok", r >= 0);
    if (r < 0) return;
    errno = 0;
    ssize_t n = read(r, b, sizeof b);
    CHECK("nb_read_no_writer_eof", n == 0, "n=%zd errno=%d", n, errno);
    errno = 0;
    w = open(FIFO_A, O_WRONLY | O_NONBLOCK);
    CHECKC("nb_write_open_with_reader", w >= 0);
    if (w >= 0) {
        n = write(w, "abc", 3);
        CHECK("nb_write_data", n == 3, "n=%zd errno=%d", n, errno);
        n = read(r, b, sizeof b);
        CHECK("nb_read_data", n == 3 && !memcmp(b, "abc", 3), "n=%zd", n);
        errno = 0;
        n = read(r, b, sizeof b);
        CHECK("nb_read_empty_eagain", n < 0 && errno == EAGAIN, "n=%zd errno=%d", n, errno);
        struct stat st;
        CHECK("fstat_is_fifo", fstat(w, &st) == 0 && S_ISFIFO(st.st_mode), "mode=%o", (unsigned)st.st_mode);
        close(w);
    }
    close(r);
}

static void check_blocking_roundtrip(void)
{
    char b[16];
    pid_t child = fork();
    if (child == 0) {
        usleep(SETTLE_US);
        int w = open(FIFO_B, O_WRONLY);
        if (w < 0) _exit(2);
        if (write(w, "ping", 4) != 4) _exit(3);
        close(w);
        _exit(0);
    }
    errno = 0;
    int r = open(FIFO_B, O_RDONLY);
    CHECKC("block_read_open_waits_for_writer", r >= 0);
    if (r < 0) { if (child > 0) waitpid(child, NULL, 0); return; }
    ssize_t n = read(r, b, sizeof b);
    CHECK("block_read_data", n == 4 && !memcmp(b, "ping", 4), "n=%zd errno=%d", n, errno);
    n = read(r, b, sizeof b);
    CHECK("block_read_eof_after_writer_close", n == 0, "n=%zd errno=%d", n, errno);
    close(r);
    int status = 0;
    waitpid(child, &status, 0);
    CHECK("block_child_ok", WIFEXITED(status) && WEXITSTATUS(status) == 0, "status=%d", status);

    child = fork();
    if (child == 0) {
        usleep(SETTLE_US);
        int rd = open(FIFO_B, O_RDONLY);
        if (rd < 0) _exit(2);
        ssize_t got = read(rd, b, sizeof b);
        _exit(got == 4 && !memcmp(b, "pong", 4) ? 0 : 3);
    }
    errno = 0;
    int w = open(FIFO_B, O_WRONLY);
    CHECKC("block_write_open_waits_for_reader", w >= 0);
    if (w >= 0) {
        n = write(w, "pong", 4);
        CHECK("block_write_data", n == 4, "n=%zd errno=%d", n, errno);
        close(w);
    }
    status = 0;
    waitpid(child, &status, 0);
    CHECK("block_reader_child_ok", WIFEXITED(status) && WEXITSTATUS(status) == 0, "status=%d", status);
}

static void check_readwrite(void)
{
    char b[8];
    errno = 0;
    int f = open(FIFO_C, O_RDWR | O_NONBLOCK);
    CHECKC("rdwr_open", f >= 0);
    if (f < 0) return;
    ssize_t n = write(f, "xyz", 3);
    CHECK("rdwr_write", n == 3, "n=%zd errno=%d", n, errno);
    n = read(f, b, sizeof b);
    CHECK("rdwr_read_back", n == 3 && !memcmp(b, "xyz", 3), "n=%zd errno=%d", n, errno);
    close(f);
    errno = 0;
    int w = open(FIFO_C, O_WRONLY | O_NONBLOCK);
    CHECK("rdwr_closed_releases_pipe", w < 0 && errno == ENXIO, "fd=%d errno=%d", w, errno);
    if (w >= 0) close(w);
}

static void check_cleanup(void)
{
    struct stat st;
    errno = 0;
    CHECK("unlink_fifo", unlink(FIFO_A) == 0 && stat(FIFO_A, &st) < 0 && errno == ENOENT, "errno=%d", errno);
    unlink(FIFO_B); unlink(FIFO_C); unlink("/tmp/ffreg");
    int fresh = mknod(FIFO_A, S_IFIFO | 0600, 0);
    CHECK("recreate_after_unlink", fresh == 0 && stat(FIFO_A, &st) == 0 && S_ISFIFO(st.st_mode), "fresh=%d", fresh);
    unlink(FIFO_A);
}

int main(void)
{
    check_creation();
    check_nonblocking();
    check_blocking_roundtrip();
    check_readwrite();
    check_cleanup();
    return 0;
}
