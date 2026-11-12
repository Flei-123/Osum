#include <arpa/inet.h>
#include <linux/futex.h>
#include <netinet/in.h>
#include <netinet/tcp.h>
#include <poll.h>
#include <sys/epoll.h>
#include <sys/socket.h>

#define WAKE_ROUNDS 2000
#define SLEEP_ROUNDS 100
#define MUTEX_ROUNDS 20000
#define TCP_PORT 47931
#define SOCK_PROC_ROUNDS 300

static volatile int fx_turn;
static long fx_rounds;

static long fx_call(volatile int *addr, int op, int val, const struct timespec *ts)
{
    return syscall(SYS_futex, addr, op, val, ts, 0, 0);
}

static void fx_wait_for(int want)
{
    int cur;
    while ((cur = __atomic_load_n(&fx_turn, __ATOMIC_ACQUIRE)) != want)
        fx_call(&fx_turn, FUTEX_WAIT, cur, 0);
}

static void fx_pass(int next)
{
    __atomic_store_n(&fx_turn, next, __ATOMIC_RELEASE);
    fx_call(&fx_turn, FUTEX_WAKE, 1, 0);
}

static void *fx_peer(void *arg)
{
    for (long i = 0; i < fx_rounds; i++) {
        fx_wait_for(1);
        fx_pass(0);
    }
    return arg;
}

static void run_futex_pingpong(long n)
{
    pthread_t th;
    fx_turn = 0;
    fx_rounds = n;
    if (pthread_create(&th, 0, fx_peer, 0))
        exit(8);
    for (long i = 0; i < n; i++) {
        fx_pass(1);
        fx_wait_for(0);
    }
    pthread_join(th, 0);
}

static pthread_mutex_t cv_mu = PTHREAD_MUTEX_INITIALIZER;
static pthread_cond_t cv_a = PTHREAD_COND_INITIALIZER;
static pthread_cond_t cv_b = PTHREAD_COND_INITIALIZER;
static int cv_turn;

static void *cv_peer(void *arg)
{
    for (long i = 0; i < fx_rounds; i++) {
        pthread_mutex_lock(&cv_mu);
        while (cv_turn != 1)
            pthread_cond_wait(&cv_b, &cv_mu);
        cv_turn = 0;
        pthread_cond_signal(&cv_a);
        pthread_mutex_unlock(&cv_mu);
    }
    return arg;
}

static void run_cond_pingpong(long n)
{
    pthread_t th;
    cv_turn = 0;
    fx_rounds = n;
    if (pthread_create(&th, 0, cv_peer, 0))
        exit(8);
    for (long i = 0; i < n; i++) {
        pthread_mutex_lock(&cv_mu);
        cv_turn = 1;
        pthread_cond_signal(&cv_b);
        while (cv_turn != 0)
            pthread_cond_wait(&cv_a, &cv_mu);
        pthread_mutex_unlock(&cv_mu);
    }
    pthread_join(th, 0);
}

static int pp_up[2], pp_down[2];

static void *pp_echo(void *arg)
{
    char b;
    while (read(pp_up[0], &b, 1) == 1)
        (void)!write(pp_down[1], &b, 1);
    return arg;
}

static void pp_threaded(long n, int use_epoll, int use_poll)
{
    pthread_t th;
    char b = 'x';
    int ep = -1;
    if (pipe(pp_up) || pipe(pp_down))
        exit(6);
    if (use_epoll) {
        struct epoll_event ev = {.events = EPOLLIN, .data.fd = pp_down[0]};
        ep = epoll_create1(0);
        if (ep < 0 || epoll_ctl(ep, EPOLL_CTL_ADD, pp_down[0], &ev))
            exit(9);
    }
    if (pthread_create(&th, 0, pp_echo, 0))
        exit(8);
    for (long i = 0; i < n; i++) {
        (void)!write(pp_up[1], &b, 1);
        if (use_epoll) {
            struct epoll_event out;
            epoll_wait(ep, &out, 1, -1);
        } else if (use_poll) {
            struct pollfd p = {.fd = pp_down[0], .events = POLLIN};
            poll(&p, 1, -1);
        }
        (void)!read(pp_down[0], &b, 1);
    }
    close(pp_up[1]);
    pthread_join(th, 0);
    close(pp_up[0]);
    close(pp_down[0]);
    close(pp_down[1]);
    if (ep >= 0)
        close(ep);
}

static void run_pipe_thread(long n)
{
    pp_threaded(n, 0, 0);
}

static void run_epoll_pingpong(long n)
{
    pp_threaded(n, 1, 0);
}

static void run_poll_pingpong(long n)
{
    pp_threaded(n, 0, 1);
}

static int sock_fd;

static void *sock_echo(void *arg)
{
    char b;
    while (read(sock_fd, &b, 1) == 1)
        (void)!write(sock_fd, &b, 1);
    return arg;
}

static void sock_rounds(int a, int b_fd, long n)
{
    pthread_t th;
    char b = 'x';
    sock_fd = b_fd;
    if (pthread_create(&th, 0, sock_echo, 0))
        exit(8);
    for (long i = 0; i < n; i++) {
        (void)!write(a, &b, 1);
        (void)!read(a, &b, 1);
    }
    shutdown(a, SHUT_RDWR);
    pthread_join(th, 0);
    close(a);
    close(b_fd);
}

static void run_socketpair_rt(long n)
{
    int sv[2];
    if (socketpair(AF_UNIX, SOCK_STREAM, 0, sv))
        exit(10);
    sock_rounds(sv[0], sv[1], n);
}

