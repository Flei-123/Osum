#define TNAME "seqpacket"
#include "t.h"
#include <fcntl.h>
#include <poll.h>
#include <sys/socket.h>
#include <sys/uio.h>

/* SOCK_SEQPACKET socketpair (Firefox SandboxBroker): message boundaries, truncation, scatter/gather,
 * descriptors that belong to ONE message, EOF. */

static int send_msg(int sk, const char *data, int len, int passfd)
{
    struct iovec iov = { (void *)data, (size_t)len };
    union { struct cmsghdr h; char b[CMSG_SPACE(sizeof(int))]; } u;
    struct msghdr m;
    memset(&m, 0, sizeof m);
    m.msg_iov = &iov;
    m.msg_iovlen = 1;
    if (passfd >= 0) {
        memset(&u, 0, sizeof u);
        m.msg_control = u.b;
        m.msg_controllen = sizeof u.b;
        struct cmsghdr *c = CMSG_FIRSTHDR(&m);
        c->cmsg_level = SOL_SOCKET;
        c->cmsg_type = SCM_RIGHTS;
        c->cmsg_len = CMSG_LEN(sizeof(int));
        memcpy(CMSG_DATA(c), &passfd, sizeof(int));
    }
    return (int)sendmsg(sk, &m, 0);
}

static int recv_msg(int sk, char *buf, int cap, int *fdout, int *mflags, int withctl)
{
    struct iovec iov = { buf, (size_t)cap };
    union { struct cmsghdr h; char b[CMSG_SPACE(sizeof(int))]; } u;
    struct msghdr m;
    memset(&m, 0, sizeof m);
    memset(&u, 0, sizeof u);
    m.msg_iov = &iov;
    m.msg_iovlen = 1;
    if (withctl) {
        m.msg_control = u.b;
        m.msg_controllen = sizeof u.b;
    }
    int r = (int)recvmsg(sk, &m, MSG_DONTWAIT);
    if (mflags) *mflags = m.msg_flags;
    if (fdout) *fdout = -1;
    if (r >= 0 && withctl) {
        for (struct cmsghdr *c = CMSG_FIRSTHDR(&m); c; c = CMSG_NXTHDR(&m, c))
            if (c->cmsg_level == SOL_SOCKET && c->cmsg_type == SCM_RIGHTS && fdout)
                memcpy(fdout, CMSG_DATA(c), sizeof(int));
    }
    return r;
}

static int pipe_with_id(unsigned char id)
{
    int p[2];
    if (pipe(p) != 0) return -1;
    (void)!write(p[1], &id, 1);
    close(p[1]);
    return p[0];
}

static int fd_id(int fd)
{
    unsigned char id = 0;
    if (fd < 0 || read(fd, &id, 1) != 1) return -1;
    return id;
}

