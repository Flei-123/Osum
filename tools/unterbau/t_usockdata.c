#define TNAME "usockdata"
#include "t.h"
#include <fcntl.h>
#include <poll.h>
#include <pthread.h>
#include <signal.h>
#include <stdint.h>
#include <stdlib.h>
#include <sys/epoll.h>
#include <sys/mman.h>
#include <sys/socket.h>
#include <sys/uio.h>
#include <sys/wait.h>
#include <time.h>

#define WATCHDOG_SECONDS 45
#define IO_WAIT_MS 20000
#define MAX_PIECE 262144
#define RING_EDGE 212992
#define SEQ_MAX_MSG 3600
#define SEQ_FRAME_OK 2048
#define SCM_MAX_FDS 4

enum { W_WRITE, W_WRITEV3, W_SENDMSG3, W_SEND_NB, W_WRITE_NB };
enum { R_READ, R_READ_SMALL, R_READ_NB, R_RECVMSG3, R_EPOLL_LT, R_EPOLL_ET, R_PEEK_MIX };
enum { RES_RUN, RES_OK, RES_MISMATCH, RES_STALL, RES_SYSERR, RES_SHORT, RES_EXTRA };

struct result {
    volatile int state;
    uint64_t off;
    unsigned expect;
    unsigned got;
    long piece;
    long prev_piece;
    int err;
    uint64_t bytes;
};

struct chan {
    int wfd;
    int rfd;
    int wmode;
    int rmode;
    int is_socket;
    uint64_t total;
    uint32_t salt;
    uint32_t seed;
    size_t maxw;
    size_t maxr;
    int wjitter;
};

struct job {
    struct chan c;
    struct result *wres;
    struct result *rres;
};

static volatile uint64_t g_progress_ms;
static volatile int g_case_active;
static const char *g_case_name = "none";

static uint64_t now_ms(void)
{
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return (uint64_t)ts.tv_sec * 1000 + ts.tv_nsec / 1000000;
}

static void progress(void)
{
    g_progress_ms = now_ms();
}

static void *watchdog(void *arg)
{
    (void)arg;
    for (;;) {
        sleep(2);
        if (g_case_active && now_ms() - g_progress_ms > WATCHDOG_SECONDS * 1000ULL) {
            FAIL("watchdog_stall", "case %s made no progress for %d s", g_case_name, WATCHDOG_SECONDS);
            _exit(0);
        }
    }
    return NULL;
}

static uint32_t next_random(uint32_t *s)
{
    uint32_t x = *s;
    x ^= x << 13;
    x ^= x >> 17;
    x ^= x << 5;
    return *s = x;
}

static inline uint8_t pat(uint64_t off, uint32_t salt)
{
    uint64_t x = (off ^ ((uint64_t)salt << 40)) * 0x9E3779B97F4A7C15ULL;
    x ^= x >> 29;
    x *= 0xBF58476D1CE4E5B9ULL;
    return (uint8_t)(x >> 56);
}

static void fill(uint8_t *b, uint64_t off, size_t n, uint32_t salt)
{
    for (size_t i = 0; i < n; i++)
        b[i] = pat(off + i, salt);
}

static int verify(const uint8_t *b, uint64_t off, size_t n, uint32_t salt, struct result *r, long prev)
{
    for (size_t i = 0; i < n; i++) {
        uint8_t want = pat(off + i, salt);
        if (b[i] != want) {
            r->off = off + i;
            r->expect = want;
            r->got = b[i];
            r->piece = (long)n;
            r->prev_piece = prev;
            r->state = RES_MISMATCH;
            return 0;
        }
    }
    return 1;
}

static const size_t special_sizes[] = {1, 2, 4095, 4096, 4097, 8191, 8192, 65535, 65536, RING_EDGE - 1, RING_EDGE, RING_EDGE + 1, MAX_PIECE};

static size_t pick_size(uint32_t *rng, size_t max)
{
    uint32_t r = next_random(rng);
    uint32_t k = r % 100;
    size_t n;
    if (k < 10) {
        n = special_sizes[(r >> 8) % (sizeof special_sizes / sizeof special_sizes[0])];
    } else if (k < 35) {
        n = 1 + (r >> 8) % 16;
    } else if (k < 60) {
        n = 17 + (r >> 8) % 496;
    } else if (k < 85) {
        n = 513 + (r >> 8) % 7680;
    } else if (k < 95) {
        n = 8193 + (r >> 8) % 57344;
    } else {
        n = 65537 + (r >> 8) % 196608;
    }
    if (n > max)
        n = 1 + n % max;
    return n;
}

static int wait_fd(int fd, short ev, int ms)
{
    struct pollfd p = {fd, ev, 0};
    for (;;) {
        int r = poll(&p, 1, ms);
        if (r < 0 && errno == EINTR)
            continue;
        return r;
    }
}

static void set_nonblock(int fd)
{
    fcntl(fd, F_SETFL, fcntl(fd, F_GETFL) | O_NONBLOCK);
}

static ssize_t send_piece(struct chan *c, const uint8_t *p, size_t n, uint32_t *rng)
{
    struct iovec iov[3];
    struct msghdr mh;
    size_t a = n > 2 ? 1 + next_random(rng) % (n / 2) : n;
    size_t b = n > a + 1 ? 1 + next_random(rng) % ((n - a) / 2 + 1) : n - a;
    switch (c->wmode) {
    case W_WRITE:
        return write(c->wfd, p, n);
    case W_WRITE_NB:
        return write(c->wfd, p, n);
    case W_SEND_NB:
        return send(c->wfd, p, n, MSG_DONTWAIT);
    case W_WRITEV3:
    case W_SENDMSG3:
        iov[0].iov_base = (void *)p;
        iov[0].iov_len = a;
        iov[1].iov_base = (void *)(p + a);
        iov[1].iov_len = b;
        iov[2].iov_base = (void *)(p + a + b);
        iov[2].iov_len = n - a - b;
        if (c->wmode == W_WRITEV3)
            return writev(c->wfd, iov, 3);
        memset(&mh, 0, sizeof mh);
        mh.msg_iov = iov;
        mh.msg_iovlen = 3;
        return sendmsg(c->wfd, &mh, 0);
    }
    return -1;
}

static void run_writer(struct chan *c, struct result *res)
{
    uint8_t *buf = malloc(c->maxw + 16);
    uint32_t rng = c->seed ^ 0xa5a5a5a5u;
    uint64_t off = 0;
    if (c->wmode == W_WRITE_NB)
        set_nonblock(c->wfd);
    while (off < c->total) {
        size_t n = pick_size(&rng, c->maxw);
        if (n > c->total - off)
            n = c->total - off;
        fill(buf, off, n, c->salt);
        size_t done = 0;
        while (done < n) {
            ssize_t w = send_piece(c, buf + done, n - done, &rng);
            if (w < 0 && errno == EINTR)
                continue;
            if (w < 0 && errno == EAGAIN) {
                if (wait_fd(c->wfd, POLLOUT, IO_WAIT_MS) <= 0) {
                    res->off = off + done;
                    res->state = RES_STALL;
                    free(buf);
                    return;
                }
                continue;
            }
            if (w <= 0) {
                res->off = off + done;
                res->err = errno;
                res->state = RES_SYSERR;
                free(buf);
                return;
            }
            done += (size_t)w;
            res->bytes = off + done;
            progress();
        }
        off += n;
        if (c->wjitter && (next_random(&rng) % c->wjitter) == 0)
            usleep(1 + next_random(&rng) % 800);
    }
    free(buf);
    res->state = RES_OK;
}

