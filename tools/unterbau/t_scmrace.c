#define TNAME "scmrace"
#include "t.h"
#include <fcntl.h>
#include <stdint.h>
#include <stdlib.h>
#include <sys/socket.h>
#include <sys/wait.h>
#include <time.h>

#define PAIRS 3
#define SECONDS 5
#define MAX_FDS 8
#define PAYLOAD_MAX 96
#define END_SEQ 0xFFFFFFFFu
#define RBUF 4096

struct header { uint32_t len, seq, nfd, pad; };
struct result { unsigned long msgs, bad_stream, bad_fd, ctrunc, short_fds; };

static int elapsed(struct timespec *t0)
{
    struct timespec t1;
    clock_gettime(CLOCK_MONOTONIC, &t1);
    return t1.tv_sec - t0->tv_sec >= SECONDS;
}

static int make_tagged_fd(uint32_t seq)
{
    int p[2];
    if (pipe(p) != 0) return -1;
    (void)!write(p[1], &seq, sizeof seq);
    close(p[1]);
    return p[0];
}

static int send_message(int sock, uint32_t seq, uint32_t nfd)
{
    char payload[PAYLOAD_MAX];
    struct header h = { sizeof h + PAYLOAD_MAX, seq, nfd, 0 };
    for (int i = 0; i < PAYLOAD_MAX; i++) payload[i] = (char)(seq + i);
    struct iovec iov[2] = { { &h, sizeof h }, { payload, PAYLOAD_MAX } };
    union { char buf[CMSG_SPACE(sizeof(int) * MAX_FDS)]; struct cmsghdr align; } ctl;
    struct msghdr mh = { 0 };
    mh.msg_iov = iov;
    mh.msg_iovlen = 2;
    int fds[MAX_FDS];
    for (uint32_t i = 0; i < nfd; i++) fds[i] = make_tagged_fd(seq);
    if (nfd) {
        memset(&ctl, 0, sizeof ctl);
        mh.msg_control = ctl.buf;
        mh.msg_controllen = CMSG_SPACE(sizeof(int) * nfd);
        struct cmsghdr *c = CMSG_FIRSTHDR(&mh);
        c->cmsg_level = SOL_SOCKET;
        c->cmsg_type = SCM_RIGHTS;
        c->cmsg_len = CMSG_LEN(sizeof(int) * nfd);
        memcpy(CMSG_DATA(c), fds, sizeof(int) * nfd);
    }
    ssize_t n = sendmsg(sock, &mh, 0);
    for (uint32_t i = 0; i < nfd; i++) close(fds[i]);
    return n == (ssize_t)(sizeof h + PAYLOAD_MAX) ? 0 : -1;
}

static void sender(int sock)
{
    struct timespec t0;
    clock_gettime(CLOCK_MONOTONIC, &t0);
    uint32_t seq = 0;
    while (!elapsed(&t0)) {
        uint32_t nfd = seq % 3 == 0 ? 1 + (seq / 3) % 2 : 0;
        if (send_message(sock, seq, nfd) != 0) break;
        seq++;
    }
    send_message(sock, END_SEQ, 0);
    close(sock);
}

struct receiver {
    int sock;
    int queue[64];
    int qhead, qtail;
    struct result res;
};

static void take_fds(struct receiver *r, struct msghdr *mh)
{
    if (mh->msg_flags & MSG_CTRUNC) r->res.ctrunc++;
    for (struct cmsghdr *c = CMSG_FIRSTHDR(mh); c; c = CMSG_NXTHDR(mh, c)) {
        if (c->cmsg_level != SOL_SOCKET || c->cmsg_type != SCM_RIGHTS) continue;
        int n = (c->cmsg_len - CMSG_LEN(0)) / sizeof(int);
        int fds[MAX_FDS];
        memcpy(fds, CMSG_DATA(c), n * sizeof(int));
        for (int i = 0; i < n; i++) r->queue[r->qtail++ % 64] = fds[i];
    }
}

