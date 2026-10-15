/* r807: the *at family with a REAL directory descriptor (apk-tools, GNU coreutils, Go, rm -r all use it) */
#define TNAME "openat"
#include "t.h"
#include <fcntl.h>
#include <stdlib.h>
#include <sys/stat.h>

static int put_at(int dfd, const char *p, const char *text)
{
    int fd = openat(dfd, p, O_WRONLY | O_CREAT | O_TRUNC, 0644);
    if (fd < 0) return -1;
    int n = write(fd, text, strlen(text));
    close(fd);
    return n;
}
static int get_at(int dfd, const char *p, char *buf, int cap)
{
    int fd = openat(dfd, p, O_RDONLY);
    if (fd < 0) return -1;
    int n = read(fd, buf, cap - 1);
    close(fd);
    if (n >= 0) buf[n] = 0;
    return n;
}

int main(void)
{
    char b[128];
    struct stat st;
    mkdir("/tmp/oa", 0755);
    mkdir("/tmp/oa/d", 0755);
    mkdir("/tmp/oa/other", 0755);
    int d = open("/tmp/oa/d", O_RDONLY | O_DIRECTORY);
    CHECKC("open_dir_fd", d >= 0);
    if (d < 0) return 0;
    /* create + read through the directory descriptor */
    errno = 0;
    CHECKC("openat_create_rel", put_at(d, "f1", "hello") == 5);
    CHECK("openat_create_landed", access("/tmp/oa/d/f1", F_OK) == 0, "errno %d", errno);
    CHECK("openat_read_rel", get_at(d, "f1", b, sizeof b) == 5 && !strcmp(b, "hello"), "b=%s", b);
    /* the directory descriptor does not depend on the working directory */
    (void)!chdir("/tmp/oa/other");
    CHECK("openat_ignores_cwd", get_at(d, "f1", b, sizeof b) == 5, "errno %d", errno);
    CHECK("openat_cwd_rel_still_cwd", openat(AT_FDCWD, "f1", O_RDONLY) < 0 && errno == ENOENT, "errno %d", errno);
    (void)!chdir("/");
    /* absolute path: the descriptor is ignored */
    CHECK("openat_abs_ignores_fd", get_at(d, "/tmp/oa/d/f1", b, sizeof b) == 5, "errno %d", errno);
    /* nested names and .. */
    errno = 0; int r = mkdirat(d, "sub", 0755);
    CHECKC("mkdirat_rel", r == 0);
    CHECK("mkdirat_landed", stat("/tmp/oa/d/sub", &st) == 0 && S_ISDIR(st.st_mode), "errno %d", errno);
    CHECK("openat_nested", put_at(d, "sub/f2", "deep") == 4 && get_at(d, "sub/f2", b, sizeof b) == 4, "errno %d", errno);
    CHECK("openat_dotdot", get_at(d, "sub/../f1", b, sizeof b) == 5, "errno %d", errno);
    /* a descriptor of a subdirectory, opened relative to another one */
    int s = openat(d, "sub", O_RDONLY | O_DIRECTORY);
    CHECKC("openat_dir_rel", s >= 0);
    if (s >= 0) {
        CHECK("openat_second_level", get_at(s, "f2", b, sizeof b) == 4 && !strcmp(b, "deep"), "b=%s", b);
        CHECK("openat_second_level_up", get_at(s, "../f1", b, sizeof b) == 5, "errno %d", errno);
        close(s);
    }
    /* dup'd descriptor shares the directory */
    int d2 = dup(d);
    CHECK("openat_dup_fd", d2 >= 0 && get_at(d2, "f1", b, sizeof b) == 5, "errno %d", errno);
    if (d2 >= 0) close(d2);
    /* fstatat */
    errno = 0;
    CHECKC("fstatat_rel", fstatat(d, "f1", &st, 0) == 0 && st.st_size == 5);
    CHECK("fstatat_dir", fstatat(d, "sub", &st, 0) == 0 && S_ISDIR(st.st_mode), "errno %d", errno);
    CHECK("fstatat_missing_enoent", fstatat(d, "nope", &st, 0) < 0 && errno == ENOENT, "errno %d", errno);
    CHECK("fstatat_empty_path", fstatat(d, "", &st, AT_EMPTY_PATH) == 0 && S_ISDIR(st.st_mode), "errno %d", errno);
    CHECK("fstatat_abs", fstatat(d, "/tmp/oa/d/f1", &st, 0) == 0 && st.st_size == 5, "errno %d", errno);
    /* symlinkat / readlinkat / fstatat NOFOLLOW */
    errno = 0; r = symlinkat("f1", d, "lnk");
    CHECKC("symlinkat_rel", r == 0);
    if (r == 0) {
        ssize_t n = readlinkat(d, "lnk", b, sizeof b - 1);
        if (n >= 0) b[n] = 0;
        CHECK("readlinkat_rel", n == 2 && !strcmp(b, "f1"), "n %d b=%s errno %d", (int)n, b, errno);
        CHECK("fstatat_nofollow_link", fstatat(d, "lnk", &st, AT_SYMLINK_NOFOLLOW) == 0 && S_ISLNK(st.st_mode), "errno %d", errno);
        CHECK("fstatat_follow_link", fstatat(d, "lnk", &st, 0) == 0 && S_ISREG(st.st_mode), "errno %d", errno);
        unlinkat(d, "lnk", 0);
    }
    /* linkat, renameat (same directory descriptor for both names) */
    errno = 0; r = linkat(d, "f1", d, "f1h", 0);
    CHECKC("linkat_rel", r == 0);
    errno = 0; r = renameat(d, "f1h", d, "f1r");
    CHECKC("renameat_same_dir", r == 0);
    CHECK("renameat_landed", access("/tmp/oa/d/f1r", F_OK) == 0 && access("/tmp/oa/d/f1h", F_OK) != 0, "errno %d", errno);
    /* one name absolute, one relative to the descriptor */
    errno = 0; r = renameat(d, "f1r", AT_FDCWD, "/tmp/oa/d/f1s");
    CHECKC("renameat_rel_to_abs", r == 0);
    /* faccessat / fchmodat / utimensat */
    errno = 0;
    CHECKC("faccessat_rel", faccessat(d, "f1", R_OK, 0) == 0);
    CHECK("faccessat_missing", faccessat(d, "nope", F_OK, 0) < 0 && errno == ENOENT, "errno %d", errno);
    errno = 0; r = fchmodat(d, "f1", 0600, 0);
    CHECKC("fchmodat_rel", r == 0);
    CHECK("fchmodat_applied", stat("/tmp/oa/d/f1", &st) == 0 && (st.st_mode & 0777) == 0600, "mode %o", st.st_mode & 0777);
    struct timespec ts[2] = { { 1000000, 0 }, { 1000000, 0 } };
    errno = 0; r = utimensat(d, "f1", ts, 0);
    CHECKC("utimensat_rel", r == 0);
    CHECK("utimensat_applied", stat("/tmp/oa/d/f1", &st) == 0 && st.st_mtime == 1000000, "mtime %ld", (long)st.st_mtime);
    /* unlinkat */
    errno = 0; r = unlinkat(d, "f1s", 0);
    CHECKC("unlinkat_file", r == 0);
    CHECK("unlinkat_gone", access("/tmp/oa/d/f1s", F_OK) != 0, "still there");
    errno = 0; r = unlinkat(d, "sub", 0);
    CHECK("unlinkat_dir_without_flag_fails", r < 0 && (errno == EISDIR || errno == EPERM), "r %d errno %d", r, errno);
    unlinkat(d, "sub/f2", 0);
    errno = 0; r = unlinkat(d, "sub", AT_REMOVEDIR);
    CHECKC("unlinkat_removedir", r == 0);
    /* errors */
    errno = 0;
    CHECK("openat_bad_fd_ebadf", openat(999, "x", O_RDONLY) < 0 && errno == EBADF, "errno %d", errno);
    int ff = open("/tmp/oa/d/f1", O_RDONLY);
    errno = 0;
    CHECK("openat_file_fd_enotdir", openat(ff, "x", O_RDONLY) < 0 && errno == ENOTDIR, "errno %d", errno);
    if (ff >= 0) close(ff);
    /* open O_DIRECTORY on a plain file */
    errno = 0;
    CHECK("openat_odirectory_on_file", openat(d, "f1", O_RDONLY | O_DIRECTORY) < 0 && errno == ENOTDIR, "errno %d", errno);
    /* the kernel remembers a path per directory descriptor: many at once, then churn (no leak, no stale path) */
    int many[40], k, okm = 1;
    for (k = 0; k < 40; k++) many[k] = open("/tmp/oa/d", O_RDONLY | O_DIRECTORY);
    for (k = 0; k < 40; k++) if (many[k] < 0 || get_at(many[k], "f1", b, sizeof b) != 5) okm = 0;
    for (k = 0; k < 40; k++) if (many[k] >= 0) close(many[k]);
    CHECK("dirfd_many_open", okm, "errno %d", errno);
    int okc = 1;
    for (k = 0; k < 600; k++) {
        int t = open(k & 1 ? "/tmp/oa/d" : "/tmp/oa/other", O_RDONLY | O_DIRECTORY);
        if (t < 0) { okc = 0; break; }
        if (!(k & 1) && fstatat(t, "f1", &st, 0) == 0) okc = 0; /* other/ has no f1: a stale path would find one */
        if ((k & 1) && fstatat(t, "f1", &st, 0) != 0) okc = 0;
        close(t);
    }
    CHECK("dirfd_churn_600", okc, "k %d errno %d", k, errno);
    close(d);
    CHECK("closed_fd_ebadf", openat(d, "f1", O_RDONLY) < 0 && errno == EBADF, "errno %d", errno);
    return 0;
}