static int split3(struct iovec *iov, uint8_t *buf, size_t want, uint32_t *rng)
{
    size_t a = want > 2 ? 1 + next_random(rng) % (want / 2) : want;
    size_t b = want > a + 1 ? 1 + next_random(rng) % ((want - a) / 2 + 1) : want - a;
    iov[0].iov_base = buf;
    iov[0].iov_len = a;
    iov[1].iov_base = buf + a;
    iov[1].iov_len = b;
    iov[2].iov_base = buf + a + b;
    iov[2].iov_len = want - a - b;
    return 3;
}

static ssize_t recv_piece(struct chan *c, uint8_t *buf, size_t want, uint32_t *rng, uint64_t off, struct result *res, long prev)
{
    struct iovec iov[3];
    struct msghdr mh;
    uint32_t r = next_random(rng);
    switch (c->rmode) {
    case R_READ:
    case R_READ_SMALL:
        return read(c->rfd, buf, want);
    case R_READ_NB:
    case R_EPOLL_LT:
    case R_EPOLL_ET:
        return read(c->rfd, buf, want);
    case R_RECVMSG3:
        memset(&mh, 0, sizeof mh);
        mh.msg_iov = iov;
        mh.msg_iovlen = split3(iov, buf, want, rng);
        return recvmsg(c->rfd, &mh, 0);
    case R_PEEK_MIX:
        if (r % 3 == 0) {
            size_t pk = 1 + (r >> 4) % (want < 6000 ? want : 6000);
            ssize_t p = recv(c->rfd, buf, pk, MSG_PEEK | MSG_DONTWAIT);
            if (p > 0) {
                if (!verify(buf, off, (size_t)p, c->salt, res, prev))
                    return -2;
            }
        }
        return recv(c->rfd, buf, want, 0);
    }
    return -1;
}

static void run_reader(struct chan *c, struct result *res)
{
    uint8_t *buf = malloc(c->maxr + 64);
    uint32_t rng = c->seed ^ 0x5a5a5a5au;
    uint64_t off = 0;
    long prev = 0;
    int ep = -1;
    if (c->rmode == R_READ_NB || c->rmode == R_EPOLL_LT || c->rmode == R_EPOLL_ET)
        set_nonblock(c->rfd);
    if (c->rmode == R_EPOLL_LT || c->rmode == R_EPOLL_ET) {
        struct epoll_event ev;
        ep = epoll_create1(0);
        ev.events = EPOLLIN | (c->rmode == R_EPOLL_ET ? EPOLLET : 0);
        ev.data.fd = c->rfd;
        epoll_ctl(ep, EPOLL_CTL_ADD, c->rfd, &ev);
    }
    int drained = 0;
    while (off < c->total) {
        if (ep >= 0 && (c->rmode == R_EPOLL_LT || drained)) {
            struct epoll_event out;
            int k = epoll_wait(ep, &out, 1, IO_WAIT_MS);
            if (k < 0 && errno == EINTR)
                continue;
            if (k == 0) {
                res->off = off;
                res->state = RES_STALL;
                goto out;
            }
            drained = 0;
        }
        size_t want = c->rmode == R_READ_SMALL ? 1 + next_random(&rng) % 9 : pick_size(&rng, c->maxr);
        if (c->rmode == R_READ_SMALL && (off & 0x3ffff) > 0x3f000)
            want = 4096;
        ssize_t r = recv_piece(c, buf, want, &rng, off, res, prev);
        if (r == -2)
            goto out;
        if (r < 0 && errno == EINTR)
            continue;
        if (r < 0 && errno == EAGAIN) {
            if (c->rmode == R_EPOLL_ET) {
                drained = 1;
                continue;
            }
            if (c->rmode == R_EPOLL_LT)
                continue;
            if (wait_fd(c->rfd, POLLIN, IO_WAIT_MS) <= 0) {
                res->off = off;
                res->state = RES_STALL;
                goto out;
            }
            continue;
        }
        if (r < 0) {
            res->off = off;
            res->err = errno;
            res->state = RES_SYSERR;
            goto out;
        }
        if (r == 0) {
            res->off = off;
            res->state = RES_SHORT;
            goto out;
        }
        if (!verify(buf, off, (size_t)r, c->salt, res, prev))
            goto out;
        off += (uint64_t)r;
        prev = r;
        res->bytes = off;
        progress();
    }
    {
        ssize_t r;
        int tries = 0;
        do {
            r = read(c->rfd, buf, 16);
            if (r < 0 && errno == EAGAIN)
                wait_fd(c->rfd, POLLIN, IO_WAIT_MS);
        } while (r < 0 && (errno == EAGAIN || errno == EINTR) && ++tries < 5);
        if (r == 0) {
            res->state = RES_OK;
        } else {
            res->off = off;
            res->got = r > 0 ? buf[0] : 0;
            res->err = r < 0 ? errno : 0;
            res->state = RES_EXTRA;
        }
    }
out:
    free(buf);
    if (ep >= 0)
        close(ep);
}

static void *writer_thread(void *a)
{
    struct job *j = a;
    run_writer(&j->c, j->wres);
    close(j->c.wfd);
    return NULL;
}

static void *reader_thread(void *a)
{
    struct job *j = a;
    run_reader(&j->c, j->rres);
    if (j->rres->state != RES_OK) {
        close(j->c.rfd);
        j->c.rfd = -1;
    }
    return NULL;
}

static struct result *alloc_results(int n)
{
    void *p = mmap(NULL, sizeof(struct result) * n, PROT_READ | PROT_WRITE, MAP_SHARED | MAP_ANONYMOUS, -1, 0);
    return p == MAP_FAILED ? NULL : p;
}

static void begin_case(const char *name)
{
    g_case_name = name;
    progress();
    g_case_active = 1;
}

static void end_case(void)
{
    g_case_active = 0;
}

static const char *state_name(int s)
{
    static const char *names[] = {"running", "ok", "mismatch", "stall", "syserr", "short", "extra"};
    return s >= 0 && s <= RES_EXTRA ? names[s] : "?";
}

static void verdict(const char *name, struct result *w, struct result *r)
{
    if (w->state == RES_OK && r->state == RES_OK) {
        PASS(name);
        return;
    }
    struct result *bad = r->state != RES_OK ? r : w;
    FAIL(name, "%s %s at off %llu exp 0x%02x got 0x%02x piece %ld prev %ld err %d | w %s %llu r %s %llu", bad == r ? "reader" : "writer", state_name(bad->state),
        (unsigned long long)bad->off, bad->expect, bad->got, bad->piece, bad->prev_piece, bad->err, state_name(w->state), (unsigned long long)w->bytes, state_name(r->state),
        (unsigned long long)r->bytes);
}

