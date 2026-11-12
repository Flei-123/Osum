#include <arpa/inet.h>
#include <linux/futex.h>
#include <netinet/in.h>
#include <netinet/tcp.h>
#include <sys/epoll.h>
#include <sys/socket.h>

#define SBP_TCP_PORT 47123
#define SBP_STREAM_BLOCK 65536
#define SBP_SLEEP_NS 1000000L

static int sbp_a = -1, sbp_b = -1;
static pid_t sbp_child;
static volatile int sbp_turn;
static long sbp_rounds;
static int sbp_epfd = -1;

static void run_vfork(long n)
{
    for (long i = 0; i < n; i++) {
        pid_t pid = vfork();
        if (pid == 0)
            _exit(0);
        waitpid(pid, 0, 0);
    }
}

static void run_nanosleep(long n)
{
    struct timespec ts = {0, SBP_SLEEP_NS};
    for (long i = 0; i < n; i++)
        nanosleep(&ts, 0);
}

static void sbp_echo_child(int in_fd, int out_fd)
{
    char b;
    while (read(in_fd, &b, 1) == 1)
        if (write(out_fd, &b, 1) != 1)
            break;
    _exit(0);
}

static void run_sock_roundtrip(long n)
{
    char b = 'x';
    for (long i = 0; i < n; i++) {
        if (write(sbp_a, &b, 1) != 1 || read(sbp_a, &b, 1) != 1)
            exit(14);
    }
}

static void sbp_socketpair(void)
{
    int sv[2];
    if (!sb_wanted("socketpair_roundtrip"))
        return;
    if (socketpair(AF_UNIX, SOCK_STREAM, 0, sv)) {
        emit_fail("socketpair_roundtrip");
        return;
    }
    sbp_child = fork();
    if (sbp_child == 0) {
        close(sv[0]);
        sbp_echo_child(sv[1], sv[1]);
    }
    close(sv[1]);
    sbp_a = sv[0];
    measure("socketpair_roundtrip", run_sock_roundtrip, 2000, 1, 1);
    close(sbp_a);
    waitpid(sbp_child, 0, 0);
}

static void run_epoll_roundtrip(long n)
{
    char b = 'x';
    struct epoll_event ev;
    for (long i = 0; i < n; i++) {
        if (write(sbp_a, &b, 1) != 1 || epoll_wait(sbp_epfd, &ev, 1, -1) != 1 || read(sbp_b, &b, 1) != 1)
            exit(15);
    }
}

static void sbp_epoll(void)
{
    int up[2], down[2];
    struct epoll_event ev = {.events = EPOLLIN};
    if (!sb_wanted("epoll_pipe_roundtrip"))
        return;
    sbp_epfd = epoll_create1(0);
    if (sbp_epfd < 0 || pipe(up) || pipe(down)) {
        emit_fail("epoll_pipe_roundtrip");
        return;
    }
    ev.data.fd = down[0];
    if (epoll_ctl(sbp_epfd, EPOLL_CTL_ADD, down[0], &ev)) {
        emit_fail("epoll_pipe_roundtrip");
        return;
    }
    sbp_child = fork();
    if (sbp_child == 0) {
        close(up[1]);
        close(down[0]);
        sbp_echo_child(up[0], down[1]);
    }
    sbp_a = up[1];
    sbp_b = down[0];
    measure("epoll_pipe_roundtrip", run_epoll_roundtrip, 2000, 1, 1);
    close(up[1]);
    waitpid(sbp_child, 0, 0);
    close(sbp_epfd);
}

static void sbp_futex_wait(volatile int *addr, int val)
{
    while (__atomic_load_n(addr, __ATOMIC_ACQUIRE) == val)
        syscall(SYS_futex, addr, FUTEX_WAIT, val, 0, 0, 0);
}

static void sbp_futex_set(int val)
{
    __atomic_store_n(&sbp_turn, val, __ATOMIC_RELEASE);
    syscall(SYS_futex, &sbp_turn, FUTEX_WAKE, 1, 0, 0, 0);
}

static void *sbp_futex_thread(void *arg)
{
    for (long i = 0; i < sbp_rounds; i++) {
        sbp_futex_wait(&sbp_turn, 0);
        sbp_futex_set(0);
    }
    return arg;
}

static void run_futex_pingpong(long n)
{
    pthread_t th;
    sbp_rounds = n;
    sbp_turn = 0;
    if (pthread_create(&th, 0, sbp_futex_thread, 0))
        exit(16);
    for (long i = 0; i < n; i++) {
        sbp_futex_set(1);
        sbp_futex_wait(&sbp_turn, 1);
    }
    pthread_join(th, 0);
}

static int sbp_tcp_pair(int *client_fd, int *server_fd)
{
    struct sockaddr_in addr = {.sin_family = AF_INET, .sin_port = htons(SBP_TCP_PORT)};
    int one = 1;
    int lfd = socket(AF_INET, SOCK_STREAM, 0);
    inet_pton(AF_INET, "127.0.0.1", &addr.sin_addr);
    if (lfd < 0)
        return 0;
    setsockopt(lfd, SOL_SOCKET, SO_REUSEADDR, &one, sizeof one);
    if (bind(lfd, (struct sockaddr *)&addr, sizeof addr) || listen(lfd, 1))
        return 0;
    *client_fd = socket(AF_INET, SOCK_STREAM, 0);
    if (*client_fd < 0 || connect(*client_fd, (struct sockaddr *)&addr, sizeof addr))
        return 0;
    *server_fd = accept(lfd, 0, 0);
    close(lfd);
    if (*server_fd < 0)
        return 0;
    setsockopt(*client_fd, IPPROTO_TCP, TCP_NODELAY, &one, sizeof one);
    setsockopt(*server_fd, IPPROTO_TCP, TCP_NODELAY, &one, sizeof one);
    return 1;
}

static void run_tcp_stream(long n)
{
    for (long i = 0; i < n; i++)
        if (write(sbp_a, io_buf, SBP_STREAM_BLOCK) != SBP_STREAM_BLOCK)
            exit(17);
}

static void sbp_tcp_run(const char *name, bench_fn fn, long batch, int echo)
{
    int cfd = -1, sfd = -1;
    char sink[SBP_STREAM_BLOCK];
    if (!sb_wanted(name))
        return;
    if (!sbp_tcp_pair(&cfd, &sfd)) {
        emit_fail(name);
        return;
    }
    sbp_child = fork();
    if (sbp_child == 0) {
        close(cfd);
        if (echo)
            sbp_echo_child(sfd, sfd);
        while (read(sfd, sink, sizeof sink) > 0)
            ;
        _exit(0);
    }
    close(sfd);
    sbp_a = cfd;
    measure(name, fn, batch, 1, 1);
    close(cfd);
    waitpid(sbp_child, 0, 0);
}

static void sbp_run_all(void)
{
    measure("vfork_exit_wait", run_vfork, 50, 1, 1);
    measure("nanosleep_1ms", run_nanosleep, 20, 1, 1);
    sbp_socketpair();
    sbp_epoll();
    measure("futex_pingpong", run_futex_pingpong, 2000, 1, 1);
    sbp_tcp_run("tcp_loopback_roundtrip", run_sock_roundtrip, 2000, 1);
    sbp_tcp_run("tcp_loopback_write_64kib", run_tcp_stream, 256, 0);
}
