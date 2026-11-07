#define TNAME "wakelat"
#include "t.h"
#include <pthread.h>
#include <poll.h>
#include <stdint.h>
#include <stdlib.h>
#include <sys/eventfd.h>
#include <sys/epoll.h>
#include <sys/socket.h>
#include <sys/syscall.h>
#include <time.h>

#define ROUNDS 200
#define LIMIT_US 1000

static long now_us(void)
{
    struct timespec t;
    clock_gettime(CLOCK_MONOTONIC, &t);
    return t.tv_sec * 1000000L + t.tv_nsec / 1000;
}

static int cmp_long(const void *a, const void *b)
{
    long x = *(const long *)a, y = *(const long *)b;
    return x < y ? -1 : x > y;
}

static long median(long *v, int n)
{
    qsort(v, n, sizeof *v, cmp_long);
    return v[n / 2];
}

static void report(const char *name, long *v, int n, long limit)
{
    long med = median(v, n);
    long worst = v[n - 1];
    if (med <= limit)
        PASS(name, "median_us=%ld worst_us=%ld limit_us=%ld", med, worst, limit);
    else
        FAIL(name, "median_us=%ld worst_us=%ld limit_us=%ld", med, worst, limit);
}

static long fx(volatile int *a, int op, int val, const struct timespec *ts)
{
    return syscall(SYS_futex, a, op, val, ts, 0, 0);
}

static volatile int turn;

static void *futex_peer(void *arg)
{
    (void)arg;
    for (int i = 0; i < ROUNDS; i++) {
        while (turn != 1)
            fx(&turn, 128, 0, 0);
        turn = 0;
        fx(&turn, 129, 1, 0);
    }
    return 0;
}

static void bench_futex(void)
{
    static long v[ROUNDS];
    pthread_t th;
    pthread_create(&th, 0, futex_peer, 0);
    for (int i = 0; i < ROUNDS; i++) {
        long t0 = now_us();
        turn = 1;
        fx(&turn, 129, 1, 0);
        while (turn != 0)
            fx(&turn, 128, 1, 0);
        v[i] = now_us() - t0;
    }
    pthread_join(th, 0);
    report("futex_pingpong", v, ROUNDS, LIMIT_US);
}

static int pa[2], pb[2];

static void *pipe_peer(void *arg)
{
    char c;
    (void)arg;
    for (int i = 0; i < ROUNDS; i++) {
        if (read(pa[0], &c, 1) != 1)
            break;
        if (write(pb[1], &c, 1) != 1)
            break;
    }
    return 0;
}

static void bench_pipe(void)
{
    static long v[ROUNDS];
    pthread_t th;
    char c = 'x';
    pipe(pa);
    pipe(pb);
    pthread_create(&th, 0, pipe_peer, 0);
    for (int i = 0; i < ROUNDS; i++) {
        long t0 = now_us();
        write(pa[1], &c, 1);
        read(pb[0], &c, 1);
        v[i] = now_us() - t0;
    }
    pthread_join(th, 0);
    report("pipe_pingpong", v, ROUNDS, LIMIT_US);
}

static int ea, eb;

static void *event_peer(void *arg)
{
    uint64_t x;
    (void)arg;
    for (int i = 0; i < ROUNDS; i++) {
        if (read(ea, &x, 8) != 8)
            break;
        x = 1;
        if (write(eb, &x, 8) != 8)
            break;
    }
    return 0;
}

static void bench_eventfd(void)
{
    static long v[ROUNDS];
    pthread_t th;
    uint64_t x;
    ea = eventfd(0, 0);
    eb = eventfd(0, 0);
    if (ea < 0 || eb < 0) {
        GAP("eventfd_pingpong", "eventfd failed");
        return;
    }
    pthread_create(&th, 0, event_peer, 0);
    for (int i = 0; i < ROUNDS; i++) {
        long t0 = now_us();
        x = 1;
        write(ea, &x, 8);
        read(eb, &x, 8);
        v[i] = now_us() - t0;
    }
    pthread_join(th, 0);
    report("eventfd_pingpong", v, ROUNDS, LIMIT_US);
}

static int sa[2], sb[2];