static int open_pair(struct chan *c, int pipe_mode, int type)
{
    int sv[2];
    if (pipe_mode) {
        if (pipe(sv) != 0)
            return -1;
        c->rfd = sv[0];
        c->wfd = sv[1];
        c->is_socket = 0;
        return 0;
    }
    if (socketpair(AF_UNIX, type, 0, sv) != 0)
        return -1;
    c->wfd = sv[0];
    c->rfd = sv[1];
    c->is_socket = 1;
    return 0;
}

static void case_threads(const char *name, int pipe_mode, int wmode, int rmode, uint64_t total, size_t maxw, size_t maxr, uint32_t salt, int jitter)
{
    struct job j;
    memset(&j, 0, sizeof j);
    j.wres = alloc_results(2);
    j.rres = j.wres + 1;
    if (!j.wres || open_pair(&j.c, pipe_mode, SOCK_STREAM) != 0) {
        FAIL(name, "setup errno %d", errno);
        return;
    }
    j.c.wmode = wmode;
    j.c.rmode = rmode;
    j.c.total = total;
    j.c.maxw = maxw;
    j.c.maxr = maxr;
    j.c.salt = salt;
    j.c.seed = salt * 2654435761u + 1;
    j.c.wjitter = jitter;
    pthread_t tw, tr;
    begin_case(name);
    pthread_create(&tr, NULL, reader_thread, &j);
    pthread_create(&tw, NULL, writer_thread, &j);
    pthread_join(tw, NULL);
    pthread_join(tr, NULL);
    end_case();
    verdict(name, j.wres, j.rres);
    if (j.c.rfd >= 0)
        close(j.c.rfd);
}

static void wait_child(pid_t pid, struct result *w, struct result *r)
{
    int st = 0;
    for (;;) {
        pid_t k = waitpid(pid, &st, WNOHANG);
        if (k == pid)
            break;
        if (w->bytes + r->bytes)
            progress();
        usleep(2000);
    }
    if (!(WIFEXITED(st) && WEXITSTATUS(st) == 0) && w->state == RES_RUN)
        w->state = RES_SYSERR;
}

static void case_procs(const char *name, int pipe_mode, int wmode, int rmode, uint64_t total, size_t maxw, size_t maxr, uint32_t salt, int jitter, int reader_in_child)
{
    struct job j;
    memset(&j, 0, sizeof j);
    j.wres = alloc_results(2);
    j.rres = j.wres + 1;
    if (!j.wres || open_pair(&j.c, pipe_mode, SOCK_STREAM) != 0) {
        FAIL(name, "setup errno %d", errno);
        return;
    }
    j.c.wmode = wmode;
    j.c.rmode = rmode;
    j.c.total = total;
    j.c.maxw = maxw;
    j.c.maxr = maxr;
    j.c.salt = salt;
    j.c.seed = salt * 2654435761u + 1;
    j.c.wjitter = jitter;
    begin_case(name);
    pid_t pid = fork();
    if (pid == 0) {
        if (reader_in_child) {
            close(j.c.wfd);
            run_reader(&j.c, j.rres);
        } else {
            close(j.c.rfd);
            run_writer(&j.c, j.wres);
        }
        _exit(0);
    }
    if (reader_in_child) {
        close(j.c.rfd);
        run_writer(&j.c, j.wres);
        close(j.c.wfd);
    } else {
        close(j.c.wfd);
        run_reader(&j.c, j.rres);
        close(j.c.rfd);
    }
    wait_child(pid, j.wres, j.rres);
    end_case();
    verdict(name, j.wres, j.rres);
}

#define MULTI_CHANNELS 4

static void case_multi(const char *name, int pipe_mode, uint64_t total)
{
    struct job jobs[MULTI_CHANNELS];
    pthread_t tw[MULTI_CHANNELS], tr[MULTI_CHANNELS];
    struct result *res = alloc_results(MULTI_CHANNELS * 2);
    int bad = 0;
    memset(jobs, 0, sizeof jobs);
    begin_case(name);
    for (int i = 0; i < MULTI_CHANNELS; i++) {
        struct job *j = &jobs[i];
        j->wres = res + 2 * i;
        j->rres = res + 2 * i + 1;
        if (open_pair(&j->c, pipe_mode, SOCK_STREAM) != 0) {
            FAIL(name, "setup errno %d", errno);
            return;
        }
        j->c.wmode = i % 2 ? W_WRITE : (pipe_mode ? W_WRITEV3 : W_SENDMSG3);
        j->c.rmode = i % 2 ? R_READ : R_READ_SMALL;
        j->c.total = total;
        j->c.maxw = 70000;
        j->c.maxr = 20000;
        j->c.salt = 100 + i;
        j->c.seed = 77 * (i + 1);
        j->c.wjitter = 0;
    }
    for (int i = 0; i < MULTI_CHANNELS; i++) {
        pthread_create(&tr[i], NULL, reader_thread, &jobs[i]);
        pthread_create(&tw[i], NULL, writer_thread, &jobs[i]);
    }
    for (int i = 0; i < MULTI_CHANNELS; i++) {
        pthread_join(tw[i], NULL);
        pthread_join(tr[i], NULL);
    }
    end_case();
    for (int i = 0; i < MULTI_CHANNELS; i++) {
        if (jobs[i].wres->state != RES_OK || jobs[i].rres->state != RES_OK) {
            bad++;
            char sub[48];
            snprintf(sub, sizeof sub, "%s_chan%d", name, i);
            verdict(sub, jobs[i].wres, jobs[i].rres);
        }
        if (jobs[i].c.rfd >= 0)
            close(jobs[i].c.rfd);
    }
    CHECK(name, bad == 0, "%d of %d channels corrupt", bad, MULTI_CHANNELS);
}

