/* AF_NETLINK / NETLINK_ROUTE (r696): the dump requests of `ip addr/link/route`, in the Linux message format. No <linux/netlink.h> on
 * purpose: musl-gcc does not ship it, and the byte layout is the thing under test. */
#define TNAME "netlink"
#include "t.h"
#include <poll.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>
#include <sys/socket.h>
#include <sys/uio.h>

#ifndef AF_NETLINK
#define AF_NETLINK 16
#endif
struct nlh { uint32_t len; uint16_t type, flags; uint32_t seq, pid; };
struct sanl { uint16_t family, pad; uint32_t pid, groups; };
struct req { struct nlh h; uint8_t family; uint8_t pad[3]; };

#define NLM_F_REQUEST 1
#define NLM_F_MULTI 2
#define NLM_F_ACK 4
#define NLM_F_DUMP 0x300
#define NLMSG_DONE 3
#define NLMSG_ERROR 2
#define RTM_NEWLINK 16
#define RTM_GETLINK 18
#define RTM_NEWADDR 20
#define RTM_GETADDR 22
#define RTM_NEWROUTE 24
#define RTM_GETROUTE 26

static int send_req(int fd, int type, int flags, int family, int seq)
{
    struct req r;
    memset(&r, 0, sizeof r);
    r.h.len = sizeof r;
    r.h.type = type;
    r.h.flags = flags;
    r.h.seq = seq;
    r.family = family;
    struct sanl to = { AF_NETLINK, 0, 0, 0 };
    struct iovec iov = { &r, sizeof r };
    struct msghdr m;
    memset(&m, 0, sizeof m);
    m.msg_name = &to;
    m.msg_namelen = sizeof to;
    m.msg_iov = &iov;
    m.msg_iovlen = 1;
    return (int)sendmsg(fd, &m, 0);
}

/* read one dump: items of `want` type counted, 1 when NLMSG_DONE came, -1 on a malformed buffer */
static int read_dump(int fd, int want, int seq, int *items, int *done)
{
    char buf[8192];
    *items = 0; *done = 0;
    for (int round = 0; round < 8 && !*done; round++) {
        struct sanl from;
        struct iovec iov = { buf, sizeof buf };
        struct msghdr m;
        memset(&m, 0, sizeof m);
        m.msg_name = &from;
        m.msg_namelen = sizeof from;
        m.msg_iov = &iov;
        m.msg_iovlen = 1;
        ssize_t n = recvmsg(fd, &m, 0);
        if (n <= 0) return -1;
        if (m.msg_namelen != sizeof from || from.family != AF_NETLINK) return -2;
        struct nlh *h = (struct nlh *)buf;
        while (n >= (ssize_t)sizeof *h && h->len >= sizeof *h && h->len <= (size_t)n) {
            if (h->seq != (uint32_t)seq) return -3;
            if (h->type == NLMSG_DONE) { *done = 1; break; }
            if (h->type == NLMSG_ERROR) return -4;
            if (h->type == want && (h->flags & NLM_F_MULTI)) (*items)++;
            ssize_t a = (h->len + 3) & ~3;
            n -= a;
            h = (struct nlh *)((char *)h + a);
        }
    }
    return *done ? 1 : 0;
}

