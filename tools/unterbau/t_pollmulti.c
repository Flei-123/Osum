#define TNAME "pollmulti"
#include "t.h"
#include <pthread.h>
#include <poll.h>
#include <fcntl.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>
#include <sched.h>
#include <sys/eventfd.h>
#include <sys/epoll.h>
#include <sys/mman.h>
#include <sys/socket.h>
#include <sys/wait.h>
#include <netinet/in.h>
#include <arpa/inet.h>
#include <time.h>

#define ROUNDS 200
#define PROCESS_ROUNDS 40
#define MAX_POLLERS 4
#define MAX_BG_FDS 7
#define POLL_TIMEOUT_MS 3000
#define STALL_US 400000
#define MEDIAN_LIMIT_US 15000
#define CONNECT_SLACK_US 3000
#define ACK_WAIT_US 8000000
#define CONNECT_ROUNDS 20
#define ECHO_IP "10.0.2.100"
#define ECHO_PORT 7777

enum { EV_PIPE, EV_SOCKPAIR, EV_EVENTFD };

struct event {
    int kind;
    int rd;
    int wr;
};

struct background {
    int fds[MAX_BG_FDS];
    int count;
};

struct poller {
    struct event ev;
    struct background *bg;
    volatile long signal_us;
    volatile long latency_us;
    volatile int acked;
    volatile int stop;
    int use_epoll;
    int ready;
};

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

static void set_nonblock(int fd)
{
    fcntl(fd, F_SETFL, fcntl(fd, F_GETFL) | O_NONBLOCK);
}

static int event_open(struct event *e, int kind)
{
    int p[2];
    e->kind = kind;
    if (kind == EV_EVENTFD) {
        e->rd = e->wr = eventfd(0, EFD_NONBLOCK);
        return e->rd < 0 ? -1 : 0;
    }
    int r = kind == EV_PIPE ? pipe(p) : socketpair(AF_UNIX, SOCK_STREAM, 0, p);
    if (r < 0)
        return -1;
    e->rd = p[0];
    e->wr = p[1];
    set_nonblock(e->rd);
    set_nonblock(e->wr);
    return 0;
}

static void event_signal(struct event *e)
{
    char c = 'x';
    uint64_t one = 1;
    if (e->kind == EV_EVENTFD)
        (void)!write(e->wr, &one, sizeof one);
    else
        (void)!write(e->wr, &c, 1);
}

static void event_clear(struct event *e)
{
    char buf[64];
    uint64_t v;
    if (e->kind == EV_EVENTFD) {
        (void)!read(e->rd, &v, sizeof v);
        return;
    }
    while (read(e->rd, buf, sizeof buf) > 0)
        ;
}

static int tcp_echo_connect(void)
{
    struct sockaddr_in ea;
    memset(&ea, 0, sizeof ea);
    ea.sin_family = AF_INET;
    ea.sin_port = htons(ECHO_PORT);
    ea.sin_addr.s_addr = inet_addr(ECHO_IP);
    int s = socket(AF_INET, SOCK_STREAM, 0);
    if (s < 0)
        return -1;
    if (connect(s, (void *)&ea, sizeof ea) < 0) {
        close(s);
        return -1;
    }
    return s;
}

static void background_add(struct background *bg, int fd)
{
    if (fd >= 0 && bg->count < MAX_BG_FDS)
        bg->fds[bg->count++] = fd;
}

static void background_open(struct background *bg)
{
    int us[2], pp[2];
    bg->count = 0;
    background_add(bg, tcp_echo_connect());
    int ls = socket(AF_INET, SOCK_STREAM, 0);
    if (ls >= 0) {
        struct sockaddr_in a;
        memset(&a, 0, sizeof a);
        a.sin_family = AF_INET;
        if (bind(ls, (void *)&a, sizeof a) == 0 && listen(ls, 4) == 0)
            background_add(bg, ls);
        else
            close(ls);
    }
    if (socketpair(AF_UNIX, SOCK_STREAM, 0, us) == 0)
        background_add(bg, us[0]);
    background_add(bg, eventfd(0, EFD_NONBLOCK));
    if (pipe(pp) == 0)
        background_add(bg, pp[0]);
    background_add(bg, socket(AF_INET, SOCK_DGRAM, 0));
}

