#define TNAME "pollwake"
#include "t.h"
#include <fcntl.h>
#include <poll.h>
#include <signal.h>
#include <stdint.h>
#include <stdlib.h>
#include <sys/epoll.h>
#include <sys/eventfd.h>
#include <sys/inotify.h>
#include <sys/signalfd.h>
#include <sys/socket.h>
#include <sys/timerfd.h>
#include <sys/uio.h>
#include <sys/un.h>
#include <sys/wait.h>
#include <time.h>

#define ACT_DELAY_MS 300
#define WAIT_MS 2500
#define FAST_MS 1500
#define ROUNDS 3
#define FILL_CHUNK 1000
#define DRAIN_CHUNK 65536
#define DRAIN_FRAMES 20
#define BIG_WRITE 100000
#define LISTEN_PATH "/tmp/pollwake.sock"
#define WATCH_DIR "/tmp"
#define WATCH_FILE "/tmp/pollwake.file"

struct sc {
    int fd[2];
    int watch;
    int close_in_parent;
    int no_child;
    short want;
};

struct scenario {
    const char *name;
    int (*setup)(struct sc *);
    void (*act)(struct sc *);
};

static uint64_t now_ms(void)
{
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return (uint64_t)ts.tv_sec * 1000 + ts.tv_nsec / 1000000;
}

static void nap_ms(long ms)
{
    struct timespec ts = { ms / 1000, (ms % 1000) * 1000000L };
    nanosleep(&ts, 0);
}

static void set_nonblock(int fd)
{
    fcntl(fd, F_SETFL, fcntl(fd, F_GETFL) | O_NONBLOCK);
}

static void fill(int fd)
{
    char buf[FILL_CHUNK];
    memset(buf, 'f', sizeof buf);
    while (write(fd, buf, sizeof buf) > 0)
        ;
}

static void drain_msgs(int fd, int frames)
{
    char buf[FILL_CHUNK];
    for (int i = 0; i < frames; i++) {
        struct iovec iov = { buf, sizeof buf };
        struct msghdr mh = { .msg_iov = &iov, .msg_iovlen = 1 };
        if (recvmsg(fd, &mh, MSG_DONTWAIT) <= 0)
            break;
    }
}

static void drain_stream_msg(int fd)
{
    static char buf[DRAIN_CHUNK];
    struct iovec iov = { buf, sizeof buf };
    struct msghdr mh = { .msg_iov = &iov, .msg_iovlen = 1 };
    recvmsg(fd, &mh, MSG_DONTWAIT);
}

static int setup_pair(struct sc *s, int type)
{
    if (socketpair(AF_UNIX, type, 0, s->fd) != 0)
        return -1;
    s->watch = s->fd[0];
    return 0;
}

static int setup_full(struct sc *s, int type)
{
    if (setup_pair(s, type) != 0)
        return -1;
    set_nonblock(s->fd[0]);
    fill(s->fd[0]);
    s->want = POLLOUT;
    return 0;
}

static int setup_full_stream(struct sc *s) { return setup_full(s, SOCK_STREAM); }
static int setup_full_seq(struct sc *s) { return setup_full(s, SOCK_SEQPACKET); }
static int setup_full_dgram(struct sc *s) { return setup_full(s, SOCK_DGRAM); }

static int setup_empty_stream(struct sc *s)
{
    s->want = POLLIN;
    return setup_pair(s, SOCK_STREAM);
}

static int setup_empty_dgram(struct sc *s)
{
    s->want = POLLIN;
    return setup_pair(s, SOCK_DGRAM);
}

static int setup_hup_stream(struct sc *s)
{
    s->want = POLLIN;
    s->close_in_parent = 1;
    s->want = POLLIN | POLLHUP;
    return setup_pair(s, SOCK_STREAM);
}

static int setup_full_pipe(struct sc *s)
{
    int p[2];
    if (pipe(p) != 0)
        return -1;
    s->fd[0] = p[0];
    s->fd[1] = p[1];
    s->watch = p[1];
    s->want = POLLOUT;
    set_nonblock(p[1]);
    fill(p[1]);
    return 0;
}

static int setup_empty_pipe(struct sc *s)
{
    int p[2];
    if (pipe(p) != 0)
        return -1;
    s->fd[0] = p[0];
    s->fd[1] = p[1];
    s->watch = p[0];
    s->want = POLLIN;
    return 0;
}

static int setup_hup_pipe(struct sc *s)
{
    s->close_in_parent = 1;
    if (setup_empty_pipe(s) != 0)
        return -1;
    s->want = POLLIN | POLLHUP;
    return 0;
}

static int setup_timerfd(struct sc *s)
{
    struct itimerspec its = { { 0, 0 }, { 0, ACT_DELAY_MS * 1000000L } };
    s->fd[0] = timerfd_create(CLOCK_MONOTONIC, 0);
    if (s->fd[0] < 0 || timerfd_settime(s->fd[0], 0, &its, 0) != 0)
        return -1;
    s->watch = s->fd[0];
    s->want = POLLIN;
    s->no_child = 1;
    return 0;
}

