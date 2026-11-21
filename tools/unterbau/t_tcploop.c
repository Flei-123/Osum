#define TNAME "tcploop"
#include "t.h"
#include <arpa/inet.h>
#include <fcntl.h>
#include <netinet/in.h>
#include <poll.h>
#include <sys/socket.h>
#include <sys/wait.h>

#define PORT 5601
#define BULK 262144

static struct sockaddr_in loop_addr(int port)
{
    struct sockaddr_in a;
    memset(&a, 0, sizeof a);
    a.sin_family = AF_INET;
    a.sin_port = htons(port);
    inet_pton(AF_INET, "127.0.0.1", &a.sin_addr);
    return a;
}

static int make_listener(int port)
{
    struct sockaddr_in a = loop_addr(port);
    int l = socket(AF_INET, SOCK_STREAM, 0);
    if (l < 0) return -1;
    if (bind(l, (struct sockaddr *)&a, sizeof a) != 0 || listen(l, 4) != 0) {
        close(l);
        return -1;
    }
    return l;
}

static int dial(int port)
{
    struct sockaddr_in a = loop_addr(port);
    int c = socket(AF_INET, SOCK_STREAM, 0);
    if (c < 0) return -1;
    if (connect(c, (struct sockaddr *)&a, sizeof a) != 0) {
        int e = errno;
        close(c);
        errno = e;
        return -1;
    }
    return c;
}

static ssize_t read_full(int fd, char *buf, size_t n)
{
    size_t got = 0;
    while (got < n) {
        ssize_t r = read(fd, buf + got, n - got);
        if (r <= 0) return got ? (ssize_t)got : r;
        got += r;
    }
    return got;
}

static int write_full(int fd, const char *buf, size_t n)
{
    size_t put = 0;
    while (put < n) {
        ssize_t w = write(fd, buf + put, n - put);
        if (w <= 0) return -1;
        put += w;
    }
    return 0;
}

static void echo_roundtrip(void)
{
    int l = make_listener(PORT);
    CHECK("loop_listen", l >= 0, "errno=%d", errno);
    if (l < 0) return;
    int c = dial(PORT);
    CHECK("loop_connect", c >= 0, "errno=%d", errno);
    if (c < 0) {
        close(l);
        return;
    }
    int a = accept(l, 0, 0);
    CHECK("loop_accept", a >= 0, "errno=%d", errno);
    char buf[16];
    CHECK("loop_client_to_server", write(c, "ping", 4) == 4 && read_full(a, buf, 4) == 4 && memcmp(buf, "ping", 4) == 0, "errno=%d", errno);
    CHECK("loop_server_to_client", write(a, "pong!", 5) == 5 && read_full(c, buf, 5) == 5 && memcmp(buf, "pong!", 5) == 0, "errno=%d", errno);
    close(c);
    ssize_t eof = read(a, buf, sizeof buf);
    CHECK("loop_eof_after_peer_close", eof == 0, "r=%zd errno=%d", eof, errno);
    close(a);
    close(l);
}

static void bulk_transfer(void)
{
    int l = make_listener(PORT + 1);
    if (l < 0) {
        GAP("bulk_listen", "errno=%d", errno);
        return;
    }
    pid_t pid = fork();
    if (pid == 0) {
        int c = dial(PORT + 1);
        if (c < 0) _exit(2);
        char chunk[4096];
        for (size_t i = 0; i < sizeof chunk; i++) chunk[i] = (char)(i * 7);
        for (int sent = 0; sent < BULK; sent += sizeof chunk)
            if (write_full(c, chunk, sizeof chunk) != 0) _exit(3);
        close(c);
        _exit(0);
    }
    int a = accept(l, 0, 0);
    CHECK("bulk_accept", a >= 0, "errno=%d", errno);
    long total = 0;
    long sum = 0;
    char buf[4096];
    ssize_t r;
    while (a >= 0 && (r = read(a, buf, sizeof buf)) > 0) {
        for (ssize_t i = 0; i < r; i++) sum += (unsigned char)buf[i];
        total += r;
    }
    int status = 0;
    waitpid(pid, &status, 0);
    long expect = 0;
    for (int i = 0; i < 4096; i++) expect += (unsigned char)(char)(i * 7);
    expect *= BULK / 4096;
    CHECK("bulk_all_bytes", total == BULK, "total=%ld", total);
    CHECK("bulk_content_sum", sum == expect, "sum=%ld expect=%ld", sum, expect);
    CHECK("bulk_sender_clean_exit", WIFEXITED(status) && WEXITSTATUS(status) == 0, "status=%d", status);
    if (a >= 0) close(a);
    close(l);
}