static void case_peek(void)
{
    int sv[2];
    uint8_t out[10000], a[600], b[600];
    ssize_t n;
    if (socketpair(AF_UNIX, SOCK_STREAM, 0, sv) != 0) {
        FAIL("stream_peek", "setup errno %d", errno);
        return;
    }
    fill(out, 0, sizeof out, 7);
    CHECK("stream_peek_send", write(sv[0], out, sizeof out) == (ssize_t)sizeof out, "errno %d", errno);
    n = recv(sv[1], a, 100, MSG_PEEK);
    CHECK("stream_peek_first", n == 100 && memcmp(a, out, 100) == 0, "n=%zd errno %d", n, errno);
    n = recv(sv[1], b, 300, MSG_PEEK);
    CHECK("stream_peek_repeat_same", n == 300 && memcmp(b, out, 300) == 0, "n=%zd errno %d", n, errno);
    n = recv(sv[1], a, 100, 0);
    CHECK("stream_peek_read_equals_peek", n == 100 && memcmp(a, out, 100) == 0, "n=%zd", n);
    n = recv(sv[1], b, 300, MSG_PEEK | MSG_DONTWAIT);
    CHECK("stream_peek_after_read_continues", n == 300 && memcmp(b, out + 100, 300) == 0, "n=%zd got first 0x%02x want 0x%02x", n, n > 0 ? b[0] : 0, out[100]);
    uint8_t big[10000];
    n = recv(sv[1], big, sizeof big, MSG_PEEK);
    CHECK("stream_peek_all_remaining", n == (ssize_t)sizeof out - 100 && memcmp(big, out + 100, n > 0 ? n : 0) == 0, "n=%zd", n);
    struct msghdr mh;
    struct iovec iov;
    memset(&mh, 0, sizeof mh);
    iov.iov_base = big;
    iov.iov_len = 50;
    mh.msg_iov = &iov;
    mh.msg_iovlen = 1;
    n = recvmsg(sv[1], &mh, MSG_PEEK);
    CHECK("stream_peek_recvmsg", n == 50 && memcmp(big, out + 100, 50) == 0, "n=%zd", n);
    n = recv(sv[1], big, sizeof big, 0);
    CHECK("stream_peek_recvmsg_kept_data", n == (ssize_t)sizeof out - 100 && memcmp(big, out + 100, n > 0 ? n : 0) == 0, "n=%zd", n);
    n = recv(sv[1], big, 10, MSG_PEEK | MSG_DONTWAIT);
    CHECK("stream_peek_empty_again", n == -1 && errno == EAGAIN, "n=%zd errno %d", n, errno);
    close(sv[0]);
    n = recv(sv[1], big, 10, MSG_PEEK);
    CHECK("stream_peek_eof", n == 0, "n=%zd errno %d", n, errno);
    close(sv[1]);
}

static void *delayed_pieces(void *arg)
{
    int fd = *(int *)arg;
    uint8_t p[1000];
    for (int i = 0; i < 3; i++) {
        usleep(30000);
        fill(p, (uint64_t)i * 1000, 1000, 9);
        (void)!write(fd, p, 1000);
    }
    return NULL;
}

static void case_waitall(void)
{
    int sv[2];
    uint8_t got[3000], want[3000];
    pthread_t t;
    if (socketpair(AF_UNIX, SOCK_STREAM, 0, sv) != 0) {
        FAIL("stream_waitall", "setup errno %d", errno);
        return;
    }
    pthread_create(&t, NULL, delayed_pieces, &sv[0]);
    ssize_t n = recv(sv[1], got, sizeof got, MSG_WAITALL);
    fill(want, 0, sizeof want, 9);
    CHECK("stream_waitall_full", n == 3000 && memcmp(got, want, 3000) == 0, "n=%zd errno %d", n, errno);
    pthread_join(t, NULL);
    close(sv[0]);
    close(sv[1]);
}

struct seq_hdr {
    uint32_t magic;
    uint32_t seq;
    uint32_t len;
    uint32_t chk;
};

#define SEQ_MAGIC 0x53455131u

static uint32_t chk_of(const uint8_t *p, size_t n)
{
    uint32_t h = 2166136261u;
    for (size_t i = 0; i < n; i++)
        h = (h ^ p[i]) * 16777619u;
    return h;
}

struct seq_job {
    int fd;
    int count;
    int max_len;
    int type;
    volatile int err;
    volatile int sent;
};

static void *seq_sender(void *arg)
{
    struct seq_job *j = arg;
    uint8_t buf[SEQ_MAX_MSG + 64];
    uint32_t rng = 12345;
    for (int i = 0; i < j->count; i++) {
        uint32_t r = next_random(&rng);
        size_t len = sizeof(struct seq_hdr) + 1 + r % (j->max_len - sizeof(struct seq_hdr));
        if (r % 11 == 0)
            len = j->max_len;
        struct seq_hdr h = {SEQ_MAGIC, (uint32_t)i, (uint32_t)len, 0};
        fill(buf + sizeof h, (uint64_t)i * 4099, len - sizeof h, 3);
        h.chk = chk_of(buf + sizeof h, len - sizeof h);
        memcpy(buf, &h, sizeof h);
        for (;;) {
            ssize_t w = send(j->fd, buf, len, 0);
            if (w == (ssize_t)len)
                break;
            if (w < 0 && errno == EINTR)
                continue;
            j->err = w < 0 ? errno : 1000;
            return NULL;
        }
        j->sent = i + 1;
        if (i % 97 == 0)
            usleep(300);
    }
    return NULL;
}

static void case_seq(const char *name, int type, int count, int max_len, int use_iov)
{
    int sv[2];
    struct seq_job j;
    pthread_t t;
    uint8_t buf[SEQ_MAX_MSG * 2];
    uint32_t rng = 999;
    int bad = 0;
    char why[160] = "";
    if (socketpair(AF_UNIX, type, 0, sv) != 0) {
        FAIL(name, "setup errno %d", errno);
        return;
    }
    memset(&j, 0, sizeof j);
    j.fd = sv[0];
    j.count = count;
    j.max_len = max_len;
    begin_case(name);
    pthread_create(&t, NULL, seq_sender, &j);
    for (int i = 0; i < count && !bad; i++) {
        struct iovec iov[3];
        struct msghdr mh;
        memset(&mh, 0, sizeof mh);
        mh.msg_iov = iov;
        mh.msg_iovlen = use_iov ? split3(iov, buf, sizeof buf / 2, &rng) : 1;
        if (!use_iov) {
            iov[0].iov_base = buf;
            iov[0].iov_len = sizeof buf / 2;
        }
        if (wait_fd(sv[1], POLLIN, IO_WAIT_MS) <= 0) {
            snprintf(why, sizeof why, "stall waiting for message %d (sent %d err %d)", i, j.sent, j.err);
            bad = 1;
            break;
        }
        ssize_t n = recvmsg(sv[1], &mh, 0);
        struct seq_hdr h;
        if (n < (ssize_t)sizeof h) {
            snprintf(why, sizeof why, "msg %d recv n=%zd errno %d", i, n, errno);
            bad = 1;
            break;
        }
        memcpy(&h, buf, sizeof h);
        if (h.magic != SEQ_MAGIC || h.seq != (uint32_t)i || h.len != (uint32_t)n || chk_of(buf + sizeof h, n - sizeof h) != h.chk || (mh.msg_flags & MSG_TRUNC)) {
            snprintf(why, sizeof why, "msg %d magic %x seq %u len %u got %zd flags %x", i, h.magic, h.seq, h.len, n, mh.msg_flags);
            bad = 1;
        }
        progress();
    }
    if (bad)
        close(sv[1]);
    pthread_join(t, NULL);
    end_case();
    if (j.err == EMSGSIZE)
        GAP(name, "send -> EMSGSIZE at message %d (frame limit below %d)", j.sent, max_len);
    else
        CHECK(name, !bad && j.err == 0, "%s sender err %d", why, j.err);
    close(sv[0]);
    if (!bad)
        close(sv[1]);
}

