/* AF_NETLINK / NETLINK_ROUTE (r696): the dump requests of `ip addr/link/route`, in the Linux message format. No <linux/netlink.h> on
 * purpose: musl-gcc does not ship it, and the byte layout is the thing under test. */
#define TNAME "netlink"
#include "t.h"
#include <poll.h>
#include <stdio.h>
#include <time.h>
#include <arpa/inet.h>
#include <netinet/in.h>
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
#define RTM_SETLINK 19
#define RTM_DELADDR 21
#define RTM_DELROUTE 25
#define RTM_NEWRULE 32
#define NLM_F_REPLACE 0x100
#define NLM_F_EXCL 0x200
#define NLM_F_CREATE 0x400
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

static int nl_change(int fd, int type, int flags, const void *body, int blen, const void *attrs, int alen, int seq)
{
    char b[512];
    memset(b, 0, sizeof b);
    struct nlh *h = (struct nlh *)b;
    memcpy(b + sizeof *h, body, blen);
    memcpy(b + sizeof *h + blen, attrs, alen);
    h->len = sizeof *h + blen + alen;
    h->type = type;
    h->flags = NLM_F_REQUEST | NLM_F_ACK | flags;
    h->seq = seq;
    struct sanl to = { AF_NETLINK, 0, 0, 0 };
    struct iovec iov = { b, h->len };
    struct msghdr m;
    memset(&m, 0, sizeof m);
    m.msg_name = &to;
    m.msg_namelen = sizeof to;
    m.msg_iov = &iov;
    m.msg_iovlen = 1;
    if (sendmsg(fd, &m, 0) < 0) return -1000 - errno;
    char rb[512];
    ssize_t n = recv(fd, rb, sizeof rb, 0);
    struct nlh *rh = (struct nlh *)rb;
    if (n < 20 || rh->type != NLMSG_ERROR || rh->seq != (uint32_t)seq) return 99999;
    return *(int32_t *)(rb + 16);
}

static int put_attr(char *p, int type, const void *d, int n)
{
    uint16_t *a = (uint16_t *)p;
    a[0] = 4 + n;
    a[1] = type;
    memcpy(p + 4, d, n);
    return (4 + n + 3) & ~3;
}

static int addr_change(int fd, int type, int flags, int plen, const char *ip, int seq)
{
    uint8_t body[8] = { 2, (uint8_t)plen, 0, 0, 1, 0, 0, 0 };
    char at[32];
    struct in_addr a;
    inet_aton(ip, &a);
    int n = put_attr(at, 2, &a, 4);
    n += put_attr(at + n, 1, &a, 4);
    return nl_change(fd, type, flags, body, 8, at, n, seq);
}

static int route_change(int fd, int type, int flags, const char *gw, int seq)
{
    uint8_t body[12] = { 2, 0, 0, 0, 254, 3, 0, 1, 0, 0, 0, 0 };
    char at[16];
    int n = 0;
    if (gw) {
        struct in_addr a;
        inet_aton(gw, &a);
        n = put_attr(at, 5, &a, 4);
    }
    return nl_change(fd, type, flags, body, 12, at, n, seq);
}

static int link_change(int fd, int flags_now, int change, int seq)
{
    uint32_t body[4];
    memset(body, 0, sizeof body);
    ((uint8_t *)body)[0] = 0;
    body[1] = 1;
    body[2] = flags_now;
    body[3] = change;
    return nl_change(fd, RTM_NEWLINK, 0, body, 16, "", 0, seq);
}

static long link_flags(int fd, int seq)
{
    send_req(fd, RTM_GETLINK, NLM_F_REQUEST | NLM_F_DUMP, 0, seq);
    char buf[2048];
    long fl = -1;
    int done = 0;
    for (int round = 0; round < 4 && !done; round++) {
        ssize_t n = recv(fd, buf, sizeof buf, 0);
        if (n <= 0) break;
        struct nlh *h = (struct nlh *)buf;
        while (n >= (ssize_t)sizeof *h && h->len >= sizeof *h && h->len <= (size_t)n) {
            if (h->type == NLMSG_DONE) { done = 1; break; }
            if (h->type == RTM_NEWLINK) fl = *(uint32_t *)((char *)h + 24);
            ssize_t a = (h->len + 3) & ~3;
            n -= a;
            h = (struct nlh *)((char *)h + a);
        }
    }
    return fl;
}