static void refused_and_nonblocking(void)
{
    int c = dial(PORT + 9);
    CHECK("loop_refused", c < 0 && errno == ECONNREFUSED, "c=%d errno=%d", c, errno);
    if (c >= 0) close(c);
    int l = make_listener(PORT + 2);
    if (l < 0) {
        GAP("nb_listen", "errno=%d", errno);
        return;
    }
    struct sockaddr_in a = loop_addr(PORT + 2);
    int s = socket(AF_INET, SOCK_STREAM | SOCK_NONBLOCK, 0);
    int r = connect(s, (struct sockaddr *)&a, sizeof a);
    CHECK("nb_connect_inprogress_or_done", r == 0 || errno == EINPROGRESS, "r=%d errno=%d", r, errno);
    struct pollfd pw = { s, POLLOUT, 0 };
    CHECK("nb_connect_pollout", poll(&pw, 1, 3000) == 1 && (pw.revents & POLLOUT), "revents=%d", pw.revents);
    struct pollfd pl = { l, POLLIN, 0 };
    CHECK("nb_listener_pollin", poll(&pl, 1, 3000) == 1 && (pl.revents & POLLIN), "revents=%d", pl.revents);
    int acc = accept4(l, 0, 0, SOCK_NONBLOCK);
    int fl = acc >= 0 ? fcntl(acc, F_GETFL) : 0;
    CHECK("nb_accept4_flag", acc >= 0 && (fl & O_NONBLOCK), "acc=%d fl=%d", acc, fl);
    char buf[4];
    ssize_t e = acc >= 0 ? read(acc, buf, sizeof buf) : 0;
    CHECK("nb_read_eagain", e < 0 && errno == EAGAIN, "r=%zd errno=%d", e, errno);
    close(s);
    if (acc >= 0) close(acc);
    close(l);
}

static void names_and_udp(void)
{
    int l = make_listener(PORT + 3);
    if (l < 0) {
        GAP("names_listen", "errno=%d", errno);
        return;
    }
    int c = dial(PORT + 3);
    struct sockaddr_in me;
    socklen_t len = sizeof me;
    int r = c >= 0 ? getsockname(c, (struct sockaddr *)&me, &len) : -1;
    CHECK("loop_getsockname_port", r == 0 && ntohs(me.sin_port) != 0, "r=%d", r);
    CHECK("loop_getsockname_addr", r == 0 && me.sin_addr.s_addr == htonl(INADDR_LOOPBACK), "r=%d", r);
    struct sockaddr_in peer;
    socklen_t plen = sizeof peer;
    int pr = c >= 0 ? getpeername(c, (struct sockaddr *)&peer, &plen) : -1;
    CHECK("loop_getpeername_addr", pr == 0 && peer.sin_addr.s_addr == htonl(INADDR_LOOPBACK) && ntohs(peer.sin_port) == PORT + 3, "r=%d", pr);
    if (c >= 0) close(c);
    close(l);

    struct sockaddr_in ua = loop_addr(PORT + 4);
    int us = socket(AF_INET, SOCK_DGRAM, 0);
    int uc = socket(AF_INET, SOCK_DGRAM, 0);
    int br = bind(us, (struct sockaddr *)&ua, sizeof ua);
    ssize_t sn = sendto(uc, "dgram", 5, 0, (struct sockaddr *)&ua, sizeof ua);
    struct pollfd p = { us, POLLIN, 0 };
    char buf[16];
    int got = poll(&p, 1, 3000) == 1 ? (int)recv(us, buf, sizeof buf, 0) : -1;
    CHECK("loop_udp_roundtrip", br == 0 && sn == 5 && got == 5 && memcmp(buf, "dgram", 5) == 0, "bind=%d sent=%zd got=%d errno=%d", br, sn, got, errno);
    close(us);
    close(uc);
}

