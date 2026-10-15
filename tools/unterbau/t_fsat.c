/* the *at family glibc/Go/newer musl use (openat 257 ... renameat2 316). Osum has no directory descriptors: AT_FDCWD or an absolute path works,
 * a relative path with a real dirfd is -ENOSYS (written down in kernel/sys/sys.fi, lc_at). */
#define TNAME "fsat"
#include "t.h"
#include <fcntl.h>
#include <stdlib.h>
#include <sys/stat.h>
#include <sys/syscall.h>
#include <unistd.h>

#ifndef AT_EMPTY_PATH
#define AT_EMPTY_PATH 0x1000
#endif
#ifndef AT_REMOVEDIR
#define AT_REMOVEDIR 0x200
#endif
#ifndef AT_SYMLINK_NOFOLLOW
#define AT_SYMLINK_NOFOLLOW 0x100
#endif

/* x86-64 numbers, spelled out so that the test does not depend on the libc headers */
#define N_OPENAT 257
#define N_MKDIRAT 258
#define N_NEWFSTATAT 262
#define N_UNLINKAT 263
#define N_RENAMEAT 264
#define N_LINKAT 265
#define N_SYMLINKAT 266
#define N_READLINKAT 267
#define N_RENAMEAT2 316

#define CWD ((long)AT_FDCWD)

static int put(const char *p, const char *text)
{
    int fd = open(p, O_WRONLY | O_CREAT | O_TRUNC, 0644);
    if (fd < 0) return -1;
    int n = write(fd, text, strlen(text));
    close(fd);
    return n;
}

int main(void)
{
    char b[128];
    struct stat st;
    long r;

    errno = 0; r = syscall(N_MKDIRAT, CWD, "/tmp/fat", 0755L);
    CHECKC("mkdirat_cwd", r == 0 || (r < 0 && errno == EEXIST));

    errno = 0; long fd = syscall(N_OPENAT, CWD, "/tmp/fat/a", (long)(O_WRONLY | O_CREAT | O_TRUNC), 0644L);
    CHECKC("openat_create", fd >= 0);
    if (fd >= 0) { (void)!write((int)fd, "hello", 5); close((int)fd); }

    errno = 0; fd = syscall(N_OPENAT, CWD, "/tmp/fat/a", (long)O_RDONLY, 0L);
    CHECKC("openat_read", fd >= 0);
    int n = -1;
    if (fd >= 0) { n = read((int)fd, b, sizeof b - 1); close((int)fd); if (n >= 0) b[n] = 0; }
    CHECK("openat_content", n == 5 && !strcmp(b, "hello"), "n=%d", n);

    errno = 0; fd = syscall(N_OPENAT, 12345L, "/tmp/fat/a", (long)O_RDONLY, 0L);
    CHECK("openat_absolute_ignores_dirfd", fd >= 0, "errno=%d", errno);
    if (fd >= 0) close((int)fd);

    errno = 0; fd = syscall(N_OPENAT, (long)0xFFFFFF9CUL, "/tmp/fat/a", (long)O_RDONLY, 0L);
    CHECK("openat_fdcwd_zero_extended", fd >= 0, "errno=%d", errno);
    if (fd >= 0) close((int)fd);

    errno = 0; fd = syscall(N_OPENAT, 12345L, "relative-name", (long)O_RDONLY, 0L);
    CHECK("openat_relative_with_bad_dirfd_ebadf", fd < 0 && errno == EBADF, "fd=%ld errno=%d", fd, errno);

    errno = 0; fd = syscall(N_OPENAT, CWD, "/tmp/fat/none", (long)O_RDONLY, 0L);
    CHECK("openat_missing_enoent", fd < 0 && errno == ENOENT, "fd=%ld errno=%d", fd, errno);

    memset(&st, 0, sizeof st);
    errno = 0; r = syscall(N_NEWFSTATAT, CWD, "/tmp/fat/a", &st, 0L);
    CHECKC("newfstatat_path", r == 0 && st.st_size == 5);
    CHECK("newfstatat_regular", r == 0 && S_ISREG(st.st_mode), "mode=%o", (unsigned)st.st_mode);

    fd = open("/tmp/fat/a", O_RDONLY);
    memset(&st, 0, sizeof st);
    errno = 0; r = syscall(N_NEWFSTATAT, fd, "", &st, (long)AT_EMPTY_PATH);
    CHECKC("newfstatat_empty_path", r == 0 && st.st_size == 5);
    if (fd >= 0) close((int)fd);

    errno = 0; r = syscall(N_SYMLINKAT, "/tmp/fat/a", CWD, "/tmp/fat/ln");
    CHECKC("symlinkat", r == 0);
    n = (int)syscall(N_READLINKAT, CWD, "/tmp/fat/ln", b, (long)sizeof b - 1);
    if (n >= 0) b[n] = 0;
    CHECK("readlinkat", n == 10 && !strcmp(b, "/tmp/fat/a"), "n=%d b=%s", n, n >= 0 ? b : "?");
    memset(&st, 0, sizeof st);
    errno = 0; r = syscall(N_NEWFSTATAT, CWD, "/tmp/fat/ln", &st, (long)AT_SYMLINK_NOFOLLOW);
    CHECK("newfstatat_nofollow_is_link", r == 0 && S_ISLNK(st.st_mode), "r=%ld mode=%o errno=%d", r, (unsigned)st.st_mode, errno);

    errno = 0; r = syscall(N_RENAMEAT, CWD, "/tmp/fat/a", CWD, "/tmp/fat/b");
    CHECKC("renameat", r == 0);
    CHECK("renameat_source_gone", access("/tmp/fat/a", F_OK) != 0, "a still there");
    CHECK("renameat_target_there", access("/tmp/fat/b", F_OK) == 0, "b missing");

    put("/tmp/fat/c", "x");
    errno = 0; r = syscall(N_RENAMEAT2, CWD, "/tmp/fat/c", CWD, "/tmp/fat/d", 0L);
    CHECKC("renameat2_flags0", r == 0);
    errno = 0; r = syscall(N_RENAMEAT2, CWD, "/tmp/fat/d", CWD, "/tmp/fat/e", 1L);
    CHECK("renameat2_noreplace_einval", r < 0 && errno == EINVAL, "r=%ld errno=%d", r, errno);

    errno = 0; r = syscall(N_LINKAT, CWD, "/tmp/fat/d", CWD, "/tmp/fat/d2", 0L);
    CHECKC("linkat", r == 0);

    errno = 0; r = syscall(N_UNLINKAT, CWD, "/tmp/fat/d2", 0L);
    CHECKC("unlinkat_file", r == 0);
    CHECK("unlinkat_file_gone", access("/tmp/fat/d2", F_OK) != 0, "d2 still there");

    errno = 0; r = syscall(N_MKDIRAT, CWD, "/tmp/fat/sub", 0755L);
    CHECKC("mkdirat_sub", r == 0);
    errno = 0; r = syscall(N_UNLINKAT, CWD, "/tmp/fat/sub", (long)AT_REMOVEDIR);
    CHECKC("unlinkat_removedir", r == 0);
    CHECK("unlinkat_removedir_gone", access("/tmp/fat/sub", F_OK) != 0, "sub still there");

    /* cleanup */
    unlink("/tmp/fat/b"); unlink("/tmp/fat/d"); unlink("/tmp/fat/e"); unlink("/tmp/fat/ln");
    rmdir("/tmp/fat");
    return 0;
}
