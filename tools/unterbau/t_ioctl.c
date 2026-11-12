#define TNAME "ioctl"
#include "t.h"
#include <fcntl.h>
#include <stdlib.h>
#include <string.h>
#include <sys/ioctl.h>
#include <sys/socket.h>
#include <sys/stat.h>
#include <arpa/inet.h>
#include <netinet/in.h>
#include <poll.h>
#include <termios.h>
#include <unistd.h>

#ifndef FIGETBSZ
#define FIGETBSZ 2
#endif

static void test_pipe(void)
{
    int fds[2], n = -1;
    CHECK("pipe_setup", pipe(fds) == 0, "errno=%d", errno);
    CHECK("pipe_empty_zero", ioctl(fds[0], FIONREAD, &n) == 0 && n == 0, "n=%d errno=%d", n, errno);
    (void)!write(fds[1], "hello", 5);
    n = -1;
    CHECK("pipe_fionread", ioctl(fds[0], FIONREAD, &n) == 0 && n == 5, "n=%d errno=%d", n, errno);
    n = -1;
    CHECK("pipe_tiocinq_alias", ioctl(fds[0], TIOCINQ, &n) == 0 && n == 5, "n=%d errno=%d", n, errno);
    n = -1;
    CHECK("pipe_write_end_fionread", ioctl(fds[1], FIONREAD, &n) == 0 && n == 5, "n=%d errno=%d", n, errno);
    CHECK("pipe_figetbsz_enotty", ioctl(fds[0], FIGETBSZ, &n) < 0 && errno == ENOTTY, "errno=%d", errno);
    CHECK("pipe_fault", ioctl(fds[0], FIONREAD, (int *)0) < 0 && errno == EFAULT, "errno=%d", errno);
    close(fds[0]);
    close(fds[1]);
}

static void test_file(void)
{
    char path[] = "/tmp/t_ioctl_XXXXXX";
    char data[100];
    int fd = mkstemp(path), n = -1;
    memset(data, 'x', sizeof data);
    CHECK("file_setup", fd >= 0 && write(fd, data, sizeof data) == (ssize_t)sizeof data, "errno=%d", errno);
    if (fd < 0)
        return;
    lseek(fd, 0, SEEK_SET);
    CHECK("file_fionread_full", ioctl(fd, FIONREAD, &n) == 0 && n == 100, "n=%d errno=%d", n, errno);
    lseek(fd, 30, SEEK_SET);
    CHECK("file_fionread_offset", ioctl(fd, FIONREAD, &n) == 0 && n == 70, "n=%d errno=%d", n, errno);
    lseek(fd, 0, SEEK_END);
    CHECK("file_fionread_eof", ioctl(fd, FIONREAD, &n) == 0 && n == 0, "n=%d errno=%d", n, errno);
    lseek(fd, 500, SEEK_SET);
    CHECK("file_fionread_past_eof", ioctl(fd, FIONREAD, &n) == 0 && n == 0, "n=%d errno=%d", n, errno);
    n = 0;
    CHECK("file_figetbsz", ioctl(fd, FIGETBSZ, &n) == 0 && n >= 512 && (n & (n - 1)) == 0, "n=%d errno=%d", n, errno);
    close(fd);
    unlink(path);
}

static void test_cloexec(void)
{
    int fd = open("/dev/null", O_RDONLY);
    CHECK("cloexec_initial_clear", fd >= 0 && (fcntl(fd, F_GETFD) & FD_CLOEXEC) == 0, "errno=%d", errno);
    CHECK("fioclex_sets", ioctl(fd, FIOCLEX) == 0 && (fcntl(fd, F_GETFD) & FD_CLOEXEC) != 0, "flags=%d errno=%d", fcntl(fd, F_GETFD), errno);
    CHECK("fionclex_clears", ioctl(fd, FIONCLEX) == 0 && (fcntl(fd, F_GETFD) & FD_CLOEXEC) == 0, "flags=%d errno=%d", fcntl(fd, F_GETFD), errno);
    int high = fcntl(fd, F_DUPFD, 100);
    CHECK("fioclex_high_fd", high >= 100 && ioctl(high, FIOCLEX) == 0 && (fcntl(high, F_GETFD) & FD_CLOEXEC) != 0, "high=%d errno=%d", high, errno);
    CHECK("fioclex_badf", ioctl(900, FIOCLEX) < 0 && errno == EBADF, "errno=%d", errno);
    close(fd);
    if (high >= 0)
        close(high);
}

static void test_unix_socket(void)
{
    int sv[2], n = -1;
    CHECK("usock_setup", socketpair(AF_UNIX, SOCK_STREAM, 0, sv) == 0, "errno=%d", errno);
    (void)!write(sv[0], "1234567", 7);
    CHECK("usock_stream_fionread", ioctl(sv[1], FIONREAD, &n) == 0 && n == 7, "n=%d errno=%d", n, errno);
    close(sv[0]);
    close(sv[1]);
    int dg[2];
    if (socketpair(AF_UNIX, SOCK_DGRAM, 0, dg) != 0) {
        GAP("usock_dgram_fionread", "socketpair dgram errno=%d", errno);
        return;
    }
    (void)!write(dg[0], "abcdef", 6);
    (void)!write(dg[0], "xy", 2);
    n = -1;
    CHECK("usock_dgram_first_size", ioctl(dg[1], FIONREAD, &n) == 0 && n == 6, "n=%d errno=%d", n, errno);
    close(dg[0]);
    close(dg[1]);
}

