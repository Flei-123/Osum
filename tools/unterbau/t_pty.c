/* the Linux pty ABI a terminal emulator (foot, xterm, python pty) uses: posix_openpt/grantpt/unlockpt/ptsname_r on /dev/ptmx,
 * /dev/pts/N, TIOCGPTN/TIOCSPTLCK, one window size per pair, TIOCSCTTY after setsid, openpty() of musl. */
#define TNAME "pty"
#include "t.h"
#include <dirent.h>
#include <fcntl.h>
#include <poll.h>
#include <pty.h>
#include <stdlib.h>
#include <string.h>
#include <sys/ioctl.h>
#include <sys/stat.h>
#include <sys/wait.h>
#include <termios.h>

/* read up to n bytes, waiting at most ms for the first one */
static ssize_t rd_wait(int fd, char *b, size_t n, int ms)
{
    struct pollfd pf = { fd, POLLIN, 0 };
    if (poll(&pf, 1, ms) <= 0)
        return -2;
    return read(fd, b, n);
}

int main(void)
{
    char name[64] = "";
    errno = 0;
    int m = posix_openpt(O_RDWR | O_NOCTTY);
    CHECKC("posix_openpt", m >= 0);
    if (m < 0)
        return 0;
    errno = 0;
    CHECKC("grantpt", grantpt(m) == 0);
    errno = 0;
    CHECKC("unlockpt", unlockpt(m) == 0);
    errno = 0;
    int pr = ptsname_r(m, name, sizeof name);
    CHECK("ptsname_r", pr == 0 && strncmp(name, "/dev/pts/", 9) == 0, "ptsname_r -> %d '%s'", pr, name);
    unsigned int num = 9999;
    errno = 0;
    int r = ioctl(m, TIOCGPTN, &num);
    CHECKC("tiocgptn", r == 0 && num < 64);
    CHECK("ptsname_matches_tiocgptn", pr == 0 && atoi(name + 9) == (int)num, "name '%s' num %u", name, num);

    errno = 0;
    int s = open(name, O_RDWR | O_NOCTTY);
    CHECKC("open_slave", s >= 0);
    if (s < 0)
        return 0;
    CHECK("isatty_slave", isatty(s) == 1, "isatty(slave) -> %d errno %d", isatty(s), errno);
    CHECK("isatty_master", isatty(m) == 1, "isatty(master) -> %d", isatty(m));
    struct stat st;
    CHECK("stat_slave_chr", fstat(s, &st) == 0 && S_ISCHR(st.st_mode), "mode 0%o", (unsigned)st.st_mode);
    errno = 0;
    CHECK("stat_by_name_chr", stat(name, &st) == 0 && S_ISCHR(st.st_mode), "stat '%s' errno %d", name, errno);
    CHECK("stat_ptmx_chr", stat("/dev/ptmx", &st) == 0 && S_ISCHR(st.st_mode), "errno %d", errno);

    /* no echo, so the master only sees what the slave wrote */
    struct termios tio;
    errno = 0;
    CHECKC("tcgetattr_slave", tcgetattr(s, &tio) == 0);
    tio.c_lflag &= ~(ECHO | ECHOE | ECHOK | ECHONL);
    errno = 0;
    CHECKC("tcsetattr_slave", tcsetattr(s, TCSANOW, &tio) == 0);

    /* master -> slave (the slave is in canonical mode: a full line) */
    (void)!write(m, "ping\n", 5);
    char b[64];
    memset(b, 0, sizeof b);
    ssize_t n = rd_wait(s, b, sizeof b, 2000);
    CHECK("master_to_slave", n >= 4 && memcmp(b, "ping", 4) == 0, "read %zd '%.8s'", n, b);

    /* slave -> master */
    (void)!write(s, "pong\n", 5);
    memset(b, 0, sizeof b);
    struct pollfd pf = { m, POLLIN, 0 };
    CHECK("poll_master_readable", poll(&pf, 1, 2000) == 1 && (pf.revents & POLLIN), "revents 0x%x", pf.revents);
    n = read(m, b, sizeof b);
    CHECK("slave_to_master", n >= 4 && memcmp(b, "pong", 4) == 0, "read %zd '%.8s'", n, b);

    /* one window size per pair: set on the master, read on the slave (and the other way) */
    struct winsize ws = { 31, 101, 0, 0 };
    errno = 0;
    CHECKC("tiocswinsz_master", ioctl(m, TIOCSWINSZ, &ws) == 0);
    struct winsize w2 = { 0, 0, 0, 0 };
    r = ioctl(s, TIOCGWINSZ, &w2);
    CHECK("winsize_master_to_slave", r == 0 && w2.ws_row == 31 && w2.ws_col == 101, "slave sees %ux%u (r=%d)", w2.ws_row, w2.ws_col, r);
    struct winsize w3 = { 0, 0, 0, 0 };
    r = ioctl(m, TIOCGWINSZ, &w3);
    CHECK("winsize_on_master", r == 0 && w3.ws_row == 31 && w3.ws_col == 101, "master sees %ux%u (r=%d)", w3.ws_row, w3.ws_col, r);

    /* raw mode: one byte arrives at once, without a newline */
    cfmakeraw(&tio);
    errno = 0;
    CHECKC("tcsetattr_raw", tcsetattr(s, TCSANOW, &tio) == 0);
    (void)!write(m, "x", 1);
    memset(b, 0, sizeof b);
    n = rd_wait(s, b, sizeof b, 2000);
    CHECK("raw_one_byte", n == 1 && b[0] == 'x', "read %zd", n);

    /* counter-proofs: the pty requests on something that is no pty master */
    int dn = open("/dev/null", O_RDWR);
    unsigned int z = 0;
    errno = 0;
    CHECK("tiocgptn_on_non_tty", dn >= 0 && ioctl(dn, TIOCGPTN, &z) == -1 && errno == ENOTTY, "errno %d", errno);
    errno = 0;
    CHECK("ptsname_r_on_non_pty", dn >= 0 && ptsname_r(dn, b, sizeof b) != 0, "ptsname_r succeeded on /dev/null");
    errno = 0;
    CHECK("tiocgptn_on_slave_refused", ioctl(s, TIOCGPTN, &z) == -1, "TIOCGPTN worked on the SLAVE");
    if (dn >= 0)
        close(dn);
    errno = 0;
    CHECK("open_missing_slave_enoent", open("/dev/pts/63", O_RDWR) == -1 && errno == ENOENT, "errno %d", errno);
    errno = 0;
    CHECK("open_pts_garbage_enoent", open("/dev/pts/12x", O_RDWR) == -1 && errno == ENOENT, "errno %d", errno);

    /* the slave can be opened a second time (a child shell does) */
    int s2 = open(name, O_RDWR | O_NOCTTY);
    CHECK("open_slave_twice", s2 >= 0, "errno %d", errno);
    if (s2 >= 0)
        close(s2);

    /* /dev/pts lists the pair that is open */
    int found = 0, entries = 0;
    DIR *d = opendir("/dev/pts");
    if (d) {
        struct dirent *e;
        while ((e = readdir(d))) {
            entries++;
            if (e->d_name[0] != '.' && atoi(e->d_name) == (int)num)
                found = 1;
        }
        closedir(d);
    }
    CHECK("readdir_dev_pts_lists_pair", d != NULL && found, "opendir %s, %d entries, pair %u %s", d ? "ok" : "failed", entries, num, found ? "found" : "missing");

    /* controlling terminal: a child makes its own session and takes the slave as its terminal */
    pid_t pid = fork();
    if (pid == 0) {
        int ok = 0;
        if (setsid() > 0) {
            int cs = open(name, O_RDWR);
            if (cs >= 0 && ioctl(cs, TIOCSCTTY, 0) == 0) {
                int t = open("/dev/tty", O_WRONLY);
                if (t >= 0 && write(t, "ctty!", 5) == 5)
                    ok = 1;
            }
        }
        _exit(ok ? 0 : 3);
    }
    int stt = -1;
    if (pid > 0)
        waitpid(pid, &stt, 0);
    CHECK("tiocsctty_after_setsid", pid > 0 && WIFEXITED(stt) && WEXITSTATUS(stt) == 0, "child status 0x%x", stt);
    memset(b, 0, sizeof b);
    n = rd_wait(m, b, sizeof b, 2000);
    CHECK("dev_tty_is_the_slave", n >= 5 && memcmp(b, "ctty!", 5) == 0, "master read %zd '%.8s'", n, b);

    /* musl openpty() goes the same road in one call */
    int om = -1, os = -1;
    errno = 0;
    r = openpty(&om, &os, NULL, NULL, NULL);
    CHECKC("openpty_libc", r == 0 && om >= 0 && os >= 0);
    if (r == 0) {
        (void)!write(os, "hi", 2);
        memset(b, 0, sizeof b);
        n = rd_wait(om, b, sizeof b, 2000);
        CHECK("openpty_libc_data", n >= 2 && memcmp(b, "hi", 2) == 0, "read %zd", n);
        close(om);
        close(os);
    }

    /* the table is finite: open and close many pairs, twice (the reaper gives them back) */
    int made = 0;
    for (int round = 0; round < 2; round++) {
        int fds[8];
        int k;
        for (k = 0; k < 6; k++) {
            fds[k] = open("/dev/ptmx", O_RDWR | O_NOCTTY);
            if (fds[k] < 0)
                break;
            made++;
        }
        for (int j = 0; j < k; j++)
            close(fds[j]);
    }
    CHECK("ptmx_6_pairs_twice", made == 12, "only %d of 12 opened (errno %d)", made, errno);

    /* the master closes: the slave sees the hangup, it does not block for ever */
    close(m);
    pf.fd = s;
    pf.events = POLLIN;
    pf.revents = 0;
    fcntl(s, F_SETFL, fcntl(s, F_GETFL) | O_NONBLOCK);
    int pn = poll(&pf, 1, 2000);
    n = read(s, b, sizeof b);
    CHECK("master_close_hangs_up_slave", pn >= 1 && ((pf.revents & (POLLHUP | POLLERR)) || n <= 0), "poll %d revents 0x%x read %zd", pn, pf.revents, n);
    close(s);
    return 0;
}