static void blocking_send_full(void)
{
    int l = make_listener(PORT + 5);
    if (l < 0) {
        GAP("send_listen", "errno=%d", errno);
        return;
    }
    int done[2];
    if (pipe(done) != 0) {
        close(l);
        return;
    }
    pid_t pid = fork();
    if (pid == 0) {
        int c = dial(PORT + 5);
        if (c < 0) _exit(2);
        static char big[BULK];
        memset(big, 'y', sizeof big);
        ssize_t w = send(c, big, sizeof big, 0);
        char go;
        if (read(done[0], &go, 1) < 0) _exit(4);
        _exit(w == (ssize_t)sizeof big ? 0 : 3);
    }
    int a = accept(l, 0, 0);
    long total = 0;
    char buf[4096];
    ssize_t r = 0;
    while (a >= 0 && total < BULK && (r = read(a, buf, sizeof buf)) > 0) total += r;
    if (write(done[1], "g", 1) != 1) total = -1;
    int status = 0;
    waitpid(pid, &status, 0);
    CHECK("send_blocking_full_count", WIFEXITED(status) && WEXITSTATUS(status) == 0, "status=%d", status);
    CHECK("send_blocking_all_bytes", total == BULK, "total=%ld a=%d errno=%d r=%zd", total, a, errno, r);
    if (a >= 0) close(a);
    close(l);
    close(done[0]);
    close(done[1]);
}

static void stale_child_after_listener_close(void)
{
    int l = make_listener(PORT + 6);
    if (l < 0) {
        GAP("stale_listen", "errno=%d", errno);
        return;
    }
    int c = dial(PORT + 6);
    close(c);
    close(l);
    int l2 = make_listener(PORT + 7);
    int c2 = dial(PORT + 7);
    int a = accept(l2, 0, 0);
    char buf[8];
    CHECK("stale_child_not_inherited", a >= 0 && write(c2, "live", 4) == 4 && read_full(a, buf, 4) == 4 && memcmp(buf, "live", 4) == 0, "a=%d errno=%d", a, errno);
    struct pollfd p = { l2, POLLIN, 0 };
    CHECK("stale_listener_queue_empty", poll(&p, 1, 0) == 0, "revents=%d", p.revents);
    if (a >= 0) close(a);
    close(c2);
    close(l2);
}

static int any_listener(int port)
{
    struct sockaddr_in a;
    memset(&a, 0, sizeof a);
    a.sin_family = AF_INET;
    a.sin_port = htons(port);
    int l = socket(AF_INET, SOCK_STREAM, 0);
    if (l < 0) return -1;
    if (bind(l, (struct sockaddr *)&a, sizeof a) != 0 || listen(l, 4) != 0) {
        close(l);
        return -1;
    }
    return l;
}

static int dial_ip(const char *ip, int port)
{
    struct sockaddr_in a = loop_addr(port);
    inet_pton(AF_INET, ip, &a.sin_addr);
    int c = socket(AF_INET, SOCK_STREAM, 0);
    if (c < 0) return -1;
    if (connect(c, (struct sockaddr *)&a, sizeof a) != 0) {
        close(c);
        return -1;
    }
    return c;
}

static int name_is(int fd, int peer, const char *ip)
{
    struct sockaddr_in a;
    socklen_t len = sizeof a;
    int r = peer ? getpeername(fd, (struct sockaddr *)&a, &len) : getsockname(fd, (struct sockaddr *)&a, &len);
    char text[32];
    return r == 0 && inet_ntop(AF_INET, &a.sin_addr, text, sizeof text) && strcmp(text, ip) == 0;
}

static void accepted_names(void)
{
    int l = any_listener(PORT + 8);
    if (l < 0) {
        GAP("accnames_listen", "errno=%d", errno);
        return;
    }
    int c = dial_ip("127.0.0.1", PORT + 8);
    int a = c >= 0 ? accept(l, 0, 0) : -1;
    CHECK("accnames_loop_accepted_peer", a >= 0 && name_is(a, 1, "127.0.0.1"), "a=%d", a);
    CHECK("accnames_loop_accepted_local", a >= 0 && name_is(a, 0, "127.0.0.1"), "a=%d", a);
    if (a >= 0) close(a);
    if (c >= 0) close(c);
    int c2 = dial_ip("10.0.2.15", PORT + 8);
    int a2 = c2 >= 0 ? accept(l, 0, 0) : -1;
    if (c2 < 0) {
        GAP("accnames_ip_connect", "errno=%d", errno);
        close(l);
        return;
    }
    CHECK("accnames_ip_accepted_peer", a2 >= 0 && name_is(a2, 1, "10.0.2.15"), "a=%d", a2);
    CHECK("accnames_ip_accepted_local", a2 >= 0 && name_is(a2, 0, "10.0.2.15"), "a=%d", a2);
    CHECK("accnames_ip_client_peer", name_is(c2, 1, "10.0.2.15"), "c=%d", c2);
    if (a2 >= 0) close(a2);
    close(c2);
    close(l);
}

int main(void)
{
    accepted_names();
    blocking_send_full();
    echo_roundtrip();
    bulk_transfer();
    refused_and_nonblocking();
    names_and_udp();
    stale_child_after_listener_close();
    return 0;
}