static int setup_eventfd(struct sc *s)
{
    s->fd[0] = eventfd(0, 0);
    s->watch = s->fd[0];
    s->want = POLLIN;
    return s->fd[0] < 0 ? -1 : 0;
}

static int setup_signalfd(struct sc *s)
{
    sigset_t set;
    sigemptyset(&set);
    sigaddset(&set, SIGUSR1);
    struct timespec none = { 0, 0 };
    sigprocmask(SIG_BLOCK, &set, 0);
    while (sigtimedwait(&set, 0, &none) > 0)
        ;
    s->fd[0] = signalfd(-1, &set, 0);
    s->watch = s->fd[0];
    s->want = POLLIN;
    return s->fd[0] < 0 ? -1 : 0;
}

static int setup_inotify(struct sc *s)
{
    unlink(WATCH_FILE);
    s->fd[0] = inotify_init();
    if (s->fd[0] < 0 || inotify_add_watch(s->fd[0], WATCH_DIR, IN_CREATE) < 0)
        return -1;
    s->watch = s->fd[0];
    s->want = POLLIN;
    return 0;
}

static int setup_listener(struct sc *s)
{
    struct sockaddr_un a = { .sun_family = AF_UNIX };
    strcpy(a.sun_path, LISTEN_PATH);
    unlink(LISTEN_PATH);
    s->fd[0] = socket(AF_UNIX, SOCK_STREAM, 0);
    if (s->fd[0] < 0 || bind(s->fd[0], (struct sockaddr *)&a, sizeof a) != 0 || listen(s->fd[0], 4) != 0)
        return -1;
    s->watch = s->fd[0];
    s->want = POLLIN;
    return 0;
}

static void act_drain_stream_msg(struct sc *s) { drain_stream_msg(s->fd[1]); }
static void act_drain_frames(struct sc *s) { drain_msgs(s->fd[1], DRAIN_FRAMES); }

static void act_recv(struct sc *s)
{
    static char buf[DRAIN_CHUNK];
    recv(s->fd[1], buf, sizeof buf, MSG_DONTWAIT);
}

static void act_read_sock(struct sc *s)
{
    static char buf[DRAIN_CHUNK];
    set_nonblock(s->fd[1]);
    read(s->fd[1], buf, sizeof buf);
}

static void act_read_pipe(struct sc *s)
{
    static char buf[DRAIN_CHUNK];
    read(s->fd[0], buf, sizeof buf);
}

static void act_readv(struct sc *s)
{
    static char buf[DRAIN_CHUNK];
    struct iovec iov[2] = { { buf, 4096 }, { buf + 4096, DRAIN_CHUNK - 4096 } };
    readv(s->fd[1], iov, 2);
}

static void act_recvmmsg(struct sc *s)
{
    static char buf[DRAIN_CHUNK];
    struct iovec iov = { buf, sizeof buf };
    struct mmsghdr mm = { .msg_hdr = { .msg_iov = &iov, .msg_iovlen = 1 } };
    recvmmsg(s->fd[1], &mm, 1, MSG_DONTWAIT, 0);
}

static void act_writev(struct sc *s)
{
    struct iovec iov[2] = { { "x", 1 }, { "y", 1 } };
    writev(s->fd[1], iov, 2);
}

static void act_sendmmsg(struct sc *s)
{
    struct iovec iov = { "x", 1 };
    struct mmsghdr mm = { .msg_hdr = { .msg_iov = &iov, .msg_iovlen = 1 } };
    sendmmsg(s->fd[1], &mm, 1, 0);
}

static void act_send(struct sc *s) { send(s->fd[1], "x", 1, 0); }

static void act_sendmsg(struct sc *s)
{
    struct iovec iov = { "x", 1 };
    struct msghdr mh = { .msg_iov = &iov, .msg_iovlen = 1 };
    sendmsg(s->fd[1], &mh, 0);
}

static void act_write_pipe(struct sc *s) { write(s->fd[1], "x", 1); }

static void act_write_pipe_big(struct sc *s)
{
    static char buf[BIG_WRITE];
    write(s->fd[1], buf, sizeof buf);
}

static void act_close_peer(struct sc *s) { close(s->fd[1]); }
static void act_exit_peer(struct sc *s) { (void)s; _exit(0); }
static void act_shutdown_wr(struct sc *s) { shutdown(s->fd[1], SHUT_WR); }

static void act_eventfd(struct sc *s)
{
    uint64_t one = 1;
    write(s->fd[0], &one, sizeof one);
}

static void act_signal(struct sc *s) { (void)s; kill(getppid(), SIGUSR1); }
static void act_create_file(struct sc *s) { (void)s; close(creat(WATCH_FILE, 0600)); }

static void act_connect(struct sc *s)
{
    struct sockaddr_un a = { .sun_family = AF_UNIX };
    int c = socket(AF_UNIX, SOCK_STREAM, 0);
    (void)s;
    strcpy(a.sun_path, LISTEN_PATH);
    connect(c, (struct sockaddr *)&a, sizeof a);
}

static void act_none(struct sc *s) { (void)s; }

