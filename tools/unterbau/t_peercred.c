#define TNAME "peercred"
#include "t.h"
#include <sys/socket.h>
#include <sys/un.h>
#include <sys/wait.h>
#include <pthread.h>
#include <signal.h>
#include <sys/ioctl.h>
#include <fcntl.h>
#include <unistd.h>
#include <sys/syscall.h>

#ifndef SO_PEERCRED
#define SO_PEERCRED 17
#endif
#ifndef SO_PEERPIDFD
#define SO_PEERPIDFD 77
#endif

struct cred {
    int pid;
    unsigned uid;
    unsigned gid;
};

static int read_cred(int fd, struct cred *c)
{
    socklen_t l = sizeof *c;
    return getsockopt(fd, SOL_SOCKET, SO_PEERCRED, c, &l);
}

static void pair_check(void)
{
    int sv[2];
    CHECKC("socketpair", socketpair(AF_UNIX, SOCK_STREAM, 0, sv) == 0);
    struct cred c;
    CHECK("pair_cred_pid", read_cred(sv[0], &c) == 0 && c.pid == getpid(), "pid=%d me=%d errno=%d", c.pid, getpid(), errno);
    CHECK("pair_cred_ids", c.uid == geteuid() && c.gid == getegid(), "uid=%u gid=%u", c.uid, c.gid);
    socklen_t l = 4;
    memset(&c, 0, sizeof c);
    int r = getsockopt(sv[0], SOL_SOCKET, SO_PEERCRED, &c, &l);
    CHECK("pair_short_buffer_truncates", r == 0 && l == 4 && c.pid == getpid(), "r=%d l=%u pid=%d errno=%d", r, (unsigned)l, c.pid, errno);
    close(sv[0]);
    close(sv[1]);
}

static void listener_check(void)
{
    const char *path = "/tmp/pc-sock";
    struct sockaddr_un a;
    memset(&a, 0, sizeof a);
    a.sun_family = AF_UNIX;
    strcpy(a.sun_path, path);
    unlink(path);
    int l = socket(AF_UNIX, SOCK_STREAM, 0);
    CHECKC("listen_socket", l >= 0 && bind(l, (struct sockaddr *)&a, sizeof a) == 0 && listen(l, 2) == 0);
    int c = socket(AF_UNIX, SOCK_STREAM, 0);
    CHECKC("connect", c >= 0 && connect(c, (struct sockaddr *)&a, sizeof a) == 0);
    int s = accept(l, 0, 0);
    CHECKC("accept", s >= 0);
    struct cred cc, sc;
    CHECK("client_sees_server_pid", read_cred(c, &cc) == 0 && cc.pid == getpid(), "pid=%d errno=%d", cc.pid, errno);
    CHECK("server_sees_client_pid", read_cred(s, &sc) == 0 && sc.pid == getpid(), "pid=%d errno=%d", sc.pid, errno);
    CHECK("server_sees_client_uid", sc.uid == geteuid() && sc.gid == getegid(), "uid=%u gid=%u", sc.uid, sc.gid);
    int pfd = -1;
    socklen_t pl = sizeof pfd;
    int r = getsockopt(s, SOL_SOCKET, SO_PEERPIDFD, &pfd, &pl);
    CHECKC("peerpidfd", r == 0 && pfd >= 0);
    if (r == 0 && pfd >= 0) close(pfd);
    int u = socket(AF_UNIX, SOCK_STREAM, 0);
    struct cred uc;
    CHECK("unconnected_pid_zero", read_cred(u, &uc) == 0 && uc.pid == 0, "pid=%d errno=%d", uc.pid, errno);
    close(u);
    close(c);
    close(s);
    close(l);
    unlink(path);
}