static int check_message(struct receiver *r, const struct header *h, const char *payload)
{
    for (int i = 0; i < PAYLOAD_MAX; i++)
        if (payload[i] != (char)(h->seq + i)) { r->res.bad_stream++; break; }
    for (uint32_t i = 0; i < h->nfd; i++) {
        if (r->qhead == r->qtail) { r->res.short_fds++; return -1; }
        int fd = r->queue[r->qhead++ % 64];
        uint32_t tag = 0;
        if (read(fd, &tag, sizeof tag) != sizeof tag || tag != h->seq) r->res.bad_fd++;
        close(fd);
    }
    r->res.msgs++;
    return 0;
}

static void receiver(int sock, int out)
{
    struct receiver r = { .sock = sock };
    static char buf[RBUF * 2];
    size_t have = 0;
    int done = 0;
    while (!done) {
        union { char buf[CMSG_SPACE(sizeof(int) * MAX_FDS)]; struct cmsghdr align; } ctl;
        struct iovec iov = { buf + have, RBUF };
        struct msghdr mh = { 0 };
        mh.msg_iov = &iov;
        mh.msg_iovlen = 1;
        mh.msg_control = ctl.buf;
        mh.msg_controllen = sizeof ctl.buf;
        ssize_t n = recvmsg(sock, &mh, 0);
        if (n <= 0) break;
        take_fds(&r, &mh);
        have += n;
        size_t off = 0;
        while (have - off >= sizeof(struct header)) {
            struct header h;
            memcpy(&h, buf + off, sizeof h);
            if (h.len != sizeof h + PAYLOAD_MAX) { r.res.bad_stream++; done = 1; break; }
            if (have - off < h.len) break;
            if (h.seq == END_SEQ) { done = 1; break; }
            if (check_message(&r, &h, buf + off + sizeof h) != 0) { done = 1; break; }
            off += h.len;
        }
        memmove(buf, buf + off, have - off);
        have -= off;
    }
    (void)!write(out, &r.res, sizeof r.res);
    close(out);
}

int main(void)
{
    int results[PAIRS];
    for (int i = 0; i < PAIRS; i++) {
        int sv[2], rp[2];
        if (socketpair(AF_UNIX, SOCK_STREAM, 0, sv) != 0 || pipe(rp) != 0) { FAIL("setup", "errno=%d", errno); return 0; }
        if (fork() == 0) { close(sv[0]); close(rp[0]); sender(sv[1]); _exit(0); }
        if (fork() == 0) { close(sv[1]); close(rp[0]); receiver(sv[0], rp[1]); _exit(0); }
        close(sv[0]);
        close(sv[1]);
        close(rp[1]);
        results[i] = rp[0];
    }
    struct result total = { 0 };
    int missing = 0;
    for (int i = 0; i < PAIRS; i++) {
        struct result r;
        if (read(results[i], &r, sizeof r) != sizeof r) { missing++; continue; }
        total.msgs += r.msgs;
        total.bad_stream += r.bad_stream;
        total.bad_fd += r.bad_fd;
        total.ctrunc += r.ctrunc;
        total.short_fds += r.short_fds;
    }
    while (wait(0) > 0) {}
    CHECK("reports", missing == 0, "missing=%d", missing);
    CHECK("rounds", total.msgs > 500, "msgs=%lu", total.msgs);
    CHECK("stream", total.bad_stream == 0, "bad=%lu of %lu", total.bad_stream, total.msgs);
    CHECK("fd_identity", total.bad_fd == 0, "bad=%lu of %lu", total.bad_fd, total.msgs);
    CHECK("fd_complete", total.short_fds == 0, "short=%lu of %lu", total.short_fds, total.msgs);
    CHECK("no_ctrunc", total.ctrunc == 0, "ctrunc=%lu of %lu", total.ctrunc, total.msgs);
    return 0;
}