static const struct scenario scenarios[] = {
    { "stream_recvmsg_frees_room", setup_full_stream, act_drain_stream_msg },
    { "seqpacket_recvmsg_frees_room", setup_full_seq, act_drain_frames },
    { "dgram_recvmsg_frees_room", setup_full_dgram, act_drain_frames },
    { "stream_recv_frees_room", setup_full_stream, act_recv },
    { "stream_read_frees_room", setup_full_stream, act_read_sock },
    { "pipe_read_frees_room", setup_full_pipe, act_read_pipe },
    { "stream_readv_frees_room", setup_full_stream, act_readv },
    { "stream_recvmmsg_frees_room", setup_full_stream, act_recvmmsg },
    { "stream_writev_data", setup_empty_stream, act_writev },
    { "stream_sendmmsg_data", setup_empty_stream, act_sendmmsg },
    { "stream_send_data", setup_empty_stream, act_send },
    { "stream_sendmsg_data", setup_empty_stream, act_sendmsg },
    { "dgram_sendmsg_data", setup_empty_dgram, act_sendmsg },
    { "pipe_write_data", setup_empty_pipe, act_write_pipe },
    { "pipe_write_big_data", setup_empty_pipe, act_write_pipe_big },
    { "stream_peer_close", setup_hup_stream, act_close_peer },
    { "stream_peer_exit", setup_hup_stream, act_exit_peer },
    { "stream_peer_shutdown", setup_empty_stream, act_shutdown_wr },
    { "pipe_writer_close", setup_hup_pipe, act_close_peer },
    { "pipe_writer_exit", setup_hup_pipe, act_exit_peer },
    { "timerfd_expiry", setup_timerfd, act_none },
    { "eventfd_write", setup_eventfd, act_eventfd },
    { "signalfd_signal", setup_signalfd, act_signal },
    { "inotify_create", setup_inotify, act_create_file },
    { "listener_connect", setup_listener, act_connect },
};

static pid_t spawn_actor(const struct scenario *sc, struct sc *s)
{
    pid_t pid = fork();
    if (pid == 0) {
        nap_ms(ACT_DELAY_MS);
        sc->act(s);
        nap_ms(WAIT_MS * 2);
        _exit(0);
    }
    if (s->close_in_parent) {
        close(s->fd[1]);
        s->fd[1] = -1;
    }
    return pid;
}

static void reap_actor(pid_t pid)
{
    if (pid > 0) {
        kill(pid, SIGKILL);
        waitpid(pid, 0, 0);
    }
}

static short wait_poll(struct sc *s, uint64_t *ms)
{
    struct pollfd p = { s->watch, s->want, 0 };
    uint64_t t0 = now_ms();
    int r = poll(&p, 1, WAIT_MS);
    *ms = now_ms() - t0;
    return r > 0 ? p.revents : 0;
}

static short wait_epoll(struct sc *s, uint64_t *ms)
{
    struct epoll_event ev = { .events = (s->want & POLLOUT) ? EPOLLOUT : EPOLLIN };
    int ep = epoll_create1(0);
    uint64_t t0 = now_ms();
    int r;
    if (ep < 0 || epoll_ctl(ep, EPOLL_CTL_ADD, s->watch, &ev) != 0)
        return 0;
    r = epoll_wait(ep, &ev, 1, WAIT_MS);
    *ms = now_ms() - t0;
    close(ep);
    return r > 0 ? s->want : 0;
}

static int run_round(const struct scenario *sc, int use_epoll, uint64_t *slowest)
{
    struct sc s = { { -1, -1 }, -1, 0, 0, 0 };
    uint64_t ms = 0;
    pid_t pid = 0;
    short got;
    if (sc->setup(&s) != 0)
        return -1;
    if (!s.no_child)
        pid = spawn_actor(sc, &s);
    got = use_epoll ? wait_epoll(&s, &ms) : wait_poll(&s, &ms);
    reap_actor(pid);
    if (s.fd[0] >= 0)
        close(s.fd[0]);
    if (s.fd[1] >= 0)
        close(s.fd[1]);
    if (ms > *slowest)
        *slowest = ms;
    return (got & s.want) != 0 && ms < FAST_MS;
}

static void run_scenario(const struct scenario *sc, int use_epoll)
{
    char name[96];
    uint64_t slowest = 0;
    int bad = 0;
    snprintf(name, sizeof name, "%s_%s", sc->name, use_epoll ? "epoll" : "poll");
    for (int i = 0; i < ROUNDS; i++) {
        int r = run_round(sc, use_epoll, &slowest);
        if (r < 0) {
            GAP(name, "setup failed errno=%d", errno);
            return;
        }
        bad += r == 0;
    }
    CHECK(name, bad == 0, "%d of %d rounds late or missed, slowest %llu ms", bad, ROUNDS, (unsigned long long)slowest);
}

int main(void)
{
    signal(SIGPIPE, SIG_IGN);
    for (unsigned i = 0; i < sizeof scenarios / sizeof scenarios[0]; i++) {
        run_scenario(&scenarios[i], 0);
        run_scenario(&scenarios[i], 1);
    }
    return 0;
}