static void fork_check(void)
{
    int sv[2];
    if (socketpair(AF_UNIX, SOCK_STREAM, 0, sv) != 0) return;
    pid_t k = fork();
    if (k == 0) {
        struct cred c;
        int ok = read_cred(sv[1], &c) == 0 && c.pid != 0;
        _exit(ok ? 0 : 1);
    }
    int st = 0;
    waitpid(k, &st, 0);
    CHECK("fork_child_reads", WIFEXITED(st) && WEXITSTATUS(st) == 0, "st=%d", st);
    close(sv[0]);
    close(sv[1]);
}

static void eof_check(void)
{
    int sv[2];
    if (socketpair(AF_UNIX, SOCK_STREAM, 0, sv) != 0) return;
    pid_t k = fork();
    if (k == 0) {
        close(sv[0]);
        char *av[] = {"/nonexistent-loader", 0};
        execv(av[0], av);
        _exit(errno == ENOENT ? 42 : 43);
    }
    close(sv[1]);
    struct cred c;
    CHECK("eof_parent_cred_pid", read_cred(sv[0], &c) == 0 && c.pid == getpid(), "pid=%d errno=%d", c.pid, errno);
    int st = 0;
    waitpid(k, &st, 0);
    CHECK("eof_exec_enoent", WIFEXITED(st) && WEXITSTATUS(st) == 42, "st=%d", st);
    char b[8];
    struct msghdr m;
    struct iovec v = {b, sizeof b};
    memset(&m, 0, sizeof m);
    m.msg_iov = &v;
    m.msg_iovlen = 1;
    ssize_t n = recvmsg(sv[0], &m, MSG_DONTWAIT);
    CHECK("eof_recvmsg_zero", n == 0, "n=%zd errno=%d", n, errno);
    close(sv[0]);
}

static void vfork_check(void)
{
    int sv[2];
    if (socketpair(AF_UNIX, SOCK_STREAM, 0, sv) != 0) return;
    pid_t k = vfork();
    if (k == 0) {
        char *av[] = {"/nonexistent-loader", 0};
        execv(av[0], av);
        _exit(42);
    }
    int st = 0;
    waitpid(k, &st, 0);
    struct cred c;
    CHECK("vfork_parent_cred_pid", read_cred(sv[0], &c) == 0 && c.pid == getpid(), "pid=%d errno=%d", c.pid, errno);
    close(sv[0]);
    close(sv[1]);
}

static void child_cred_check(void)
{
    int sv[2];
    if (socketpair(AF_UNIX, SOCK_STREAM, 0, sv) != 0) return;
    pid_t me = getpid();
    pid_t k = fork();
    if (k == 0) {
        struct cred c;
        int ok = read_cred(sv[1], &c) == 0 && c.pid == me && c.uid == geteuid() && c.gid == getegid();
        _exit(ok ? 0 : 1);
    }
    int st = 0;
    waitpid(k, &st, 0);
    CHECK("fork_child_sees_creator_pid", WIFEXITED(st) && WEXITSTATUS(st) == 0, "st=%d", st);
    close(sv[0]);
    close(sv[1]);
}

static void on_alarm(int sig)
{
    (void)sig;
}

static ssize_t recv_once(int fd)
{
    char b[8];
    struct iovec v = {b, sizeof b};
    struct msghdr m;
    memset(&m, 0, sizeof m);
    m.msg_iov = &v;
    m.msg_iovlen = 1;
    return recvmsg(fd, &m, 0);
}

static void arm_alarm(unsigned secs)
{
    struct sigaction sa;
    memset(&sa, 0, sizeof sa);
    sa.sa_handler = on_alarm;
    sigaction(SIGALRM, &sa, 0);
    alarm(secs);
}

static void blocking_eof_check(void)
{
    int sv[2];
    if (socketpair(AF_UNIX, SOCK_STREAM | SOCK_CLOEXEC, 0, sv) != 0) return;
    pid_t k = fork();
    if (k == 0) {
        usleep(200000);
        char *av[] = {"/nonexistent-loader", 0};
        execv(av[0], av);
        _exit(42);
    }
    close(sv[1]);
    arm_alarm(5);
    ssize_t n = recv_once(sv[0]);
    alarm(0);
    CHECK("blocking_recvmsg_eof_after_child_exit", n == 0, "n=%zd errno=%d", n, errno);
    waitpid(k, 0, 0);
    close(sv[0]);
}

