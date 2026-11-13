#define TNAME "usockshut"
#include "t.h"
#include <fcntl.h>
#include <poll.h>
#include <signal.h>
#include <stdio.h>
#include <string.h>
#include <sys/socket.h>
#include <sys/wait.h>

#define DELAY_US 150000

static int make_pair(int *sv)
{
    return socketpair(AF_UNIX, SOCK_STREAM, 0, sv);
}

static int recv_now(int fd, char *buf, int len)
{
    return (int)recv(fd, buf, len, MSG_DONTWAIT);
}

static int send_now(int fd)
{
    errno = 0;
    return (int)send(fd, "x", 1, MSG_NOSIGNAL | MSG_DONTWAIT);
}

static void check_write_side(void)
{
    int sv[2];
    char buf[8];
    if (make_pair(sv) != 0) {
        FAIL("write_pair", "errno=%d", errno);
        return;
    }
    (void)!write(sv[0], "hi", 2);
    int r = shutdown(sv[0], SHUT_WR);
    CHECKC("wr_returns_zero", r == 0);
    CHECK("wr_peer_drains_data", recv_now(sv[1], buf, sizeof buf) == 2, "errno=%d", errno);
    CHECK("wr_peer_sees_eof", recv_now(sv[1], buf, sizeof buf) == 0, "errno=%d", errno);
    CHECK("wr_self_send_epipe", send_now(sv[0]) < 0 && errno == EPIPE, "errno=%d", errno);
    CHECK("wr_other_direction_open", send_now(sv[1]) == 1 && recv_now(sv[0], buf, sizeof buf) == 1, "errno=%d", errno);
    close(sv[0]);
    close(sv[1]);
}

static void check_read_side(void)
{
    int sv[2];
    char buf[8];
    if (make_pair(sv) != 0) {
        FAIL("read_pair", "errno=%d", errno);
        return;
    }
    int r = shutdown(sv[0], SHUT_RD);
    CHECKC("rd_returns_zero", r == 0);
    CHECK("rd_self_sees_eof", recv_now(sv[0], buf, sizeof buf) == 0, "errno=%d", errno);
    CHECK("rd_peer_send_epipe", send_now(sv[1]) < 0 && errno == EPIPE, "errno=%d", errno);
    CHECK("rd_self_send_open", send_now(sv[0]) == 1 && recv_now(sv[1], buf, sizeof buf) == 1, "errno=%d", errno);
    close(sv[0]);
    close(sv[1]);
}

static void check_both(void)
{
    int sv[2];
    char buf[8];
    if (make_pair(sv) != 0) {
        FAIL("both_pair", "errno=%d", errno);
        return;
    }
    int r = shutdown(sv[0], SHUT_RDWR);
    CHECKC("rdwr_returns_zero", r == 0);
    CHECK("rdwr_self_eof", recv_now(sv[0], buf, sizeof buf) == 0, "errno=%d", errno);
    CHECK("rdwr_peer_eof", recv_now(sv[1], buf, sizeof buf) == 0, "errno=%d", errno);
    CHECK("rdwr_self_send_epipe", send_now(sv[0]) < 0 && errno == EPIPE, "errno=%d", errno);
    CHECK("rdwr_peer_send_epipe", send_now(sv[1]) < 0 && errno == EPIPE, "errno=%d", errno);
    close(sv[0]);
    close(sv[1]);
}

static void check_errors(void)
{
    int sv[2];
    if (make_pair(sv) != 0) {
        FAIL("errors_pair", "errno=%d", errno);
        return;
    }
    errno = 0;
    CHECK("bad_how_einval", shutdown(sv[0], 3) < 0 && errno == EINVAL, "errno=%d", errno);
    close(sv[0]);
    close(sv[1]);
    int lone = socket(AF_UNIX, SOCK_STREAM, 0);
    errno = 0;
    CHECK("unconnected_enotconn", shutdown(lone, SHUT_RDWR) < 0 && errno == ENOTCONN, "errno=%d", errno);
    close(lone);
    errno = 0;
    CHECK("bad_fd_ebadf", shutdown(999, SHUT_RDWR) < 0 && errno == EBADF, "errno=%d", errno);
}

static void check_poll(void)
{
    int sv[2];
    if (make_pair(sv) != 0) {
        FAIL("poll_pair", "errno=%d", errno);
        return;
    }
    struct pollfd p = { .fd = sv[1], .events = POLLIN };
    int idle = poll(&p, 1, 0);
    CHECK("poll_idle_quiet", idle == 0, "ready=%d", idle);
    shutdown(sv[0], SHUT_WR);
    p.revents = 0;
    int ready = poll(&p, 1, 0);
    CHECK("poll_eof_readable", ready == 1 && (p.revents & POLLIN), "ready=%d revents=%x", ready, p.revents);
    close(sv[0]);
    close(sv[1]);
}

static void check_wakeup(void)
{
    int sv[2];
    char buf[8];
    if (make_pair(sv) != 0) {
        FAIL("wake_pair", "errno=%d", errno);
        return;
    }
    pid_t child = fork();
    if (child == 0) {
        usleep(DELAY_US);
        shutdown(sv[0], SHUT_WR);
        _exit(0);
    }
    int r = (int)read(sv[1], buf, sizeof buf);
    CHECK("blocked_reader_wakes_with_eof", r == 0, "r=%d errno=%d", r, errno);
    waitpid(child, NULL, 0);
    close(sv[0]);
    close(sv[1]);
}