static void case_seq_big(const char *name, int type)
{
    int sv[2];
    uint8_t *out = malloc(MAX_PIECE), *in = malloc(MAX_PIECE);
    static const size_t sizes[] = {SEQ_MAX_MSG + 1, 4096, 8192, 20000, 65536, 100000};
    if (socketpair(AF_UNIX, type, 0, sv) != 0) {
        FAIL(name, "setup errno %d", errno);
        return;
    }
    for (size_t k = 0; k < sizeof sizes / sizeof sizes[0]; k++) {
        size_t n = sizes[k];
        fill(out, k * 13, n, 5);
        set_nonblock(sv[0]);
        ssize_t w = send(sv[0], out, n, 0);
        if (w < 0 && errno == EMSGSIZE) {
            GAP(name, "send of %zu bytes -> EMSGSIZE (frame limit %d)", n, SEQ_MAX_MSG);
            goto done;
        }
        if (w != (ssize_t)n) {
            FAIL(name, "send %zu returned %zd errno %d", n, w, errno);
            goto done;
        }
        ssize_t r = recv(sv[1], in, MAX_PIECE, 0);
        if (r != (ssize_t)n || memcmp(in, out, n) != 0) {
            FAIL(name, "recv of %zu bytes returned %zd", n, r);
            goto done;
        }
    }
    PASS(name);
done:
    free(out);
    free(in);
    close(sv[0]);
    close(sv[1]);
}

static void case_seq_trunc_peek(const char *name, int type)
{
    int sv[2];
    uint8_t a[400], b[400], got[400];
    struct msghdr mh;
    struct iovec iov;
    if (socketpair(AF_UNIX, type, 0, sv) != 0) {
        FAIL(name, "setup errno %d", errno);
        return;
    }
    fill(a, 0, 400, 21);
    fill(b, 0, 300, 22);
    (void)!send(sv[0], a, 400, 0);
    (void)!send(sv[0], b, 300, 0);
    ssize_t p1 = recv(sv[1], got, 400, MSG_PEEK);
    int peek_ok = p1 == 400 && memcmp(got, a, 400) == 0;
    ssize_t p2 = recv(sv[1], got, 400, MSG_PEEK);
    int peek_same = p2 == 400 && memcmp(got, a, 400) == 0;
    memset(&mh, 0, sizeof mh);
    iov.iov_base = got;
    iov.iov_len = 100;
    mh.msg_iov = &iov;
    mh.msg_iovlen = 1;
    ssize_t t = recvmsg(sv[1], &mh, MSG_DONTWAIT);
    int trunc_ok = t == 100 && (mh.msg_flags & MSG_TRUNC) && memcmp(got, a, 100) == 0;
    ssize_t n2 = recv(sv[1], got, 400, MSG_DONTWAIT);
    int next_ok = n2 == 300 && memcmp(got, b, 300) == 0;
    char label[64];
    snprintf(label, sizeof label, "%s_peek", name);
    CHECK(label, peek_ok && peek_same, "p1 %zd p2 %zd", p1, p2);
    snprintf(label, sizeof label, "%s_trunc_drops_rest", name);
    CHECK(label, trunc_ok && next_ok, "t %zd flags %x next %zd", t, mh.msg_flags, n2);
    close(sv[0]);
    close(sv[1]);
}

struct scm_job {
    int fd;
    int count;
    int fds_sent;
    volatile int done;
    int keep[256];
    int keep_k[256];
};

static void *scm_sender(void *arg)
{
    struct scm_job *j = arg;
    uint8_t buf[8192];
    uint32_t rng = 4242;
    for (int i = 0; i < j->count; i++) {
        uint32_t r = next_random(&rng);
        size_t len = sizeof(struct seq_hdr) + r % 3000;
        int with_fd = (i % 3) == 1 && j->fds_sent < 256;
        struct seq_hdr h = {SEQ_MAGIC, (uint32_t)i, (uint32_t)len, (uint32_t)with_fd};
        memcpy(buf, &h, sizeof h);
        fill(buf + sizeof h, (uint64_t)i * 77, len - sizeof h, 31);
        struct iovec iov = {buf, len};
        struct msghdr mh;
        char ctl[CMSG_SPACE(sizeof(int))];
        int pp[2] = {-1, -1};
        memset(&mh, 0, sizeof mh);
        mh.msg_iov = &iov;
        mh.msg_iovlen = 1;
        if (with_fd) {
            if (pipe(pp) != 0) {
                j->done = -1;
                return NULL;
            }
            memset(ctl, 0, sizeof ctl);
            mh.msg_control = ctl;
            mh.msg_controllen = sizeof ctl;
            struct cmsghdr *cm = CMSG_FIRSTHDR(&mh);
            cm->cmsg_level = SOL_SOCKET;
            cm->cmsg_type = SCM_RIGHTS;
            cm->cmsg_len = CMSG_LEN(sizeof(int));
            memcpy(CMSG_DATA(cm), &pp[1], sizeof(int));
        }
        size_t sent = 0;
        while (sent < len) {
            struct iovec rest = {buf + sent, len - sent};
            mh.msg_iov = &rest;
            ssize_t w = sendmsg(j->fd, &mh, 0);
            if (w < 0 && errno == EINTR)
                continue;
            if (w <= 0) {
                j->done = -2;
                return NULL;
            }
            sent += (size_t)w;
            mh.msg_control = NULL;
            mh.msg_controllen = 0;
        }
        if (with_fd) {
            close(pp[1]);
            j->keep[j->fds_sent] = pp[0];
            j->keep_k[j->fds_sent] = i;
            j->fds_sent++;
        }
        if (i % 50 == 0)
            usleep(200);
    }
    j->done = 1;
    return NULL;
}