static struct sockaddr_in remote(const char *ip, int port)
{
    struct sockaddr_in a;
    memset(&a, 0, sizeof a);
    a.sin_family = AF_INET;
    a.sin_port = htons(port);
    inet_pton(AF_INET, ip, &a.sin_addr);
    return a;
}

static void test_tcp_socket(void)
{
    int s = socket(AF_INET, SOCK_STREAM, 0), n = -1;
    struct sockaddr_in dst = remote("10.0.2.100", 7777);
    int ok = s >= 0 && connect(s, (struct sockaddr *)&dst, sizeof dst) == 0;
    CHECKC("tcp_setup", ok, "");
    if (!ok)
        return;
    CHECK("tcp_empty_fionread", ioctl(s, FIONREAD, &n) == 0 && n == 0, "n=%d errno=%d", n, errno);
    (void)!write(s, "hello", 5);
    struct pollfd p = { s, POLLIN, 0 };
    int ready = poll(&p, 1, 5000);
    n = -1;
    CHECK("tcp_fionread_after_echo", ready == 1 && ioctl(s, FIONREAD, &n) == 0 && n > 0 && n <= 5, "ready=%d n=%d errno=%d", ready, n, errno);
    char buf[8];
    ssize_t got = recv(s, buf, sizeof buf, MSG_PEEK);
    CHECK("tcp_fionread_matches_peek", got == n, "got=%d n=%d", (int)got, n);
    n = -1;
    CHECK("tcp_outq_zero_after_ack", ioctl(s, TIOCOUTQ, &n) == 0 && n >= 0 && n <= 5, "n=%d errno=%d", n, errno);
    close(s);
}

static void test_udp_socket(void)
{
    static const unsigned char query[] = {
        0x12, 0x34, 0x01, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
        7, 'e', 'x', 'a', 'm', 'p', 'l', 'e', 3, 'c', 'o', 'm', 0, 0, 1, 0, 1
    };
    int s = socket(AF_INET, SOCK_DGRAM, 0), n = -1;
    struct sockaddr_in dst = remote("10.0.2.3", 53);
    int ok = s >= 0 && sendto(s, query, sizeof query, 0, (struct sockaddr *)&dst, sizeof dst) == (ssize_t)sizeof query;
    CHECKC("udp_setup", ok, "");
    if (!ok)
        return;
    struct pollfd p = { s, POLLIN, 0 };
    if (poll(&p, 1, 8000) != 1) {
        GAP("udp_fionread_datagram_size", "no dns answer");
        close(s);
        return;
    }
    unsigned char buf[512];
    CHECK("udp_fionread_datagram_size", ioctl(s, FIONREAD, &n) == 0 && n >= 12, "n=%d errno=%d", n, errno);
    ssize_t got = recv(s, buf, sizeof buf, 0);
    CHECK("udp_fionread_matches_recv", got == n, "got=%d n=%d", (int)got, n);
    close(s);
}

static void test_tty(void)
{
    int master = posix_openpt(O_RDWR | O_NOCTTY);
    int n = -1;
    if (master < 0 || grantpt(master) != 0 || unlockpt(master) != 0) {
        GAP("tty_setup", "openpt errno=%d", errno);
        return;
    }
    int slave = open(ptsname(master), O_RDWR | O_NOCTTY);
    CHECK("tty_setup", slave >= 0, "errno=%d", errno);
    if (slave < 0)
        return;
    CHECK("tty_empty_fionread", ioctl(slave, FIONREAD, &n) == 0 && n == 0, "n=%d errno=%d", n, errno);
    (void)!write(master, "ab\n", 3);
    n = -1;
    CHECK("tty_line_fionread", ioctl(slave, FIONREAD, &n) == 0 && n == 3, "n=%d errno=%d", n, errno);
    n = -1;
    CHECK("tty_tiocinq", ioctl(slave, TIOCINQ, &n) == 0 && n == 3, "n=%d errno=%d", n, errno);
    n = -1;
    CHECK("tty_tiocoutq", ioctl(slave, TIOCOUTQ, &n) == 0 && n >= 0, "n=%d errno=%d", n, errno);
    int bits = 0;
    CHECK("pty_tiocmget_enotty", ioctl(slave, TIOCMGET, &bits) < 0 && errno == ENOTTY, "errno=%d", errno);
    close(slave);
    close(master);
}

static void test_not_tty(void)
{
    int fd = open("/dev/null", O_RDONLY), n = 0;
    CHECK("devnull_fionread_enotty", ioctl(fd, FIONREAD, &n) < 0 && errno == ENOTTY, "errno=%d", errno);
    CHECK("devnull_tiocoutq_enotty", ioctl(fd, TIOCOUTQ, &n) < 0 && errno == ENOTTY, "errno=%d", errno);
    CHECK("devnull_tiocmget_enotty", ioctl(fd, TIOCMGET, &n) < 0 && errno == ENOTTY, "errno=%d", errno);
    close(fd);
}

int main(void)
{
    alarm(60);
    test_pipe();
    test_file();
    test_cloexec();
    test_unix_socket();
    test_tcp_socket();
    test_udp_socket();
    test_tty();
    test_not_tty();
    return 0;
}