static void wait_once(struct poller *p)
{
    struct pollfd fds[MAX_BG_FDS + 1];
    int n = 0;
    fds[n].fd = p->ev.rd;
    fds[n].events = POLLIN;
    n++;
    for (int i = 0; i < p->bg->count; i++) {
        fds[n].fd = p->bg->fds[i];
        fds[n].events = POLLIN;
        n++;
    }
    for (int i = 0; i < n; i++)
        fds[i].revents = 0;
    if (poll(fds, n, POLL_TIMEOUT_MS) <= 0 || !(fds[0].revents & POLLIN))
        return;
    p->latency_us = now_us() - p->signal_us;
    event_clear(&p->ev);
    p->acked++;
}

static void wait_once_epoll(struct poller *p, int ep)
{
    struct epoll_event out[MAX_BG_FDS + 1];
    int n = epoll_wait(ep, out, MAX_BG_FDS + 1, POLL_TIMEOUT_MS);
    for (int i = 0; i < n; i++) {
        if (out[i].data.fd != p->ev.rd)
            continue;
        p->latency_us = now_us() - p->signal_us;
        event_clear(&p->ev);
        p->acked++;
    }
}

static void *poller_main(void *arg)
{
    struct poller *p = arg;
    int ep = -1;
    if (p->use_epoll) {
        struct epoll_event e;
        ep = epoll_create1(0);
        e.events = EPOLLIN;
        e.data.fd = p->ev.rd;
        epoll_ctl(ep, EPOLL_CTL_ADD, p->ev.rd, &e);
        for (int i = 0; i < p->bg->count; i++) {
            e.data.fd = p->bg->fds[i];
            epoll_ctl(ep, EPOLL_CTL_ADD, p->bg->fds[i], &e);
        }
    }
    p->ready = 1;
    while (!p->stop) {
        if (p->use_epoll)
            wait_once_epoll(p, ep);
        else
            wait_once(p);
    }
    return 0;
}

static struct poller *poller_alloc(int count)
{
    void *m = mmap(0, count * sizeof(struct poller), PROT_READ | PROT_WRITE, MAP_SHARED | MAP_ANONYMOUS, -1, 0);
    return m == MAP_FAILED ? 0 : m;
}

static int poller_start(struct poller *p, int kind, int use_epoll, struct background *bg, pthread_t *th)
{
    memset(p, 0, sizeof *p);
    p->bg = bg;
    p->use_epoll = use_epoll;
    if (event_open(&p->ev, kind) < 0)
        return -1;
    if (pthread_create(th, 0, poller_main, p) != 0)
        return -1;
    while (!p->ready)
        usleep(200);
    return 0;
}

static void poller_stop(struct poller *p, pthread_t th)
{
    p->stop = 1;
    event_signal(&p->ev);
    pthread_join(th, 0);
}

static long fire(struct poller *p)
{
    int before = p->acked;
    long deadline = now_us() + ACK_WAIT_US;
    p->signal_us = now_us();
    event_signal(&p->ev);
    while (p->acked == before && now_us() < deadline)
        usleep(100);
    return p->acked == before ? ACK_WAIT_US : p->latency_us;
}

static void summarize(const char *name, long *v, int n)
{
    int stalls = 0;
    for (int i = 0; i < n; i++)
        if (v[i] >= STALL_US)
            stalls++;
    qsort(v, n, sizeof *v, cmp_long);
    long med = v[n / 2];
    if (stalls == 0 && med <= MEDIAN_LIMIT_US)
        PASS(name, "median_us=%ld worst_us=%ld stalls=0 rounds=%d", med, v[n - 1], n);
    else
        FAIL(name, "median_us=%ld worst_us=%ld stalls=%d rounds=%d", med, v[n - 1], stalls, n);
}

static void run_single(const char *name, int kind, int use_epoll, struct background *bg)
{
    static long v[ROUNDS];
    pthread_t th;
    struct poller *p = poller_alloc(1);
    if (!p || poller_start(p, kind, use_epoll, bg, &th) < 0) {
        GAP(name, "setup failed errno %d", errno);
        return;
    }
    for (int i = 0; i < ROUNDS; i++) {
        usleep(rand() % 3000);
        v[i] = fire(p);
    }
    poller_stop(p, th);
    summarize(name, v, ROUNDS);
}