static void case_scm(const char *name, int msgs)
{
    int sv[2];
    struct scm_job j;
    pthread_t t;
    uint8_t acc[16384];
    size_t have = 0;
    int next_seq = 0, got_fds = 0, used_fds = 0, bad = 0, want_fds = 0;
    int fdq[64], fdq_n = 0;
    char why[160] = "";
    uint32_t rng = 31337;
    if (socketpair(AF_UNIX, SOCK_STREAM, 0, sv) != 0) {
        FAIL(name, "setup errno %d", errno);
        return;
    }
    memset(&j, 0, sizeof j);
    j.fd = sv[0];
    j.count = msgs;
    begin_case(name);
    pthread_create(&t, NULL, scm_sender, &j);
    while (next_seq < msgs && !bad) {
        char ctl[CMSG_SPACE(sizeof(int) * SCM_MAX_FDS)];
        uint8_t chunk[4096];
        struct iovec iov = {chunk, 1 + next_random(&rng) % sizeof chunk};
        struct msghdr mh;
        memset(&mh, 0, sizeof mh);
        mh.msg_iov = &iov;
        mh.msg_iovlen = 1;
        mh.msg_control = ctl;
        mh.msg_controllen = sizeof ctl;
        if (wait_fd(sv[1], POLLIN, IO_WAIT_MS) <= 0) {
            snprintf(why, sizeof why, "stall at msg %d fds %d/%d", next_seq, got_fds, want_fds);
            bad = 1;
            break;
        }
        ssize_t n = recvmsg(sv[1], &mh, 0);
        if (n <= 0) {
            snprintf(why, sizeof why, "recvmsg %zd errno %d at msg %d", n, errno, next_seq);
            bad = 1;
            break;
        }
        if (mh.msg_flags & MSG_CTRUNC) {
            snprintf(why, sizeof why, "CTRUNC at msg %d", next_seq);
            bad = 1;
            break;
        }
        for (struct cmsghdr *cm = CMSG_FIRSTHDR(&mh); cm; cm = CMSG_NXTHDR(&mh, cm)) {
            if (cm->cmsg_level == SOL_SOCKET && cm->cmsg_type == SCM_RIGHTS) {
                int k = (int)((cm->cmsg_len - CMSG_LEN(0)) / sizeof(int));
                for (int q = 0; q < k && fdq_n < 64; q++) {
                    memcpy(&fdq[fdq_n++], CMSG_DATA(cm) + q * sizeof(int), sizeof(int));
                    got_fds++;
                }
            }
        }
        if (have + (size_t)n > sizeof acc) {
            snprintf(why, sizeof why, "accumulator overflow");
            bad = 1;
            break;
        }
        memcpy(acc + have, chunk, n);
        have += n;
        for (;;) {
            struct seq_hdr h;
            if (have < sizeof h)
                break;
            memcpy(&h, acc, sizeof h);
            if (h.magic != SEQ_MAGIC || h.seq != (uint32_t)next_seq || h.len < sizeof h || h.len > 4096) {
                snprintf(why, sizeof why, "frame %d header magic %x seq %u len %u", next_seq, h.magic, h.seq, h.len);
                bad = 1;
                break;
            }
            if (have < h.len)
                break;
            for (size_t q = sizeof h; q < h.len; q++) {
                if (acc[q] != pat((uint64_t)next_seq * 77 + (q - sizeof h), 31)) {
                    snprintf(why, sizeof why, "frame %d payload byte %zu wrong", next_seq, q);
                    bad = 1;
                    break;
                }
            }
            if (bad)
                break;
            if (h.chk) {
                want_fds++;
                if (fdq_n == 0) {
                    snprintf(why, sizeof why, "frame %d complete but its descriptor has not arrived", next_seq);
                    bad = 1;
                    break;
                }
                int fd = fdq[0];
                memmove(fdq, fdq + 1, (--fdq_n) * sizeof(int));
                uint8_t token = (uint8_t)next_seq;
                (void)!write(fd, &token, 1);
                close(fd);
                used_fds++;
            }
            memmove(acc, acc + h.len, have - h.len);
            have -= h.len;
            next_seq++;
        }
    }
    if (bad)
        close(sv[1]);
    pthread_join(t, NULL);
    end_case();
    int wrong_token = 0;
    for (int q = 0; q < j.fds_sent && !bad; q++) {
        uint8_t tok = 0;
        ssize_t r = read(j.keep[q], &tok, 1);
        if (r != 1 || tok != (uint8_t)j.keep_k[q])
            wrong_token++;
    }
    CHECK(name, !bad && j.done == 1 && wrong_token == 0 && used_fds == j.fds_sent && fdq_n == 0, "%s done %d fds used %d sent %d left %d wrong_token %d", why, j.done, used_fds, j.fds_sent, fdq_n, wrong_token);
    close(sv[0]);
    if (!bad)
        close(sv[1]);
}

static void case_close_mid_stream(const char *name, int use_shutdown)
{
    int bad = 0;
    char why[120] = "";
    uint32_t rng = 2024;
    begin_case(name);
    for (int round = 0; round < 150 && !bad; round++) {
        int sv[2];
        uint8_t buf[70000], got[70000];
        if (socketpair(AF_UNIX, SOCK_STREAM, 0, sv) != 0) {
            snprintf(why, sizeof why, "socketpair errno %d", errno);
            bad = 1;
            break;
        }
        size_t total = next_random(&rng) % 150000;
        pid_t pid = fork();
        if (pid == 0) {
            close(sv[1]);
            uint64_t off = 0;
            while (off < total) {
                size_t n = total - off < sizeof buf ? total - off : sizeof buf;
                size_t lim = 1 + next_random(&rng) % 60000;
                if (n > lim)
                    n = lim;
                fill(buf, off, n, 61);
                size_t d = 0;
                while (d < n) {
                    ssize_t w = write(sv[0], buf + d, n - d);
                    if (w <= 0)
                        _exit(3);
                    d += w;
                }
                off += n;
            }
            if (use_shutdown)
                shutdown(sv[0], SHUT_WR);
            else
                close(sv[0]);
            _exit(0);
        }
        close(sv[0]);
        uint64_t off = 0;
        for (;;) {
            if (wait_fd(sv[1], POLLIN, IO_WAIT_MS) <= 0) {
                snprintf(why, sizeof why, "round %d stall at %llu of %zu", round, (unsigned long long)off, total);
                bad = 1;
                break;
            }
            ssize_t r = read(sv[1], got, 1 + next_random(&rng) % sizeof got);
            if (r < 0 && errno == EINTR)
                continue;
            if (r < 0) {
                snprintf(why, sizeof why, "round %d read errno %d at %llu", round, errno, (unsigned long long)off);
                bad = 1;
                break;
            }
            if (r == 0)
                break;
            for (ssize_t q = 0; q < r; q++) {
                if (got[q] != pat(off + q, 61)) {
                    snprintf(why, sizeof why, "round %d mismatch at %llu", round, (unsigned long long)(off + q));
                    bad = 1;
                    break;
                }
            }
            if (bad)
                break;
            off += (uint64_t)r;
            progress();
        }
        if (!bad && off != total) {
            snprintf(why, sizeof why, "round %d got %llu of %zu then EOF", round, (unsigned long long)off, total);
            bad = 1;
        }
        close(sv[1]);
        waitpid(pid, NULL, 0);
    }
    end_case();
    CHECK(name, !bad, "%s", why);
}

static void case_reader_gone(void)
{
    int bad = 0;
    char why[120] = "";
    signal(SIGPIPE, SIG_IGN);
    begin_case("stream_reader_gone_epipe");
    for (int round = 0; round < 100 && !bad; round++) {
        int sv[2];
        uint8_t buf[9000];
        if (socketpair(AF_UNIX, SOCK_STREAM, 0, sv) != 0) {
            bad = 1;
            break;
        }
        fill(buf, 0, sizeof buf, 5);
        (void)!write(sv[0], buf, sizeof buf);
        close(sv[1]);
        ssize_t w = write(sv[0], buf, 100);
        if (w != -1 || errno != EPIPE) {
            snprintf(why, sizeof why, "round %d write after peer close returned %zd errno %d", round, w, errno);
            bad = 1;
        }
        close(sv[0]);
    }
    end_case();
    CHECK("stream_reader_gone_epipe", !bad, "%s", why);
}