struct spawn_args {
    int keep;
    int other;
    pid_t child;
};

static void *spawn_thread(void *p)
{
    struct spawn_args *a = p;
    pid_t k = fork();
    if (k == 0) {
        close(a->keep);
        usleep(200000);
        _exit(0);
    }
    a->child = k;
    close(a->other);
    return 0;
}

static void thread_spawn_check(void)
{
    int sv[2];
    if (socketpair(AF_UNIX, SOCK_STREAM | SOCK_CLOEXEC, 0, sv) != 0) return;
    struct spawn_args a = {sv[0], sv[1], 0};
    pthread_t th;
    pthread_create(&th, 0, spawn_thread, &a);
    pthread_join(th, 0);
    arm_alarm(5);
    ssize_t n = recv_once(sv[0]);
    alarm(0);
    CHECK("thread_fork_blocking_recvmsg_eof", n == 0, "n=%zd errno=%d", n, errno);
    waitpid(a.child, 0, 0);
    close(sv[0]);
}

#define NS_FLAGS 0x7E020000UL
#define CLOSE_RANGE_CLOEXEC_FLAG 4U

static void bwrap_like_child(int keep)
{
    syscall(436, 3U, ~0U, CLOSE_RANGE_CLOEXEC_FLAG);
    fcntl(keep, F_SETFD, 0);
    long inner = syscall(56, NS_FLAGS | SIGCHLD, 0, 0, 0, 0);
    if (inner == 0) _exit(1);
    int st = 0;
    if (inner > 0) waitpid((pid_t)inner, &st, 0);
    _exit(1);
}

static void *bwrap_thread(void *p)
{
    struct spawn_args *a = p;
    pid_t k = fork();
    if (k == 0) bwrap_like_child(a->other);
    a->child = k;
    close(a->other);
    return 0;
}

static void bwrap_like_check(void)
{
    int sv[2];
    if (socketpair(AF_UNIX, SOCK_STREAM | SOCK_CLOEXEC, 0, sv) != 0) return;
    struct spawn_args a = {sv[0], sv[1], 0};
    pthread_t th;
    pthread_create(&th, 0, bwrap_thread, &a);
    pthread_join(th, 0);
    arm_alarm(5);
    ssize_t n = recv_once(sv[0]);
    alarm(0);
    CHECK("bwrap_like_recvmsg_eof", n == 0, "n=%zd errno=%d", n, errno);
    waitpid(a.child, 0, 0);
    close(sv[0]);
}

static void nonblock_check(void)
{
    int sv[2];
    if (socketpair(AF_UNIX, SOCK_STREAM | SOCK_CLOEXEC, 0, sv) != 0) return;
    int on = 1;
    CHECKC("fionbio_ioctl", ioctl(sv[0], FIONBIO, &on) == 0);
    arm_alarm(3);
    ssize_t n = recv_once(sv[0]);
    int e = errno;
    alarm(0);
    CHECK("fionbio_recvmsg_eagain", n == -1 && e == EAGAIN, "n=%zd errno=%d", n, e);
    int fl = fcntl(sv[1], F_GETFL);
    fcntl(sv[1], F_SETFL, fl | O_NONBLOCK);
    arm_alarm(3);
    n = recv_once(sv[1]);
    e = errno;
    alarm(0);
    CHECK("setfl_recvmsg_eagain", n == -1 && e == EAGAIN, "n=%zd errno=%d", n, e);
    close(sv[0]);
    close(sv[1]);
}

int main(void)
{
    pair_check();
    listener_check();
    fork_check();
    eof_check();
    vfork_check();
    child_cred_check();
    blocking_eof_check();
    thread_spawn_check();
    bwrap_like_check();
    nonblock_check();
    return 0;
}
