#define TNAME "pvecwait"
#include "t.h"
#include <fcntl.h>
#include <stdlib.h>
#include <signal.h>
#include <sys/syscall.h>
#include <sys/uio.h>
#include <sys/wait.h>

/* Firefox needs: many pipes at once (libevent/glib wake-ups per process), pwritev2/preadv2, waitid(WNOWAIT). */

int main(void)
{
    int pp[40][2];
    int made = 0;
    for (int i = 0; i < 40; i++) {
        if (pipe(pp[i]) != 0) break;
        made++;
    }
    CHECK("pipes_40_at_once", made == 40, "made=%d errno=%d", made, errno);
    int okio = 1;
    for (int i = 0; i < made; i++) {
        char c = (char)('a' + i % 26), g = 0;
        if (write(pp[i][1], &c, 1) != 1 || read(pp[i][0], &g, 1) != 1 || g != c) okio = 0;
        close(pp[i][0]);
        close(pp[i][1]);
    }
    CHECK("pipes_roundtrip", okio, "");

    char path[] = "/tmp/pvXXXXXX";
    int fd = mkstemp(path);
    if (fd < 0) {
        GAP("tmpfile", "errno=%d", errno);
        return 0;
    }
    unlink(path);
    char init[16];
    memset(init, '.', sizeof init);
    write(fd, init, sizeof init);
    struct iovec w2[2] = { { "AB", 2 }, { "CDE", 3 } };
    errno = 0;
    long r = syscall(SYS_pwritev, fd, w2, 2, 4L, 0L);
    CHECKC("pwritev_ret", r == 5, "r=%ld", r);
    char back[16];
    pread(fd, back, sizeof back, 0);
    CHECK("pwritev_offset", memcmp(back, "....ABCDE.......", 16) == 0, "");
    struct iovec r2[2];
    char a[2], b[3];
    r2[0].iov_base = a; r2[0].iov_len = 2;
    r2[1].iov_base = b; r2[1].iov_len = 3;
    errno = 0;
    r = syscall(SYS_preadv, fd, r2, 2, 4L, 0L);
    CHECKC("preadv", r == 5 && memcmp(a, "AB", 2) == 0 && memcmp(b, "CDE", 3) == 0, "r=%ld", r);
    struct iovec w3[1] = { { "ZZ", 2 } };
    errno = 0;
    r = syscall(SYS_pwritev2, fd, w3, 1, 10L, 0L, 0);
    CHECKC("pwritev2", r == 2, "r=%ld", r);
    pread(fd, back, sizeof back, 0);
    CHECK("pwritev2_offset", memcmp(back + 10, "ZZ", 2) == 0, "");
    errno = 0;
    r2[0].iov_base = a; r2[0].iov_len = 2;
    r = syscall(SYS_preadv2, fd, r2, 1, 10L, 0L, 0);
    CHECKC("preadv2", r == 2 && memcmp(a, "ZZ", 2) == 0, "r=%ld", r);
    close(fd);

    int gate[2];
    pipe(gate);
    pid_t kid = fork();
    if (kid == 0) {
        char c;
        close(gate[1]);
        read(gate[0], &c, 1);
        _exit(7);
    }
    close(gate[0]);
    siginfo_t si;
    memset(&si, 0x55, sizeof si);
    errno = 0;
    int rc = waitid(P_PID, kid, &si, WEXITED | WNOHANG);
    CHECKC("waitid_nohang_running", rc == 0 && si.si_pid == 0, "rc=%d pid=%d", rc, (int)si.si_pid);
    close(gate[1]);
    memset(&si, 0, sizeof si);
    errno = 0;
    rc = waitid(P_PID, kid, &si, WEXITED | WNOWAIT);
    CHECKC("waitid_wnowait", rc == 0 && si.si_pid == kid && si.si_code == CLD_EXITED && si.si_status == 7, "rc=%d pid=%d code=%d st=%d", rc, (int)si.si_pid, si.si_code, si.si_status);
    memset(&si, 0, sizeof si);
    errno = 0;
    rc = waitid(P_PID, kid, &si, WEXITED | WNOHANG);
    CHECKC("waitid_still_there", rc == 0 && si.si_pid == kid && si.si_status == 7, "rc=%d pid=%d", rc, (int)si.si_pid);
    int st = 0;
    pid_t w = waitpid(kid, &st, 0);
    CHECK("waitpid_after_waitid", w == kid && WIFEXITED(st) && WEXITSTATUS(st) == 7, "w=%d st=%d", (int)w, st);
    errno = 0;
    rc = waitid(P_PID, kid, &si, WEXITED | WNOHANG);
    CHECK("waitid_no_child", rc == -1 && errno == ECHILD, "rc=%d errno=%d", rc, errno);
    long fa = syscall(221, 0, 0L, 0L, 4);
    CHECK("fadvise64_ok", fa == 0, "fa=%ld errno=%d", fa, errno);
    return 0;
}