struct pp_job {
    int fd;
    int count;
    int salt;
    volatile int err;
};

static void *pp_echo(void *arg)
{
    struct pp_job *j = arg;
    uint8_t buf[4096];
    uint32_t rng = 555;
    for (int i = 0; i < j->count; i++) {
        size_t want = 1 + next_random(&rng) % 1500;
        size_t got = 0;
        while (got < want) {
            struct pollfd p = {j->fd, POLLIN, 0};
            int k = poll(&p, 1, IO_WAIT_MS);
            if (k <= 0) {
                j->err = 1;
                return NULL;
            }
            ssize_t r = read(j->fd, buf + got, want - got);
            if (r <= 0) {
                j->err = 2;
                return NULL;
            }
            got += (size_t)r;
        }
        for (size_t q = 0; q < want; q++)
            buf[q] ^= 0xff;
        if (write(j->fd, buf, want) != (ssize_t)want) {
            j->err = 3;
            return NULL;
        }
        progress();
    }
    return NULL;
}

static void case_pingpong(const char *name, int use_epoll, int count)
{
    int sv[2];
    struct pp_job j;
    pthread_t t;
    uint8_t buf[4096], rb[4096];
    uint32_t rng = 555;
    int bad = 0;
    char why[120] = "";
    if (socketpair(AF_UNIX, SOCK_STREAM, 0, sv) != 0) {
        FAIL(name, "setup errno %d", errno);
        return;
    }
    memset(&j, 0, sizeof j);
    j.fd = sv[1];
    j.count = count;
    begin_case(name);
    pthread_create(&t, NULL, pp_echo, &j);
    int ep = -1;
    if (use_epoll) {
        struct epoll_event ev = {EPOLLIN | EPOLLET, {.fd = sv[0]}};
        ep = epoll_create1(0);
        set_nonblock(sv[0]);
        epoll_ctl(ep, EPOLL_CTL_ADD, sv[0], &ev);
    }
    for (int i = 0; i < count && !bad; i++) {
        size_t n = 1 + next_random(&rng) % 1500;
        fill(buf, (uint64_t)i * 1500, n, 8);
        if (write(sv[0], buf, n) != (ssize_t)n) {
            snprintf(why, sizeof why, "write %d errno %d", i, errno);
            bad = 1;
            break;
        }
        size_t got = 0;
        while (got < n) {
            if (use_epoll) {
                struct epoll_event out;
                ssize_t r = read(sv[0], rb + got, n - got);
                if (r > 0) {
                    got += r;
                    continue;
                }
                if (epoll_wait(ep, &out, 1, IO_WAIT_MS) <= 0) {
                    snprintf(why, sizeof why, "epoll stall at round %d got %zu of %zu", i, got, n);
                    bad = 1;
                    break;
                }
                continue;
            }
            if (wait_fd(sv[0], POLLIN, IO_WAIT_MS) <= 0) {
                snprintf(why, sizeof why, "poll stall at round %d got %zu of %zu", i, got, n);
                bad = 1;
                break;
            }
            ssize_t r = read(sv[0], rb + got, n - got);
            if (r <= 0) {
                snprintf(why, sizeof why, "read %zd round %d", r, i);
                bad = 1;
                break;
            }
            got += (size_t)r;
        }
        if (bad)
            break;
        for (size_t q = 0; q < n; q++) {
            if ((uint8_t)(rb[q] ^ 0xff) != buf[q]) {
                snprintf(why, sizeof why, "round %d byte %zu of %zu wrong", i, q, n);
                bad = 1;
                break;
            }
        }
    }
    if (bad)
        close(sv[0]);
    pthread_join(t, NULL);
    end_case();
    CHECK(name, !bad && j.err == 0, "%s echo err %d", why, j.err);
    close(sv[0]);
    close(sv[1]);
    if (ep >= 0)
        close(ep);
}

struct rec_hdr {
    uint32_t magic;
    uint32_t writer;
    uint32_t seq;
    uint32_t len;
    uint32_t chk;
};

#define REC_MAGIC 0x52454331u
#define REC_WRITERS 3
#define REC_PER_WRITER 600

struct rec_job {
    int wfd;
    int id;
    volatile int err;
};

static void *rec_writer(void *arg)
{
    struct rec_job *j = arg;
    uint8_t buf[4096];
    uint32_t rng = 1000 + j->id;
    for (int i = 0; i < REC_PER_WRITER; i++) {
        size_t len = sizeof(struct rec_hdr) + next_random(&rng) % (4096 - sizeof(struct rec_hdr));
        struct rec_hdr h = {REC_MAGIC, (uint32_t)j->id, (uint32_t)i, (uint32_t)len, 0};
        fill(buf + sizeof h, (uint64_t)i, len - sizeof h, 70 + j->id);
        h.chk = chk_of(buf + sizeof h, len - sizeof h);
        memcpy(buf, &h, sizeof h);
        ssize_t w = write(j->wfd, buf, len);
        if (w != (ssize_t)len) {
            j->err = w < 0 ? errno : 999;
            return NULL;
        }
    }
    return NULL;
}

static void case_pipe_records(void)
{
    int pp[2];
    struct rec_job jobs[REC_WRITERS];
    pthread_t th[REC_WRITERS];
    uint32_t next[REC_WRITERS] = {0};
    uint8_t buf[8192];
    int bad = 0;
    char why[120] = "";
    if (pipe(pp) != 0) {
        FAIL("pipe_atomic_records", "pipe errno %d", errno);
        return;
    }
    begin_case("pipe_atomic_records");
    for (int i = 0; i < REC_WRITERS; i++) {
        jobs[i].wfd = pp[1];
        jobs[i].id = i;
        jobs[i].err = 0;
        pthread_create(&th[i], NULL, rec_writer, &jobs[i]);
    }
    int records = 0;
    while (records < REC_WRITERS * REC_PER_WRITER && !bad) {
        struct rec_hdr h;
        size_t got = 0;
        while (got < sizeof h) {
            if (wait_fd(pp[0], POLLIN, IO_WAIT_MS) <= 0) {
                snprintf(why, sizeof why, "stall after %d records", records);
                bad = 1;
                break;
            }
            ssize_t r = read(pp[0], buf + got, sizeof h - got);
            if (r <= 0) {
                snprintf(why, sizeof why, "read %zd", r);
                bad = 1;
                break;
            }
            got += r;
        }
        if (bad)
            break;
        memcpy(&h, buf, sizeof h);
        if (h.magic != REC_MAGIC || h.writer >= REC_WRITERS || h.len < sizeof h || h.len > 4096 || h.seq != next[h.writer]) {
            snprintf(why, sizeof why, "record %d header magic %x writer %u seq %u len %u", records, h.magic, h.writer, h.seq, h.len);
            bad = 1;
            break;
        }
        while (got < h.len) {
            if (wait_fd(pp[0], POLLIN, IO_WAIT_MS) <= 0) {
                snprintf(why, sizeof why, "stall inside record %d", records);
                bad = 1;
                break;
            }
            ssize_t r = read(pp[0], buf + got, h.len - got);
            if (r <= 0) {
                bad = 1;
                break;
            }
            got += r;
        }
        if (bad)
            break;
        if (chk_of(buf + sizeof h, h.len - sizeof h) != h.chk) {
            snprintf(why, sizeof why, "record %d (writer %u seq %u len %u) torn", records, h.writer, h.seq, h.len);
            bad = 1;
            break;
        }
        next[h.writer]++;
        records++;
        progress();
    }
    for (int i = 0; i < REC_WRITERS; i++)
        pthread_join(th[i], NULL);
    end_case();
    int werr = 0;
    for (int i = 0; i < REC_WRITERS; i++)
        werr |= jobs[i].err;
    CHECK("pipe_atomic_records", !bad && werr == 0, "%s writer err %d", why, werr);
    close(pp[0]);
    close(pp[1]);
}