static void run_socketpair_proc_rt(long n)
{
    int sv[2];
    char b = 'x';
    if (socketpair(AF_UNIX, SOCK_STREAM, 0, sv))
        exit(10);
    pid_t pid = fork();
    if (pid == 0) {
        close(sv[0]);
        while (read(sv[1], &b, 1) == 1)
            (void)!write(sv[1], &b, 1);
        _exit(0);
    }
    close(sv[1]);
    for (long i = 0; i < n; i++) {
        (void)!write(sv[0], &b, 1);
        (void)!read(sv[0], &b, 1);
    }
    close(sv[0]);
    waitpid(pid, 0, 0);
}

static void run_socketpair_sendrecv_rt(long n)
{
    int sv[2];
    char b = 'x';
    if (socketpair(AF_UNIX, SOCK_STREAM, 0, sv))
        exit(10);
    pid_t pid = fork();
    if (pid == 0) {
        close(sv[0]);
        while (recv(sv[1], &b, 1, 0) == 1)
            (void)!send(sv[1], &b, 1, 0);
        _exit(0);
    }
    close(sv[1]);
    for (long i = 0; i < n; i++) {
        (void)!send(sv[0], &b, 1, 0);
        (void)!recv(sv[0], &b, 1, 0);
    }
    close(sv[0]);
    waitpid(pid, 0, 0);
}

static void run_tcp_loopback_rt(long n)
{
    struct sockaddr_in addr = {.sin_family = AF_INET, .sin_port = htons(TCP_PORT)};
    int one = 1;
    int ls = socket(AF_INET, SOCK_STREAM, 0);
    int c = socket(AF_INET, SOCK_STREAM, 0);
    addr.sin_addr.s_addr = htonl(INADDR_LOOPBACK);
    if (ls < 0 || c < 0) {
        emit("tcp_setup_socket_failed", -1, 0);
        return;
    }
    setsockopt(ls, SOL_SOCKET, SO_REUSEADDR, &one, sizeof one);
    if (bind(ls, (struct sockaddr *)&addr, sizeof addr) || listen(ls, 1)) {
        emit("tcp_setup_bind_failed", -1, 0);
        return;
    }
    if (connect(c, (struct sockaddr *)&addr, sizeof addr)) {
        emit("tcp_setup_connect_failed", -1, 0);
        return;
    }
    int s = accept(ls, 0, 0);
    if (s < 0) {
        emit("tcp_setup_accept_failed", -1, 0);
        return;
    }
    setsockopt(c, IPPROTO_TCP, TCP_NODELAY, &one, sizeof one);
    setsockopt(s, IPPROTO_TCP, TCP_NODELAY, &one, sizeof one);
    sock_rounds(c, s, n);
    close(ls);
}

static void run_nanosleep_1ms(long n)
{
    struct timespec ts = {0, 1000000};
    for (long i = 0; i < n; i++)
        nanosleep(&ts, 0);
}

static void run_nanosleep_100us(long n)
{
    struct timespec ts = {0, 100000};
    for (long i = 0; i < n; i++)
        nanosleep(&ts, 0);
}

static void run_poll_timeout_1ms(long n)
{
    for (long i = 0; i < n; i++)
        poll(0, 0, 1);
}

static void run_futex_timeout_1ms(long n)
{
    volatile int word = 0;
    struct timespec ts = {0, 1000000};
    for (long i = 0; i < n; i++)
        fx_call(&word, FUTEX_WAIT, 0, &ts);
}

static pthread_mutex_t mc_mu = PTHREAD_MUTEX_INITIALIZER;
static long mc_count;

static void *mc_peer(void *arg)
{
    for (long i = 0; i < fx_rounds; i++) {
        pthread_mutex_lock(&mc_mu);
        mc_count++;
        pthread_mutex_unlock(&mc_mu);
    }
    return arg;
}

static void run_mutex_contend(long n)
{
    pthread_t th;
    fx_rounds = n;
    if (pthread_create(&th, 0, mc_peer, 0))
        exit(8);
    mc_peer(0);
    pthread_join(th, 0);
}

static void wake_run_all(void)
{
    measure("futex_pingpong", run_futex_pingpong, WAKE_ROUNDS, 1, 1);
    measure("cond_pingpong", run_cond_pingpong, WAKE_ROUNDS, 1, 1);
    measure("pipe_thread_rt", run_pipe_thread, WAKE_ROUNDS, 1, 1);
    measure("poll_pingpong", run_poll_pingpong, WAKE_ROUNDS, 1, 1);
    measure("epoll_pingpong", run_epoll_pingpong, WAKE_ROUNDS, 1, 1);
    measure("socketpair_rt", run_socketpair_rt, SOCK_PROC_ROUNDS, 1, 1);
    measure("socketpair_proc_rt", run_socketpair_proc_rt, SOCK_PROC_ROUNDS, 1, 1);
    measure("socketpair_sendrecv_rt", run_socketpair_sendrecv_rt, SOCK_PROC_ROUNDS, 1, 1);
    measure("tcp_loopback_rt", run_tcp_loopback_rt, WAKE_ROUNDS, 1, 1);
    measure("nanosleep_1ms", run_nanosleep_1ms, SLEEP_ROUNDS, 1, 1);
    measure("nanosleep_100us", run_nanosleep_100us, SLEEP_ROUNDS, 1, 1);
    measure("poll_timeout_1ms", run_poll_timeout_1ms, SLEEP_ROUNDS, 1, 1);
    measure("futex_timeout_1ms", run_futex_timeout_1ms, SLEEP_ROUNDS, 1, 1);
    measure("mutex_contend", run_mutex_contend, MUTEX_ROUNDS, 1, 1);
}