static void *poll_peer(void *arg)
{
    char c;
    struct pollfd p = { sa[0], POLLIN, 0 };
    (void)arg;
    for (int i = 0; i < ROUNDS; i++) {
        if (poll(&p, 1, 1000) != 1)
            break;
        if (read(sa[0], &c, 1) != 1)
            break;
        if (write(sb[1], &c, 1) != 1)
            break;
    }
    return 0;
}

static void bench_poll_wake(void)
{
    static long v[ROUNDS];
    pthread_t th;
    char c = 'x';
    pipe(sa);
    pipe(sb);
    pthread_create(&th, 0, poll_peer, 0);
    struct pollfd p = { sb[0], POLLIN, 0 };
    for (int i = 0; i < ROUNDS; i++) {
        long t0 = now_us();
        write(sa[1], &c, 1);
        poll(&p, 1, 1000);
        read(sb[0], &c, 1);
        v[i] = now_us() - t0;
    }
    pthread_join(th, 0);
    report("poll_wake_pingpong", v, ROUNDS, LIMIT_US);
}

static void bench_poll_timeout(void)
{
    static long v[50];
    int p2[2];
    pipe(p2);
    struct pollfd p = { p2[0], POLLIN, 0 };
    for (int i = 0; i < 50; i++) {
        long t0 = now_us();
        poll(&p, 1, 1);
        v[i] = now_us() - t0;
    }
    report("poll_1ms_timeout", v, 50, 2500);
}

static void bench_epoll_timeout(void)
{
    static long v[50];
    int p2[2];
    struct epoll_event ev = { EPOLLIN, { 0 } }, out;
    pipe(p2);
    int ep = epoll_create1(0);
    epoll_ctl(ep, EPOLL_CTL_ADD, p2[0], &ev);
    for (int i = 0; i < 50; i++) {
        long t0 = now_us();
        epoll_wait(ep, &out, 1, 1);
        v[i] = now_us() - t0;
    }
    report("epoll_1ms_timeout", v, 50, 2500);
}

static void bench_nanosleep(void)
{
    static long v[50];
    struct timespec ts = { 0, 1000000 };
    for (int i = 0; i < 50; i++) {
        long t0 = now_us();
        nanosleep(&ts, 0);
        v[i] = now_us() - t0;
    }
    report("nanosleep_1ms", v, 50, 2500);
}

static void bench_futex_timeout(void)
{
    static long v[50];
    volatile int w = 0;
    struct timespec ts = { 0, 1000000 };
    for (int i = 0; i < 50; i++) {
        long t0 = now_us();
        fx(&w, 128, 0, &ts);
        v[i] = now_us() - t0;
    }
    report("futex_1ms_timeout", v, 50, 2500);
}

static volatile int sleeper_go;

static void *sleeper(void *arg)
{
    (void)arg;
    fx(&sleeper_go, 128, 0, 0);
    return 0;
}

static void bench_wake_to_run(void)
{
    static long v[50];
    for (int i = 0; i < 50; i++) {
        pthread_t th;
        sleeper_go = 0;
        pthread_create(&th, 0, sleeper, 0);
        usleep(3000);
        long t0 = now_us();
        sleeper_go = 1;
        fx(&sleeper_go, 129, 1, 0);
        pthread_join(th, 0);
        v[i] = now_us() - t0;
    }
    report("wake_join", v, 50, LIMIT_US);
}

static void bench_socketpair(void)
{
    static long v[ROUNDS];
    int s[2];
    char c = 'x';
    if (socketpair(AF_UNIX, SOCK_STREAM, 0, s) < 0) {
        GAP("socketpair_pingpong", "socketpair failed");
        return;
    }
    pid_t pid = fork();
    if (pid == 0) {
        for (int i = 0; i < ROUNDS; i++) {
            if (read(s[1], &c, 1) != 1)
                break;
            write(s[1], &c, 1);
        }
        _exit(0);
    }
    for (int i = 0; i < ROUNDS; i++) {
        long t0 = now_us();
        write(s[0], &c, 1);
        read(s[0], &c, 1);
        v[i] = now_us() - t0;
    }
    report("socketpair_proc_pingpong", v, ROUNDS, LIMIT_US);
}

int main(void)
{
    bench_futex();
    bench_pipe();
    bench_eventfd();
    bench_poll_wake();
    bench_poll_timeout();
    bench_epoll_timeout();
    bench_nanosleep();
    bench_futex_timeout();
    bench_wake_to_run();
    bench_socketpair();
    return 0;
}