static void case_wake_bytes(void)
{
    int pp[2];
    int bad = 0;
    char why[120] = "";
    if (pipe(pp) != 0) {
        FAIL("pipe_wake_bytes", "errno %d", errno);
        return;
    }
    set_nonblock(pp[0]);
    int ep = epoll_create1(0);
    struct epoll_event ev = {EPOLLIN, {.fd = pp[0]}};
    epoll_ctl(ep, EPOLL_CTL_ADD, pp[0], &ev);
    begin_case("pipe_wake_bytes");
    pid_t pid = fork();
    if (pid == 0) {
        uint32_t rng = 17;
        for (int i = 0; i < 3000; i++) {
            uint8_t b = (uint8_t)i;
            (void)!write(pp[1], &b, 1);
            if (next_random(&rng) % 4 == 0)
                usleep(100 + next_random(&rng) % 500);
        }
        _exit(0);
    }
    close(pp[1]);
    int want = 0;
    while (want < 3000 && !bad) {
        struct epoll_event out;
        if (epoll_wait(ep, &out, 1, IO_WAIT_MS) <= 0) {
            snprintf(why, sizeof why, "stall at byte %d", want);
            bad = 1;
            break;
        }
        uint8_t b[64];
        ssize_t r;
        while ((r = read(pp[0], b, sizeof b)) > 0) {
            for (ssize_t q = 0; q < r; q++, want++) {
                if (b[q] != (uint8_t)want) {
                    snprintf(why, sizeof why, "byte %d is %u", want, b[q]);
                    bad = 1;
                }
            }
        }
        progress();
    }
    waitpid(pid, NULL, 0);
    end_case();
    CHECK("pipe_wake_bytes", !bad, "%s", why);
    close(pp[0]);
    close(ep);
}

int main(void)
{
    pthread_t wd;
    struct { const char *name; int pipe_mode, wmode, rmode; uint64_t total; size_t maxw, maxr; int jitter; } cases[] = {
        {"stream_thr_block_read", 0, W_WRITE, R_READ, 3u << 20, MAX_PIECE, 70000, 0},
        {"stream_thr_writev_read1", 0, W_WRITEV3, R_READ_SMALL, 600000, 4000, 4096, 0},
        {"stream_thr_sendmsg3_recvmsg3", 0, W_SENDMSG3, R_RECVMSG3, 3u << 20, MAX_PIECE, 20000, 0},
        {"stream_thr_nb_epoll_lt", 0, W_SEND_NB, R_EPOLL_LT, 2u << 20, 100000, 30000, 40},
        {"stream_thr_nb_epoll_et", 0, W_SEND_NB, R_EPOLL_ET, 2u << 20, 100000, 30000, 40},
        {"stream_thr_peek_mix", 0, W_WRITE, R_PEEK_MIX, 1u << 20, 30000, 20000, 20},
        {"pipe_thr_block_read", 1, W_WRITE, R_READ, 3u << 20, MAX_PIECE, 70000, 0},
        {"pipe_thr_read1", 1, W_WRITEV3, R_READ_SMALL, 600000, 4000, 4096, 0},
        {"pipe_thr_nb_epoll_et", 1, W_WRITE_NB, R_EPOLL_ET, 2u << 20, 100000, 30000, 40},
    };
    signal(SIGPIPE, SIG_IGN);
    pthread_create(&wd, NULL, watchdog, NULL);
    for (size_t i = 0; i < sizeof cases / sizeof cases[0]; i++)
        case_threads(cases[i].name, cases[i].pipe_mode, cases[i].wmode, cases[i].rmode, cases[i].total, cases[i].maxw, cases[i].maxr, 11 + (uint32_t)i, cases[i].jitter);
    case_procs("stream_proc_writer_child", 0, W_SENDMSG3, R_RECVMSG3, 3u << 20, MAX_PIECE, 30000, 41, 0, 0);
    case_procs("stream_proc_reader_child", 0, W_WRITE, R_READ_SMALL, 400000, 9000, 4096, 42, 30, 1);
    case_procs("stream_proc_nb_epoll", 0, W_SEND_NB, R_EPOLL_ET, 2u << 20, 90000, 25000, 43, 30, 0);
    case_procs("pipe_proc_writer_child", 1, W_WRITE, R_READ, 3u << 20, MAX_PIECE, 70000, 44, 0, 0);
    case_procs("pipe_proc_reader_child", 1, W_WRITEV3, R_READ_SMALL, 400000, 9000, 4096, 45, 30, 1);
    case_multi("stream_multi_channel", 0, 1u << 20);
    case_multi("pipe_multi_channel", 1, 1u << 20);
    begin_case("stream_peek");
    case_peek();
    end_case();
    begin_case("stream_waitall");
    case_waitall();
    end_case();
    case_seq("seqpacket_frames", SOCK_SEQPACKET, 4000, SEQ_FRAME_OK, 0);
    case_seq("seqpacket_frames_iov", SOCK_SEQPACKET, 3000, SEQ_FRAME_OK, 1);
    case_seq("dgram_frames", SOCK_DGRAM, 3000, SEQ_FRAME_OK, 0);
    case_seq("seqpacket_frames_3600", SOCK_SEQPACKET, 500, SEQ_MAX_MSG, 0);
    begin_case("seqpacket_big");
    case_seq_big("seqpacket_big", SOCK_SEQPACKET);
    end_case();
    begin_case("seqpacket_trunc_peek");
    case_seq_trunc_peek("seqpacket", SOCK_SEQPACKET);
    case_seq_trunc_peek("dgram", SOCK_DGRAM);
    end_case();
    case_scm("scm_rights_ordered", 900);
    case_close_mid_stream("stream_close_mid_stream", 0);
    case_close_mid_stream("stream_shutdown_mid_stream", 1);
    case_reader_gone();
    case_pingpong("stream_pingpong_poll", 0, 6000);
    case_pingpong("stream_pingpong_epoll_et", 1, 6000);
    case_pipe_records();
    case_wake_bytes();
    return 0;
}
