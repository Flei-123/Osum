#define TNAME "udpnet"
#include "t.h"
#include <arpa/inet.h>
#include <netinet/in.h>
#include <poll.h>
#include <stdlib.h>
#include <sys/uio.h>
#include <sys/socket.h>

static const unsigned char query[] = {
    0x12, 0x34, 0x01, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
    7, 'e', 'x', 'a', 'm', 'p', 'l', 'e', 3, 'c', 'o', 'm', 0, 0, 1, 0, 1
};

static struct sockaddr_in resolver(void)
{
    struct sockaddr_in a;
    memset(&a, 0, sizeof a);
    a.sin_family = AF_INET;
    a.sin_port = htons(53);
    inet_pton(AF_INET, "10.0.2.3", &a.sin_addr);
    return a;
}

static int answered(int fd, int ms)
{
    unsigned char b[512];
    struct pollfd p = { fd, POLLIN, 0 };
    if (poll(&p, 1, ms) != 1 || !(p.revents & POLLIN))
        return -1;
    ssize_t n = recv(fd, b, sizeof b, 0);
    if (n < 12 || b[0] != 0x12 || b[1] != 0x34 || !(b[2] & 0x80))
        return -2;
    return (int)n;
}

int main(void)
{
    struct sockaddr_in dst = resolver();
    struct sockaddr_in me;
    socklen_t ml = sizeof me;

    int a = socket(AF_INET, SOCK_DGRAM, 0);
    CHECKC("socket", a >= 0);
    if (a < 0) return 0;
    memset(&me, 0, sizeof me);
    me.sin_family = AF_INET;
    errno = 0;
    CHECKC("bind_port0", bind(a, (struct sockaddr *)&me, sizeof me) == 0);
    ml = sizeof me;
    errno = 0;
    int gs = getsockname(a, (struct sockaddr *)&me, &ml);
    CHECK("bind_port0_ephemeral", gs == 0 && ntohs(me.sin_port) != 0, "port=%d", ntohs(me.sin_port));

    errno = 0;
    CHECKC("sendto", sendto(a, query, sizeof query, 0, (struct sockaddr *)&dst, sizeof dst) == (ssize_t)sizeof query);
    int r = answered(a, 8000);
    CHECK("sendto_poll_recv", r > 0, "answer=%d", r);

    int b = socket(AF_INET, SOCK_DGRAM, 0);
    errno = 0;
    CHECKC("connect", connect(b, (struct sockaddr *)&dst, sizeof dst) == 0);
    struct sockaddr_in peer;
    socklen_t pl = sizeof peer;
    memset(&peer, 0, sizeof peer);
    errno = 0;
    int gp = getpeername(b, (struct sockaddr *)&peer, &pl);
    CHECK("connect_getpeername", gp == 0 && peer.sin_addr.s_addr == dst.sin_addr.s_addr && ntohs(peer.sin_port) == 53,
          "rc=%d port=%d", gp, ntohs(peer.sin_port));
    ml = sizeof me;
    getsockname(b, (struct sockaddr *)&me, &ml);
    CHECK("connect_keeps_local_port", ntohs(me.sin_port) != 0 && ntohs(me.sin_port) != 53, "port=%d", ntohs(me.sin_port));
    errno = 0;
    CHECKC("connected_send", send(b, query, sizeof query, 0) == (ssize_t)sizeof query);
    r = answered(b, 8000);
    CHECK("connected_send_recv", r > 0, "answer=%d", r);
    errno = 0;
    CHECKC("connected_write", write(b, query, sizeof query) == (ssize_t)sizeof query);
    r = answered(b, 8000);
    CHECK("connected_write_recv", r > 0, "answer=%d", r);

    int d = socket(AF_INET, SOCK_DGRAM, 0);
    struct iovec siov = { (void *)query, sizeof query };
    struct msghdr sm;
    memset(&sm, 0, sizeof sm);
    sm.msg_name = &dst;
    sm.msg_namelen = sizeof dst;
    sm.msg_iov = &siov;
    sm.msg_iovlen = 1;
    errno = 0;
    CHECKC("sendmsg", sendmsg(d, &sm, 0) == (ssize_t)sizeof query);
    unsigned char rb[512];
    struct sockaddr_in from;
    struct iovec riov = { rb, sizeof rb };
    struct msghdr rm;
    memset(&rm, 0, sizeof rm);
    memset(&from, 0, sizeof from);
    rm.msg_name = &from;
    rm.msg_namelen = sizeof from;
    rm.msg_iov = &riov;
    rm.msg_iovlen = 1;
    struct pollfd dp = { d, POLLIN, 0 };
    int pr = poll(&dp, 1, 8000);
    errno = 0;
    ssize_t rn = pr == 1 ? recvmsg(d, &rm, 0) : -1;
    CHECK("recvmsg", rn > 12 && rb[0] == 0x12 && (rb[2] & 0x80), "rc=%zd poll=%d errno=%d", rn, pr, errno);
    CHECK("recvmsg_source_address", rn > 0 && from.sin_addr.s_addr == dst.sin_addr.s_addr && ntohs(from.sin_port) == 53, "port=%d", ntohs(from.sin_port));

    int c = socket(AF_INET, SOCK_DGRAM, 0);
    errno = 0;
    ssize_t w = send(c, query, sizeof query, 0);
    CHECK("unconnected_send_refused", w == -1 && errno == EDESTADDRREQ, "rc=%zd errno=%d", w, errno);
    return 0;
}
