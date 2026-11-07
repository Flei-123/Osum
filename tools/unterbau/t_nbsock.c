#define TNAME "nbsock"
#include "t.h"
#include <fcntl.h>
#include <poll.h>
#include <stdlib.h>
#include <string.h>
#include <sys/ioctl.h>
#include <sys/socket.h>
#include <netinet/in.h>
#include <arpa/inet.h>
#include <time.h>

#define ECHO_IP "10.0.2.100"
#define ECHO_PORT 7777
#define EAGAIN_LIMIT_US 1000000
#define ECHO_WAIT_MS 5000

static long now_us(void)
{
    struct timespec t;
    clock_gettime(CLOCK_MONOTONIC, &t);
    return t.tv_sec * 1000000L + t.tv_nsec / 1000;
}

static int connected_socket(void)
{
    struct sockaddr_in ea;
    memset(&ea, 0, sizeof ea);
    ea.sin_family = AF_INET;
    ea.sin_port = htons(ECHO_PORT);
    ea.sin_addr.s_addr = inet_addr(ECHO_IP);
    int s = socket(AF_INET, SOCK_STREAM, 0);
    if (s < 0 || connect(s, (void *)&ea, sizeof ea) < 0)
        return -1;
    return s;
}

static long timed_recv_flags(int s, int flags, int *err)
{
    char c;
    long t0 = now_us();
    errno = 0;
    long r = recv(s, &c, 1, flags);
    *err = errno;
    long dt = now_us() - t0;
    return r == -1 && *err == EAGAIN ? dt : -1;
}

static void check_eagain_flags(const char *name, int s, int flags)
{
    int err;
    long dt = timed_recv_flags(s, flags, &err);
    if (dt >= 0 && dt < EAGAIN_LIMIT_US)
        PASS(name, "us=%ld", dt);
    else
        FAIL(name, "us=%ld errno=%d", dt, err);
}

static void check_eagain(const char *name, int s)
{
    check_eagain_flags(name, s, 0);
}

static void tcp_setfl(void)
{
    int s = connected_socket();
    if (s < 0) {
        GAP("setfl_recv_eagain", "no echo peer");
        return;
    }
    fcntl(s, F_SETFL, fcntl(s, F_GETFL) | O_NONBLOCK);
    check_eagain("setfl_recv_eagain", s);
    fcntl(s, F_SETFL, fcntl(s, F_GETFL) & ~O_NONBLOCK);
    char c = 'x', back = 0;
    struct pollfd p = { s, POLLIN, 0 };
    send(s, &c, 1, 0);
    long r = poll(&p, 1, ECHO_WAIT_MS) == 1 ? recv(s, &back, 1, 0) : -1;
    CHECK("setfl_clear_blocks_again", r == 1 && back == 'x', "r=%ld back=%d", r, back);
    close(s);
}

static void tcp_fionbio(void)
{
    int s = connected_socket();
    if (s < 0) {
        GAP("fionbio_recv_eagain", "no echo peer");
        return;
    }
    int on = 1;
    ioctl(s, FIONBIO, &on);
    check_eagain("fionbio_recv_eagain", s);
    close(s);
}

static void tcp_creation_flag(void)
{
    int s = socket(AF_INET, SOCK_STREAM | SOCK_NONBLOCK, 0);
    int fl = fcntl(s, F_GETFL);
    CHECK("sock_nonblock_getfl", s >= 0 && (fl & O_NONBLOCK), "fl=%d", fl);
    close(s);
}

static void udp_setfl(void)
{
    struct sockaddr_in a;
    memset(&a, 0, sizeof a);
    a.sin_family = AF_INET;
    a.sin_port = htons(40123);
    int s = socket(AF_INET, SOCK_DGRAM, 0);
    bind(s, (void *)&a, sizeof a);
    fcntl(s, F_SETFL, fcntl(s, F_GETFL) | O_NONBLOCK);
    check_eagain("udp_setfl_recv_eagain", s);
    close(s);
}

static void tcp_msg_dontwait(void)
{
    int s = connected_socket();
    if (s < 0) {
        GAP("msg_dontwait_tcp_eagain", "no echo peer");
        return;
    }
    check_eagain_flags("msg_dontwait_tcp_eagain", s, MSG_DONTWAIT);
    char c = 'y', back = 0;
    struct pollfd p = { s, POLLIN, 0 };
    send(s, &c, 1, MSG_DONTWAIT);
    long r = poll(&p, 1, ECHO_WAIT_MS) == 1 ? recv(s, &back, 1, MSG_DONTWAIT) : -1;
    CHECK("msg_dontwait_tcp_data", r == 1 && back == 'y', "r=%ld back=%d", r, back);
    close(s);
}

static void udp_msg_dontwait(void)
{
    struct sockaddr_in a;
    memset(&a, 0, sizeof a);
    a.sin_family = AF_INET;
    a.sin_port = htons(40124);
    int s = socket(AF_INET, SOCK_DGRAM, 0);
    bind(s, (void *)&a, sizeof a);
    check_eagain_flags("msg_dontwait_udp_eagain", s, MSG_DONTWAIT);
    close(s);
}

static void unix_msg_dontwait(void)
{
    int sv[2];
    if (socketpair(AF_UNIX, SOCK_STREAM, 0, sv) < 0) {
        GAP("msg_dontwait_unix_eagain", "no socketpair");
        return;
    }
    check_eagain_flags("msg_dontwait_unix_eagain", sv[0], MSG_DONTWAIT);
    close(sv[0]);
    close(sv[1]);
}

static void tcp_recvfrom_dontwait(void)
{
    int s = connected_socket();
    if (s < 0) {
        GAP("msg_dontwait_recvfrom_eagain", "no echo peer");
        return;
    }
    char c;
    struct sockaddr_in from;
    socklen_t fl = sizeof from;
    long t0 = now_us();
    errno = 0;
    long r = recvfrom(s, &c, 1, MSG_DONTWAIT, (void *)&from, &fl);
    long dt = now_us() - t0;
    CHECK("msg_dontwait_recvfrom_eagain", r == -1 && errno == EAGAIN && dt < EAGAIN_LIMIT_US, "r=%ld errno=%d us=%ld", r, errno, dt);
    close(s);
}

int main(void)
{
    tcp_creation_flag();
    udp_setfl();
    tcp_setfl();
    tcp_fionbio();
    tcp_msg_dontwait();
    udp_msg_dontwait();
    unix_msg_dontwait();
    tcp_recvfrom_dontwait();
    return 0;
}