int main(void)
{
    errno = 0;
    int fd = socket(AF_NETLINK, SOCK_RAW | SOCK_CLOEXEC, 0);
    CHECKC("socket", fd >= 0);
    if (fd < 0) return 0;

    errno = 0;
    int bad = socket(AF_NETLINK, SOCK_RAW, 9);
    CHECK("bad_protocol", bad < 0 && errno == EPROTONOSUPPORT, "socket(NETLINK 9) -> %d errno %d", bad, errno);
    if (bad >= 0) close(bad);

    struct sanl me = { AF_NETLINK, 0, 0, 0 };
    CHECKC("bind", bind(fd, (struct sockaddr *)&me, sizeof me) == 0);
    struct sanl got;
    socklen_t gl = sizeof got;
    memset(&got, 0, sizeof got);
    int r = getsockname(fd, (struct sockaddr *)&got, &gl);
    CHECK("getsockname", r == 0 && gl == sizeof got && got.family == AF_NETLINK && got.pid != 0,
          "r=%d len=%d family=%d pid=%u", r, (int)gl, got.family, got.pid);

    int sz = 0; socklen_t sl = sizeof sz;
    int buf = 32768;
    CHECK("setsockopt_rcvbuf", setsockopt(fd, SOL_SOCKET, SO_RCVBUF, &buf, sizeof buf) == 0, "errno %d", errno);
    CHECK("getsockopt_rcvbuf", getsockopt(fd, SOL_SOCKET, SO_RCVBUF, &sz, &sl) == 0 && sz > 0, "errno %d", errno);

    char tmp[64];
    errno = 0;
    ssize_t e = recv(fd, tmp, sizeof tmp, MSG_DONTWAIT | MSG_PEEK);
    CHECK("empty_eagain", e == -1 && errno == EAGAIN, "recv -> %zd errno %d", e, errno);
    struct pollfd pf = { fd, POLLIN, 0 };
    CHECK("poll_empty", poll(&pf, 1, 0) == 0, "readable with nothing queued");

    int items, done;
    int w = send_req(fd, RTM_GETLINK, NLM_F_REQUEST | NLM_F_DUMP, 0, 11);
    CHECK("send_getlink", w == (int)sizeof(struct req), "sendmsg -> %d errno %d", w, errno);
    pf.revents = 0;
    CHECK("poll_reply", poll(&pf, 1, 100) == 1 && (pf.revents & POLLIN), "no POLLIN after a request");
    r = read_dump(fd, RTM_NEWLINK, 11, &items, &done);
    CHECK("dump_link", r == 1 && items <= 1, "r=%d items=%d", r, items);

    send_req(fd, RTM_GETADDR, NLM_F_REQUEST | NLM_F_DUMP, 2, 12);
    r = read_dump(fd, RTM_NEWADDR, 12, &items, &done);
    CHECK("dump_addr", r == 1 && items <= 1, "r=%d items=%d", r, items);

    send_req(fd, RTM_GETROUTE, NLM_F_REQUEST | NLM_F_DUMP, 2, 13);
    r = read_dump(fd, RTM_NEWROUTE, 13, &items, &done);
    CHECK("dump_route", r == 1 && items <= 2, "r=%d items=%d", r, items);

    /* IPv6 is not there: an empty dump, still ended by DONE */
    send_req(fd, RTM_GETADDR, NLM_F_REQUEST | NLM_F_DUMP, 10, 14);
    r = read_dump(fd, RTM_NEWADDR, 14, &items, &done);
    CHECK("dump_addr_ipv6_empty", r == 1 && items == 0, "r=%d items=%d", r, items);

    /* what cannot be done is an error message, not silence */
    send_req(fd, RTM_NEWADDR, NLM_F_REQUEST | NLM_F_ACK, 2, 15);
    char eb[256];
    ssize_t en = recv(fd, eb, sizeof eb, 0);
    struct nlh *eh = (struct nlh *)eb;
    int32_t err = en >= 20 ? *(int32_t *)(eb + 16) : 0;
    CHECK("unsupported_error", en >= 36 && eh->type == NLMSG_ERROR && err == -EOPNOTSUPP && eh->seq == 15,
          "n=%zd type=%d err=%d", en, en >= 8 ? eh->type : -1, err);

    /* MSG_PEEK keeps the datagram, MSG_TRUNC reports its real length, a short buffer sets MSG_TRUNC in msg_flags */
    send_req(fd, RTM_GETROUTE, NLM_F_REQUEST | NLM_F_DUMP, 2, 16);
    char small[8];
    ssize_t pk = recv(fd, small, sizeof small, MSG_PEEK | MSG_TRUNC);
    struct iovec iv = { small, sizeof small };
    struct msghdr mh;
    memset(&mh, 0, sizeof mh);
    mh.msg_iov = &iv;
    mh.msg_iovlen = 1;
    ssize_t full = recvmsg(fd, &mh, MSG_TRUNC);
    CHECK("peek_trunc", pk >= 20 && full == pk && (mh.msg_flags & MSG_TRUNC), "peek=%zd full=%zd flags=%x", pk, full, mh.msg_flags);
    errno = 0;
    CHECK("consumed", recv(fd, tmp, sizeof tmp, MSG_DONTWAIT) == -1 && errno == EAGAIN, "datagram still there");

    /* plain write() works as a request too (rtnl_send_check of busybox does exactly that) */
    struct req rq;
    memset(&rq, 0, sizeof rq);
    rq.h.len = sizeof rq; rq.h.type = RTM_GETLINK; rq.h.flags = NLM_F_REQUEST | NLM_F_DUMP; rq.h.seq = 17; rq.family = 0;
    CHECK("write_request", write(fd, &rq, sizeof rq) == (ssize_t)sizeof rq, "errno %d", errno);
    r = read_dump(fd, RTM_NEWLINK, 17, &items, &done);
    CHECK("write_dump", r == 1, "r=%d", r);
    close(fd);
    return 0;
}