int main(void)
{
    int sv[2];
    if (socketpair(AF_UNIX, SOCK_SEQPACKET, 0, sv) != 0) {
        GAP("socketpair", "errno=%d", errno);
        return 0;
    }
    PASS("socketpair");
    char buf[4096];
    int mf = 0, fd = -1, r;

    send_msg(sv[0], "AAAA", 4, -1);
    send_msg(sv[0], "BB", 2, -1);
    r = recv_msg(sv[1], buf, sizeof buf, NULL, &mf, 0);
    CHECK("boundary_first", r == 4 && memcmp(buf, "AAAA", 4) == 0, "r=%d", r);
    r = recv_msg(sv[1], buf, sizeof buf, NULL, &mf, 0);
    CHECK("boundary_second", r == 2 && memcmp(buf, "BB", 2) == 0, "r=%d", r);

    send_msg(sv[0], "0123456789", 10, -1);
    r = recv_msg(sv[1], buf, 4, NULL, &mf, 0);
    CHECK("trunc_flag", r == 4 && (mf & MSG_TRUNC) != 0, "r=%d flags=%d", r, mf);
    errno = 0;
    r = recv_msg(sv[1], buf, sizeof buf, NULL, &mf, 0);
    CHECK("trunc_rest_dropped", r < 0 && errno == EAGAIN, "r=%d errno=%d", r, errno);

    {
        struct iovec out[2] = { { "head-", 5 }, { "tail", 4 } };
        struct msghdr m;
        memset(&m, 0, sizeof m);
        m.msg_iov = out;
        m.msg_iovlen = 2;
        int w = (int)sendmsg(sv[0], &m, 0);
        char a[3], b[16];
        struct iovec in[2] = { { a, sizeof a }, { b, sizeof b } };
        memset(&m, 0, sizeof m);
        m.msg_iov = in;
        m.msg_iovlen = 2;
        int g = (int)recvmsg(sv[1], &m, MSG_DONTWAIT);
        CHECK("iov_gather_scatter", w == 9 && g == 9 && memcmp(a, "hea", 3) == 0 && memcmp(b, "d-tail", 6) == 0, "w=%d g=%d", w, g);
    }

    int p1 = pipe_with_id(11), p2 = pipe_with_id(22);
    send_msg(sv[0], "plain", 5, -1);
    send_msg(sv[0], "one", 3, p1);
    send_msg(sv[0], "two", 3, p2);
    close(p1);
    close(p2);
    r = recv_msg(sv[1], buf, sizeof buf, NULL, &mf, 1);
    int okp = r == 5;
    r = recv_msg(sv[1], buf, sizeof buf, &fd, &mf, 1);
    CHECK("fd_belongs_to_message_1", okp && r == 3 && fd >= 0 && fd_id(fd) == 11, "r=%d fd=%d", r, fd);
    if (fd >= 0) close(fd);
    r = recv_msg(sv[1], buf, sizeof buf, &fd, &mf, 1);
    CHECK("fd_belongs_to_message_2", r == 3 && fd >= 0 && fd_id(fd) == 22, "r=%d fd=%d", r, fd);
    if (fd >= 0) close(fd);

    int p3 = pipe_with_id(33);
    send_msg(sv[0], "drop", 4, p3);
    close(p3);
    send_msg(sv[0], "next", 4, -1);
    r = recv_msg(sv[1], buf, sizeof buf, NULL, &mf, 0);
    CHECK("no_ctl_drops_fd_ctrunc", r == 4 && (mf & MSG_CTRUNC) != 0, "r=%d flags=%d", r, mf);
    r = recv_msg(sv[1], buf, sizeof buf, &fd, &mf, 1);
    CHECK("after_drop_next_clean", r == 4 && fd < 0 && memcmp(buf, "next", 4) == 0, "r=%d fd=%d", r, fd);

    memset(buf, 'x', sizeof buf);
    r = send_msg(sv[0], buf, 3000, -1);
    CHECK("send_3000", r == 3000, "r=%d errno=%d", r, errno);
    r = recv_msg(sv[1], buf, sizeof buf, NULL, &mf, 0);
    CHECK("recv_3000", r == 3000, "r=%d", r);
    errno = 0;
    r = send_msg(sv[0], buf, 4096, -1);
    CHECK("too_big_emsgsize", r < 0 && errno == EMSGSIZE, "r=%d errno=%d", r, errno);

    struct pollfd pf = { sv[1], POLLIN, 0 };
    CHECK("poll_empty", poll(&pf, 1, 0) == 0, "revents=%d", pf.revents);
    send_msg(sv[0], "z", 1, -1);
    CHECK("poll_ready", poll(&pf, 1, 0) == 1 && (pf.revents & POLLIN), "revents=%d", pf.revents);
    recv_msg(sv[1], buf, sizeof buf, NULL, &mf, 0);

    close(sv[0]);
    r = recv_msg(sv[1], buf, sizeof buf, NULL, &mf, 0);
    CHECK("eof_after_close", r == 0, "r=%d errno=%d", r, errno);
    return 0;
}