static void run_tight(struct background *bg)
{
    static long v[ROUNDS * 2];
    pthread_t th[2];
    struct poller *p = poller_alloc(2);
    if (!p || poller_start(&p[0], EV_PIPE, 0, bg, &th[0]) < 0 || poller_start(&p[1], EV_SOCKPAIR, 0, bg, &th[1]) < 0) {
        GAP("tight_two_pollers", "setup failed errno %d", errno);
        return;
    }
    for (int i = 0; i < ROUNDS; i++) {
        v[i * 2] = fire(&p[0]);
        v[i * 2 + 1] = fire(&p[1]);
    }
    poller_stop(&p[0], th[0]);
    poller_stop(&p[1], th[1]);
    summarize("tight_two_pollers", v, ROUNDS * 2);
}

static volatile int noise_stop;

static void *noise_main(void *arg)
{
    char c = 'n';
    int s = tcp_echo_connect();
    (void)arg;
    while (!noise_stop && s >= 0) {
        if (write(s, &c, 1) != 1 || read(s, &c, 1) != 1)
            break;
        usleep(300);
    }
    if (s >= 0)
        close(s);
    return 0;
}

static void run_many(struct background *bg)
{
    static long v[ROUNDS * MAX_POLLERS];
    pthread_t th[MAX_POLLERS], noise;
    struct poller *p = poller_alloc(MAX_POLLERS);
    int kinds[MAX_POLLERS] = { EV_PIPE, EV_SOCKPAIR, EV_EVENTFD, EV_PIPE };
    int n = 0;
    if (!p) {
        GAP("four_pollers_noise", "alloc failed");
        return;
    }
    for (int i = 0; i < MAX_POLLERS; i++) {
        if (poller_start(&p[i], kinds[i], 0, bg, &th[i]) < 0) {
            GAP("four_pollers_noise", "setup failed errno %d", errno);
            return;
        }
    }
    noise_stop = 0;
    pthread_create(&noise, 0, noise_main, 0);
    for (int i = 0; i < ROUNDS; i++) {
        usleep(rand() % 2000);
        v[n++] = fire(&p[rand() % MAX_POLLERS]);
    }
    noise_stop = 1;
    pthread_join(noise, 0);
    for (int i = 0; i < MAX_POLLERS; i++)
        poller_stop(&p[i], th[i]);
    summarize("four_pollers_noise", v, n);
}

struct stamp_poller {
    int ev_rd;
    int ack_wr;
    struct background *bg;
};

static void *stamp_poller_main(void *arg)
{
    struct stamp_poller *sp = arg;
    struct pollfd fds[MAX_BG_FDS + 1];
    for (;;) {
        int n = 1;
        fds[0].fd = sp->ev_rd;
        fds[0].events = POLLIN;
        for (int i = 0; i < sp->bg->count; i++, n++) {
            fds[n].fd = sp->bg->fds[i];
            fds[n].events = POLLIN;
        }
        for (int i = 0; i < n; i++)
            fds[i].revents = 0;
        if (poll(fds, n, POLL_TIMEOUT_MS) <= 0 || !(fds[0].revents & POLLIN))
            continue;
        long stamp;
        if (read(sp->ev_rd, &stamp, sizeof stamp) != sizeof stamp)
            continue;
        if (stamp == 0)
            return 0;
        long lat = now_us() - stamp;
        (void)!write(sp->ack_wr, &lat, sizeof lat);
    }
}

static int child_fire_rounds(int ev_wr, int ack_rd)
{
    int stalls = 0;
    for (int i = 0; i < PROCESS_ROUNDS; i++) {
        long lat = 0;
        usleep(rand() % 3000);
        long stamp = now_us();
        (void)!write(ev_wr, &stamp, sizeof stamp);
        if (read(ack_rd, &lat, sizeof lat) != sizeof lat)
            return 2;
        stalls += lat >= STALL_US;
        if (i < 4) {
            char line[64];
            int n = snprintf(line, sizeof line, "P round %d latency_us=%ld\n", i, lat);
            (void)!write(1, line, n);
        }
    }
    return stalls ? 1 : 0;
}

static void run_from_process(struct background *bg)
{
    int ev[2], ack[2];
    pthread_t th;
    struct stamp_poller sp;
    if (pipe(ev) < 0 || pipe(ack) < 0) {
        GAP("wake_from_process", "pipe failed errno %d", errno);
        return;
    }
    sp.ev_rd = ev[0];
    sp.ack_wr = ack[1];
    sp.bg = bg;
    pthread_create(&th, 0, stamp_poller_main, &sp);
    pid_t pid = fork();
    if (pid == 0)
        _exit(child_fire_rounds(ev[1], ack[0]));
    int st = 0;
    waitpid(pid, &st, 0);
    long stop = 0;
    (void)!write(ev[1], &stop, sizeof stop);
    pthread_join(th, 0);
    if (st != 0)
        FAIL("wake_from_process", "child status=%d", st);
    else
        PASS("wake_from_process", "rounds=%d stalls=0", PROCESS_ROUNDS);
}