static void check_dup_survives(void)
{
    int sv[2];
    char buf[8];
    if (make_pair(sv) != 0) {
        FAIL("dup_pair", "errno=%d", errno);
        return;
    }
    int copy = dup(sv[0]);
    shutdown(copy, SHUT_WR);
    close(copy);
    CHECK("dup_shared_state", send_now(sv[0]) < 0 && errno == EPIPE, "errno=%d", errno);
    CHECK("dup_peer_eof", recv_now(sv[1], buf, sizeof buf) == 0, "errno=%d", errno);
    close(sv[0]);
    close(sv[1]);
}

static char name_buf[64];

static const char *named(const char *prefix, const char *suffix)
{
    snprintf(name_buf, sizeof name_buf, "%s_%s", prefix, suffix);
    return name_buf;
}

static int send_msg(int fd, const char *msg)
{
    errno = 0;
    return (int)send(fd, msg, strlen(msg), MSG_NOSIGNAL | MSG_DONTWAIT);
}

static void check_message_kind(int type, const char *prefix)
{
    int sv[2];
    char buf[16];
    if (socketpair(AF_UNIX, type, 0, sv) != 0) {
        FAIL(named(prefix, "pair"), "errno=%d", errno);
        return;
    }
    send_msg(sv[0], "one");
    send_msg(sv[0], "second");
    int r = shutdown(sv[0], SHUT_WR);
    CHECKC(named(prefix, "wr_returns_zero"), r == 0);
    int first = recv_now(sv[1], buf, sizeof buf);
    int second = recv_now(sv[1], buf, sizeof buf);
    CHECK(named(prefix, "wr_peer_keeps_boundaries"), first == 3 && second == 6, "first=%d second=%d errno=%d", first, second, errno);
    CHECK(named(prefix, "wr_peer_sees_eof"), recv_now(sv[1], buf, sizeof buf) == 0, "errno=%d", errno);
    CHECK(named(prefix, "wr_self_send_epipe"), send_now(sv[0]) < 0 && errno == EPIPE, "errno=%d", errno);
    CHECK(named(prefix, "wr_other_direction_open"), send_now(sv[1]) == 1 && recv_now(sv[0], buf, sizeof buf) == 1, "errno=%d", errno);
    close(sv[0]);
    close(sv[1]);

    if (socketpair(AF_UNIX, type, 0, sv) != 0) {
        FAIL(named(prefix, "rd_pair"), "errno=%d", errno);
        return;
    }
    r = shutdown(sv[0], SHUT_RD);
    CHECKC(named(prefix, "rd_returns_zero"), r == 0);
    CHECK(named(prefix, "rd_self_sees_eof"), recv_now(sv[0], buf, sizeof buf) == 0, "errno=%d", errno);
    CHECK(named(prefix, "rd_peer_send_epipe"), send_now(sv[1]) < 0 && errno == EPIPE, "errno=%d", errno);
    CHECK(named(prefix, "rd_self_send_open"), send_now(sv[0]) == 1 && recv_now(sv[1], buf, sizeof buf) == 1, "errno=%d", errno);
    close(sv[0]);
    close(sv[1]);

    if (socketpair(AF_UNIX, type, 0, sv) != 0) {
        FAIL(named(prefix, "both_pair"), "errno=%d", errno);
        return;
    }
    r = shutdown(sv[0], SHUT_RDWR);
    CHECKC(named(prefix, "rdwr_returns_zero"), r == 0);
    CHECK(named(prefix, "rdwr_both_eof"), recv_now(sv[0], buf, sizeof buf) == 0 && recv_now(sv[1], buf, sizeof buf) == 0, "errno=%d", errno);
    CHECK(named(prefix, "rdwr_both_send_epipe"), send_now(sv[0]) < 0 && errno == EPIPE && send_now(sv[1]) < 0 && errno == EPIPE, "errno=%d", errno);
    close(sv[0]);
    close(sv[1]);
}

static void check_message_poll(int type, const char *prefix)
{
    int sv[2];
    if (socketpair(AF_UNIX, type, 0, sv) != 0) {
        FAIL(named(prefix, "poll_pair"), "errno=%d", errno);
        return;
    }
    struct pollfd p = { .fd = sv[1], .events = POLLIN };
    int idle = poll(&p, 1, 0);
    CHECK(named(prefix, "poll_idle_quiet"), idle == 0, "ready=%d", idle);
    shutdown(sv[0], SHUT_WR);
    p.revents = 0;
    int ready = poll(&p, 1, 0);
    CHECK(named(prefix, "poll_eof_readable"), ready == 1 && (p.revents & POLLIN), "ready=%d revents=%x", ready, p.revents);
    close(sv[0]);
    close(sv[1]);
}

static void check_message_kinds(void)
{
    check_message_kind(SOCK_SEQPACKET, "seq");
    check_message_kind(SOCK_DGRAM, "dgram");
    check_message_poll(SOCK_SEQPACKET, "seq");
    check_message_poll(SOCK_DGRAM, "dgram");
}

int main(void)
{
    signal(SIGPIPE, SIG_IGN);
    check_write_side();
    check_read_side();
    check_both();
    check_errors();
    check_poll();
    check_wakeup();
    check_dup_survives();
    check_message_kinds();
    return 0;
}
