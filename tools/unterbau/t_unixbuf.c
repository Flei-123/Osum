#define TNAME "unixbuf"
#include "t.h"
#include <fcntl.h>
#include <poll.h>
#include <stdlib.h>
#include <sys/socket.h>
#include <sys/wait.h>
#include <unistd.h>

#define BIG (192 * 1024)
#define MIN_CAPACITY (64 * 1024)
#define ROUNDS 64

static unsigned char pattern(size_t i, unsigned seed)
{
    return (unsigned char)((i * 131 + seed * 7 + (i >> 9)) & 0xff);
}

static void fill(unsigned char *b, size_t n, unsigned seed)
{
    for (size_t i = 0; i < n; i++)
        b[i] = pattern(i, seed);
}

static size_t first_bad(const unsigned char *b, size_t n, unsigned seed)
{
    for (size_t i = 0; i < n; i++)
        if (b[i] != pattern(i, seed))
            return i;
    return n;
}

static size_t read_all(int fd, unsigned char *b, size_t n)
{
    size_t got = 0;
    while (got < n) {
        ssize_t r = read(fd, b + got, n - got);
        if (r <= 0)
            break;
        got += (size_t)r;
    }
    return got;
}

static void check_capacity(void)
{
    int sv[2];
    if (socketpair(AF_UNIX, SOCK_STREAM, 0, sv) != 0) {
        FAIL("capacity", "socketpair errno=%d", errno);
        return;
    }
    fcntl(sv[0], F_SETFL, O_NONBLOCK);
    unsigned char *out = malloc(BIG), *in = malloc(BIG);
    fill(out, BIG, 1);
    size_t sent = 0;
    int eagain = 0;
    while (sent < BIG) {
        ssize_t w = write(sv[0], out + sent, BIG - sent);
        if (w < 0) {
            eagain = errno == EAGAIN;
            break;
        }
        sent += (size_t)w;
    }
    CHECK("capacity", sent >= MIN_CAPACITY, "sent=%zu before EAGAIN", sent);
    CHECK("full_is_eagain", sent == BIG || eagain, "errno=%d", errno);
    struct pollfd p = { .fd = sv[1], .events = POLLIN };
    CHECK("poll_in", poll(&p, 1, 0) == 1 && (p.revents & POLLIN), "revents=%x", p.revents);
    size_t got = read_all(sv[1], in, sent);
    CHECK("roundtrip", got == sent && first_bad(in, got, 1) == got, "got=%zu sent=%zu bad=%zu", got, sent, first_bad(in, got, 1));
    struct pollfd q = { .fd = sv[0], .events = POLLOUT };
    CHECK("poll_out_after_drain", poll(&q, 1, 0) == 1 && (q.revents & POLLOUT), "revents=%x", q.revents);
    free(out);
    free(in);
    close(sv[0]);
    close(sv[1]);
}

static void check_stream_child(void)
{
    int sv[2];
    socketpair(AF_UNIX, SOCK_STREAM, 0, sv);
    pid_t c = fork();
    if (c == 0) {
        close(sv[1]);
        unsigned char *b = malloc(BIG);
        for (unsigned r = 0; r < ROUNDS; r++) {
            size_t n = 1000 + (r * 7919) % (BIG - 1000);
            fill(b, n, r);
            size_t s = 0;
            while (s < n) {
                ssize_t w = write(sv[0], b + s, n - s);
                if (w <= 0)
                    _exit(2);
                s += (size_t)w;
            }
        }
        _exit(0);
    }
    close(sv[0]);
    unsigned char *b = malloc(BIG);
    unsigned bad = 0;
    for (unsigned r = 0; r < ROUNDS; r++) {
        size_t n = 1000 + (r * 7919) % (BIG - 1000);
        if (read_all(sv[1], b, n) != n || first_bad(b, n, r) != n)
            bad++;
    }
    int st = 0;
    waitpid(c, &st, 0);
    CHECK("bulk_stream", bad == 0 && WIFEXITED(st) && WEXITSTATUS(st) == 0, "bad=%u status=%x", bad, st);
    free(b);
    close(sv[1]);
}

static int send_with_fd(int s, const void *buf, size_t n, int fd)
{
    char ctl[CMSG_SPACE(sizeof(int))];
    memset(ctl, 0, sizeof ctl);
    struct iovec iov = { .iov_base = (void *)buf, .iov_len = n };
    struct msghdr m = { .msg_iov = &iov, .msg_iovlen = 1, .msg_control = ctl, .msg_controllen = sizeof ctl };
    struct cmsghdr *c = CMSG_FIRSTHDR(&m);
    c->cmsg_level = SOL_SOCKET;
    c->cmsg_type = SCM_RIGHTS;
    c->cmsg_len = CMSG_LEN(sizeof(int));
    memcpy(CMSG_DATA(c), &fd, sizeof fd);
    return (int)sendmsg(s, &m, 0);
}

static ssize_t recv_with_fd(int s, void *buf, size_t n, int *fd)
{
    char ctl[CMSG_SPACE(sizeof(int))];
    struct iovec iov = { .iov_base = buf, .iov_len = n };
    struct msghdr m = { .msg_iov = &iov, .msg_iovlen = 1, .msg_control = ctl, .msg_controllen = sizeof ctl };
    *fd = -1;
    ssize_t r = recvmsg(s, &m, 0);
    struct cmsghdr *c = CMSG_FIRSTHDR(&m);
    if (r > 0 && c && c->cmsg_type == SCM_RIGHTS)
        memcpy(fd, CMSG_DATA(c), sizeof *fd);
    return r;
}

static void check_fd_boundaries(void)
{
    int sv[2];
    socketpair(AF_UNIX, SOCK_STREAM, 0, sv);
    size_t sizes[3] = { 5000, 9000, 4096 * 3 + 17 };
    unsigned char *b = malloc(BIG);
    int ok = 1;
    for (int k = 0; k < 3; k++) {
        fill(b, sizes[k], 40 + k);
        int pipefd[2];
        pipe(pipefd);
        if (send_with_fd(sv[0], b, sizes[k], pipefd[0]) != (int)sizes[k])
            ok = 0;
        close(pipefd[0]);
        close(pipefd[1]);
    }
    for (int k = 0; k < 3 && ok; k++) {
        size_t got = 0;
        int fds = 0;
        while (got < sizes[k]) {
            int fd;
            ssize_t r = recv_with_fd(sv[1], b + got, sizes[k] - got, &fd);
            if (r <= 0) {
                ok = 0;
                break;
            }
            if (fd >= 0) {
                fds++;
                if (got != 0)
                    ok = 0;
                close(fd);
            }
            got += (size_t)r;
        }
        if (fds != 1 || first_bad(b, sizes[k], 40 + k) != sizes[k])
            ok = 0;
    }
    CHECK("fd_at_message_start", ok, "descriptor or data out of place");
    free(b);
    close(sv[0]);
    close(sv[1]);
}

int main(void)
{
    check_capacity();
    check_stream_child();
    check_fd_boundaries();
    return 0;
}