static int connect_nonblock_start(int *out, struct sockaddr_in *ea)
{
    int s = socket(AF_INET, SOCK_STREAM, 0);
    if (s < 0)
        return -1;
    set_nonblock(s);
    int r = connect(s, (void *)ea, sizeof *ea);
    if (r < 0 && errno != EINPROGRESS) {
        close(s);
        return -1;
    }
    *out = s;
    return 0;
}

static long connect_by_poll(struct sockaddr_in *ea)
{
    int s;
    long t0 = now_us();
    if (connect_nonblock_start(&s, ea) < 0)
        return -1;
    struct pollfd p = { s, POLLOUT, 0 };
    int r = poll(&p, 1, POLL_TIMEOUT_MS);
    long dt = now_us() - t0;
    close(s);
    return r == 1 ? dt : -1;
}

static long connect_by_spin(struct sockaddr_in *ea)
{
    int s;
    long t0 = now_us();
    if (connect_nonblock_start(&s, ea) < 0)
        return -1;
    struct pollfd p = { s, POLLOUT, 0 };
    long dt = -1;
    while (now_us() - t0 < POLL_TIMEOUT_MS * 1000L) {
        if (poll(&p, 1, 0) == 1) {
            dt = now_us() - t0;
            break;
        }
        usleep(100);
    }
    close(s);
    return dt;
}

static long connect_blocking(struct sockaddr_in *ea)
{
    long t0 = now_us();
    int s = socket(AF_INET, SOCK_STREAM, 0);
    if (s < 0 || connect(s, (void *)ea, sizeof *ea) < 0)
        return -1;
    long dt = now_us() - t0;
    close(s);
    return dt;
}

static void run_connect(void)
{
    static long v[CONNECT_ROUNDS], spin[CONNECT_ROUNDS], blk[CONNECT_ROUNDS];
    struct sockaddr_in ea;
    memset(&ea, 0, sizeof ea);
    ea.sin_family = AF_INET;
    ea.sin_port = htons(ECHO_PORT);
    ea.sin_addr.s_addr = inet_addr(ECHO_IP);
    for (int i = 0; i < CONNECT_ROUNDS; i++) {
        v[i] = connect_by_poll(&ea);
        spin[i] = connect_by_spin(&ea);
        blk[i] = connect_blocking(&ea);
        if (v[i] < 0 || spin[i] < 0 || blk[i] < 0) {
            GAP("connect_nonblock_pollout", "connect failed or timed out in round %d", i);
            return;
        }
    }
    qsort(v, CONNECT_ROUNDS, sizeof *v, cmp_long);
    qsort(spin, CONNECT_ROUNDS, sizeof *spin, cmp_long);
    qsort(blk, CONNECT_ROUNDS, sizeof *blk, cmp_long);
    long med = v[CONNECT_ROUNDS / 2];
    long base = spin[CONNECT_ROUNDS / 2];
    long limit = blk[CONNECT_ROUNDS / 2] + CONNECT_SLACK_US;
    if (med <= limit)
        PASS("connect_nonblock_pollout", "median_us=%ld worst_us=%ld spin_median_us=%ld blocking_median_us=%ld limit_us=%ld", med, v[CONNECT_ROUNDS - 1], base, blk[CONNECT_ROUNDS / 2], limit);
    else
        FAIL("connect_nonblock_pollout", "median_us=%ld worst_us=%ld spin_median_us=%ld blocking_median_us=%ld limit_us=%ld", med, v[CONNECT_ROUNDS - 1], base, blk[CONNECT_ROUNDS / 2], limit);
}

int main(void)
{
    struct background bg;
    background_open(&bg);
    run_connect();
    run_single("pipe_among_fds", EV_PIPE, 0, &bg);
    run_single("socketpair_among_fds", EV_SOCKPAIR, 0, &bg);
    run_single("eventfd_among_fds", EV_EVENTFD, 0, &bg);
    run_single("epoll_among_fds", EV_PIPE, 1, &bg);
    run_tight(&bg);
    run_many(&bg);
    run_from_process(&bg);
    return 0;
}