static long tx_frames(void)
{
    FILE *f = fopen("/proc/net/dev", "r");
    char line[256];
    long tx = -1;
    if (!f) return -1;
    while (fgets(line, sizeof line, f)) {
        char *c = strstr(line, "eth0:");
        if (c) {
            long v[16];
            int k = sscanf(c + 5, "%ld %ld %ld %ld %ld %ld %ld %ld %ld %ld", &v[0], &v[1], &v[2], &v[3], &v[4], &v[5], &v[6], &v[7], &v[8], &v[9]);
            if (k >= 10) tx = v[9];
        }
    }
    fclose(f);
    return tx;
}

static void udp_poke(void)
{
    int s = socket(AF_INET, SOCK_DGRAM, 0);
    struct sockaddr_in to;
    memset(&to, 0, sizeof to);
    to.sin_family = AF_INET;
    to.sin_port = htons(9);
    inet_aton("10.0.2.2", &to.sin_addr);
    sendto(s, "x", 1, 0, (struct sockaddr *)&to, sizeof to);
    close(s);
    struct timespec ts = { 0, 300000000 };
    nanosleep(&ts, 0);
}

static void write_tests(int fd)
{
    int items, done, r;
    send_req(fd, RTM_GETADDR, NLM_F_REQUEST | NLM_F_DUMP, 2, 30);
    r = read_dump(fd, RTM_NEWADDR, 30, &items, &done);
    if (r != 1 || items != 1) {
        GAP("write_needs_nic", "r=%d items=%d", r, items);
        return;
    }
    r = addr_change(fd, RTM_NEWADDR, NLM_F_CREATE | NLM_F_EXCL, 24, "10.0.2.15", 31);
    CHECK("addr_exists", r == -EEXIST, "got %d", r);
    r = addr_change(fd, RTM_NEWADDR, NLM_F_CREATE, 24, "10.0.2.99", 32);
    CHECK("addr_second_refused", r == -EOPNOTSUPP, "got %d", r);
    r = addr_change(fd, RTM_DELADDR, 0, 24, "10.0.2.77", 33);
    CHECK("addr_del_missing", r == -EADDRNOTAVAIL, "got %d", r);
    r = addr_change(fd, RTM_NEWADDR, NLM_F_CREATE, 40, "10.0.2.15", 34);
    CHECK("addr_bad_prefix", r == -EINVAL, "got %d", r);
    r = route_change(fd, RTM_NEWROUTE, NLM_F_CREATE | NLM_F_EXCL, "10.0.2.2", 35);
    CHECK("route_default_exists", r == -EEXIST, "got %d", r);
    r = route_change(fd, RTM_NEWROUTE, NLM_F_CREATE | NLM_F_REPLACE, "192.168.77.1", 36);
    CHECK("route_offlink_refused", r == -ENETUNREACH, "got %d", r);
    r = route_change(fd, RTM_DELROUTE, 0, "10.0.2.3", 37);
    CHECK("route_del_wrong_gw", r == -ESRCH, "got %d", r);
    r = route_change(fd, RTM_DELROUTE, 0, "10.0.2.2", 38);
    CHECK("route_del_default", r == 0, "got %d", r);
    send_req(fd, RTM_GETROUTE, NLM_F_REQUEST | NLM_F_DUMP, 2, 39);
    r = read_dump(fd, RTM_NEWROUTE, 39, &items, &done);
    CHECK("route_dump_after_del", r == 1 && items == 1, "r=%d items=%d", r, items);
    r = route_change(fd, RTM_DELROUTE, 0, 0, 40);
    CHECK("route_del_twice", r == -ESRCH, "got %d", r);
    r = route_change(fd, RTM_NEWROUTE, NLM_F_CREATE | NLM_F_EXCL, "10.0.2.2", 41);
    CHECK("route_add_default", r == 0, "got %d", r);
    send_req(fd, RTM_GETROUTE, NLM_F_REQUEST | NLM_F_DUMP, 2, 42);
    r = read_dump(fd, RTM_NEWROUTE, 42, &items, &done);
    CHECK("route_dump_after_add", r == 1 && items == 2, "r=%d items=%d", r, items);
    r = addr_change(fd, RTM_DELADDR, 0, 24, "10.0.2.15", 43);
    CHECK("addr_del", r == 0, "got %d", r);
    send_req(fd, RTM_GETADDR, NLM_F_REQUEST | NLM_F_DUMP, 2, 44);
    r = read_dump(fd, RTM_NEWADDR, 44, &items, &done);
    CHECK("addr_dump_after_del", r == 1 && items == 0, "r=%d items=%d", r, items);
    r = addr_change(fd, RTM_NEWADDR, NLM_F_CREATE | NLM_F_EXCL, 24, "10.0.2.15", 45);
    CHECK("addr_add", r == 0, "got %d", r);
    send_req(fd, RTM_GETADDR, NLM_F_REQUEST | NLM_F_DUMP, 2, 46);
    r = read_dump(fd, RTM_NEWADDR, 46, &items, &done);
    CHECK("addr_dump_after_add", r == 1 && items == 1, "r=%d items=%d", r, items);
    r = route_change(fd, RTM_NEWROUTE, NLM_F_CREATE, "10.0.2.2", 47);
    CHECK("route_add_after_addr", r == 0 || r == -EEXIST, "got %d", r);

    long t0 = tx_frames();
    udp_poke();
    long t1 = tx_frames();
    int observer = t0 >= 0 && t1 > t0;
    if (!observer) GAP("tx_counter_observer", "tx %ld -> %ld", t0, t1);
    long fl = link_flags(fd, 48);
    CHECK("link_up_flag", fl >= 0 && (fl & 1), "flags %lx", fl);
    r = link_change(fd, 0, 1, 49);
    CHECK("link_set_down", r == 0, "got %d", r);
    fl = link_flags(fd, 50);
    CHECK("link_down_flag", fl >= 0 && !(fl & 1) && !(fl & 0x40), "flags %lx", fl);
    if (observer) {
        t0 = tx_frames();
        udp_poke();
        udp_poke();
        t1 = tx_frames();
        CHECK("link_down_blocks_tx", t1 == t0, "tx %ld -> %ld", t0, t1);
    }
    r = link_change(fd, 1, 1, 51);
    CHECK("link_set_up", r == 0, "got %d", r);
    fl = link_flags(fd, 52);
    CHECK("link_up_again", fl >= 0 && (fl & 1), "flags %lx", fl);
    if (observer) {
        t0 = tx_frames();
        udp_poke();
        t1 = tx_frames();
        CHECK("link_up_passes_tx", t1 > t0, "tx %ld -> %ld", t0, t1);
    }
    r = link_change(fd, 1, 1, 53);
    CHECK("link_up_idempotent", r == 0, "got %d", r);
    uint32_t bad[4] = { 0, 9, 1, 1 };
    r = nl_change(fd, RTM_NEWLINK, 0, bad, 16, "", 0, 54);
    CHECK("link_bad_index", r == -ENODEV, "got %d", r);

    if (setuid(1000) == 0) {
        int fd2 = socket(AF_NETLINK, SOCK_RAW, 0);
        r = fd2 >= 0 ? addr_change(fd2, RTM_NEWADDR, NLM_F_CREATE, 24, "10.0.2.15", 55) : -1;
        CHECK("nonroot_refused", r == -EPERM, "got %d", r);
        r = fd2 >= 0 ? link_change(fd2, 0, 1, 56) : -1;
        CHECK("nonroot_link_refused", r == -EPERM, "got %d", r);
        r = fd2 >= 0 ? route_change(fd2, RTM_DELROUTE, 0, "10.0.2.2", 57) : -1;
        CHECK("nonroot_route_refused", r == -EPERM, "got %d", r);
        if (fd2 >= 0) close(fd2);
    } else {
        GAP("nonroot_refused", "setuid errno %d", errno);
    }
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
    send_req(fd, RTM_NEWRULE, NLM_F_REQUEST | NLM_F_ACK, 2, 15);
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
    write_tests(fd);
    close(fd);
    return 0;
}
