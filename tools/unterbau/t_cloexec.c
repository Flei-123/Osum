/* FD_CLOEXEC for descriptors >= 64 (docs/SECURITY-TOCTOU-KERNEL.md K-08): the close-on-exec set used to be one 64-bit word, so descriptors
 * 64..511 lost the flag and leaked across execve. Checks F_GETFD/F_SETFD on high descriptors and what a child really inherits. */
#define TNAME "cloexec"
#include "t.h"
#include <fcntl.h>
#include <sys/wait.h>

int main(void)
{
    int keep = -1;   /* one descriptor >= 64 WITHOUT the flag: must survive the exec */
    int hi[3] = { -1, -1, -1 }, nhi = 0, opened = 0;
    for (int i = 0; i < 100; i++) {
        int fd = open("/dev/null", O_RDONLY | O_CLOEXEC);
        if (fd < 0) break;
        opened++;
        if (fd >= 64 && nhi < 3) hi[nhi++] = fd;
    }
    CHECK("opened_past_64", opened == 100 && nhi == 3, "opened=%d high=%d", opened, nhi);
    int flags_ok = nhi == 3;
    for (int i = 0; i < nhi; i++) flags_ok = flags_ok && (fcntl(hi[i], F_GETFD) & FD_CLOEXEC);
    CHECK("getfd_high_set", flags_ok, "hi=%d,%d,%d", hi[0], hi[1], hi[2]);
    if (nhi == 3) {
        fcntl(hi[1], F_SETFD, 0);
        keep = hi[1];
    }
    CHECK("setfd_high_clear", keep >= 64 && !(fcntl(keep, F_GETFD) & FD_CLOEXEC) && (fcntl(hi[0], F_GETFD) & FD_CLOEXEC), "keep=%d", keep);
    int fd2 = fcntl(hi[0], F_DUPFD_CLOEXEC, 64);
    CHECK("dupfd_cloexec_high", fd2 >= 64 && (fcntl(fd2, F_GETFD) & FD_CLOEXEC), "fd2=%d", fd2);

    int po[2];
    if (pipe(po) != 0) { CHECK("child_scan", 0, "pipe"); return 0; }
    pid_t p = fork();
    if (p == 0) {
        dup2(po[1], 1); close(po[0]); close(po[1]);
        char *av[] = { "c_child", "fdscan", 0 };
        execve("/bin/c_child", av, 0);
        _exit(127);
    }
    close(po[1]);
    char buf[128] = { 0 };
    int n = 0, r;
    while ((r = read(po[0], buf + n, sizeof buf - 1 - n)) > 0) n += r;
    int st = 0;
    waitpid(p, &st, 0);
    int lo = -1, h = -1;
    sscanf(buf, "fdscan lo=%d hi=%d", &lo, &h);
    /* survivors >= 64: only `keep`; the 98 flagged ones above 64 (and fd2) must be gone. Below 64 the pipe read end is ours, closed in the child. */
    CHECK("child_inherits_only_unflagged", h == 1 && lo == 0, "child said '%s' lo=%d hi=%d", buf, lo, h);
    return 0;
}
