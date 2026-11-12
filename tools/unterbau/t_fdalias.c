#define TNAME "fdalias"
#include "t.h"
#include <fcntl.h>
#include <stdio.h>
#include <sys/stat.h>

static int read_all(int fd, char *out, int max)
{
    int n = read(fd, out, max - 1);
    out[n > 0 ? n : 0] = 0;
    return n;
}

static void check_std_alias(const char *name, const char *path, int target, int writing)
{
    int p[2];
    char buf[32];
    if (pipe(p) < 0) {
        FAIL(name, "pipe errno=%d", errno);
        return;
    }
    int saved = dup(target);
    dup2(writing ? p[1] : p[0], target);
    int fd = open(path, writing ? O_WRONLY : O_RDONLY);
    int saved_errno = errno;
    if (fd >= 0 && writing)
        (void)!write(fd, "alias", 5);
    if (!writing)
        (void)!write(p[1], "alias", 5);
    int n = -1;
    if (fd >= 0)
        n = read_all(writing ? p[0] : fd, buf, sizeof buf);
    dup2(saved, target);
    close(saved);
    if (fd >= 0)
        close(fd);
    close(p[0]);
    close(p[1]);
    CHECK(name, fd >= 0 && n == 5 && !strcmp(buf, "alias"), "fd=%d errno=%d n=%d", fd, saved_errno, n);
}

static void check_numbered(const char *name, const char *dir)
{
    char path[64], buf[32] = "";
    int src = open("/dev/zero", O_RDONLY);
    if (src < 0)
        src = open("/dev/zero", O_RDONLY);
    snprintf(path, sizeof path, "%s/%d", dir, src);
    int fd = open(path, O_RDONLY);
    int saved_errno = errno;
    int n = fd >= 0 ? read(fd, buf, 4) : -1;
    CHECK(name, fd >= 0 && n == 4, "path=%s fd=%d errno=%d n=%d", path, fd, saved_errno, n);
    if (fd >= 0)
        close(fd);
    close(src);
}

int main(void)
{
    check_std_alias("dev_stdout_pipe", "/dev/stdout", 1, 1);
    check_std_alias("dev_stderr_pipe", "/dev/stderr", 2, 1);
    check_std_alias("dev_stdin_pipe", "/dev/stdin", 0, 0);
    check_numbered("dev_fd_n_file", "/dev/fd");
    check_numbered("proc_self_fd_n_file", "/proc/self/fd");

    int fd = open("/dev/fd/99", O_RDONLY);
    CHECK("closed_fd_enoent", fd < 0 && errno == ENOENT, "fd=%d errno=%d", fd, errno);
    fd = open("/dev/fd/abc", O_RDONLY);
    CHECK("bad_number_enoent", fd < 0 && errno == ENOENT, "fd=%d errno=%d", fd, errno);
    fd = open("/dev/stdout", O_WRONLY | O_CLOEXEC);
    CHECK("cloexec_flag", fd >= 0 && (fcntl(fd, F_GETFD) & FD_CLOEXEC), "fd=%d", fd);
    if (fd >= 0)
        close(fd);
    int own = open("/dev/zero", O_RDONLY);
    char path[48];
    snprintf(path, sizeof path, "/dev/fd/%d", own);
    int again = open(path, O_RDONLY);
    CHECK("not_same_number", own >= 0 && again >= 0 && again != own, "own=%d again=%d", own, again);
    return 0;
}
