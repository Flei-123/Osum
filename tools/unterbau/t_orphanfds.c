#define TNAME "orphanfds"
#include "t.h"
#include <fcntl.h>
#include <signal.h>
#include <stdlib.h>
#include <poll.h>
#include <sys/epoll.h>
#include <sys/eventfd.h>
#include <sys/socket.h>
#include <sys/stat.h>
#include <sys/syscall.h>
#include <sys/un.h>
#include <sys/wait.h>

#define CHILDREN 8
#define PIPES 12
#define SETTLE_POLLS 50
#define SETTLE_USEC 20000
#define LEAK_SLACK 2
#define PEER_EOF_WAIT_MS 2000

static long open_files(void)
{
    char buf[64];
    int fd = open("/proc/sys/fs/file-nr", O_RDONLY);
    if (fd < 0) return -1;
    int n = (int)read(fd, buf, sizeof buf - 1);
    close(fd);
    if (n <= 0) return -1;
    buf[n] = 0;
    return strtol(buf, 0, 10);
}

static long settled_open_files(long target)
{
    long now = open_files();
    for (int i = 0; i < SETTLE_POLLS && now > target + LEAK_SLACK; i++) {
        usleep(SETTLE_USEC);
        now = open_files();
    }
    return now;
}

static void send_one(int sk, int fd)
{
    char data = 'x';
    struct iovec iov = { &data, 1 };
    char ctl[CMSG_SPACE(sizeof(int))];
    struct msghdr mh = { 0 };
    mh.msg_iov = &iov;
    mh.msg_iovlen = 1;
    mh.msg_control = ctl;
    mh.msg_controllen = sizeof ctl;
    struct cmsghdr *c = CMSG_FIRSTHDR(&mh);
    c->cmsg_level = SOL_SOCKET;
    c->cmsg_type = SCM_RIGHTS;
    c->cmsg_len = CMSG_LEN(sizeof(int));
    memcpy(CMSG_DATA(c), &fd, sizeof(int));
    (void)!sendmsg(sk, &mh, MSG_DONTWAIT);
}

static void hold_resources(const char *path, int inflight_sk)
{
    int p[2], sv[2], srv, cli, acc;
    struct sockaddr_un sa = { .sun_family = AF_UNIX };
    for (int i = 0; i < PIPES; i++) {
        if (pipe(p) == 0 && inflight_sk >= 0 && i < 4) send_one(inflight_sk, p[0]);
    }
    socketpair(AF_UNIX, SOCK_STREAM, 0, sv);
    socketpair(AF_UNIX, SOCK_DGRAM, 0, sv);
    socketpair(AF_UNIX, SOCK_SEQPACKET, 0, sv);
    strncpy(sa.sun_path, path, sizeof sa.sun_path - 1);
    unlink(path);
    srv = socket(AF_UNIX, SOCK_STREAM, 0);
    if (bind(srv, (struct sockaddr *)&sa, sizeof sa) == 0 && listen(srv, 4) == 0) {
        cli = socket(AF_UNIX, SOCK_STREAM, 0);
        if (connect(cli, (struct sockaddr *)&sa, sizeof sa) == 0) {
            acc = accept(srv, 0, 0);
            if (acc >= 0 && inflight_sk >= 0) send_one(inflight_sk, acc);
        }
        socket(AF_UNIX, SOCK_STREAM, 0);
    }
    eventfd(0, 0);
    epoll_create1(0);
    syscall(SYS_memfd_create, "orph", 0);
    open("/proc/self/stat", O_RDONLY);
}

static pid_t spawn_holder(int idx, int inflight_sk)
{
    char path[64];
    pid_t pid = fork();
    if (pid != 0) return pid;
    snprintf(path, sizeof path, "/tmp/orph.%d.%d", (int)getppid(), idx);
    hold_resources(path, inflight_sk);
    for (;;) pause();
    return 0;
}

static void reap(pid_t pid)
{
    int st;
    waitpid(pid, &st, 0);
}

static void cleanup_paths(void)
{
    char path[64];
    for (int i = 0; i < CHILDREN; i++) {
        snprintf(path, sizeof path, "/tmp/orph.%d.%d", (int)getpid(), i);
        unlink(path);
    }
}

int main(void)
{
    long base = open_files();
    if (base < 0) {
        GAP("file_nr", "errno=%d", errno);
        return 0;
    }

    int pr[2];
    socketpair(AF_UNIX, SOCK_STREAM, 0, pr);
    pid_t holder = fork();
    if (holder == 0) {
        close(pr[0]);
        for (;;) pause();
    }
    close(pr[1]);
    usleep(100000);
    kill(holder, SIGKILL);
    struct pollfd pf = { pr[0], POLLIN, 0 };
    int pn = poll(&pf, 1, PEER_EOF_WAIT_MS);
    char eof;
    long er = pn > 0 ? (long)read(pr[0], &eof, 1) : -1;
    CHECK("killed_unreaped_closes_peer", pn > 0 && er == 0, "poll=%d read=%ld", pn, er);
    reap(holder);
    close(pr[0]);

    base = open_files();
    pid_t kids[CHILDREN];
    for (int i = 0; i < CHILDREN; i++) kids[i] = spawn_holder(i, -1);
    usleep(200000);
    long held = open_files();
    for (int i = 0; i < CHILDREN; i++) kill(kids[i], SIGKILL);
    for (int i = 0; i < CHILDREN; i++) reap(kids[i]);
    long after = settled_open_files(base);
    CHECK("kill_releases_all", held > base && after <= base + LEAK_SLACK, "base=%ld held=%ld after=%ld", base, held, after);
    cleanup_paths();

    int sv[2];
    socketpair(AF_UNIX, SOCK_STREAM, 0, sv);
    base = open_files();
    for (int i = 0; i < CHILDREN; i++) kids[i] = spawn_holder(i, sv[0]);
    usleep(200000);
    for (int i = 0; i < CHILDREN; i++) kill(kids[i], SIGKILL);
    for (int i = 0; i < CHILDREN; i++) reap(kids[i]);
    close(sv[0]);
    close(sv[1]);
    after = settled_open_files(base - 2);
    CHECK("kill_inflight_released", after <= base - 2 + LEAK_SLACK, "base=%ld after=%ld", base, after);
    cleanup_paths();

    base = open_files();
    for (int round = 0; round < 6; round++) {
        int q[2];
        int pp[2];
        socketpair(AF_UNIX, SOCK_STREAM, 0, q);
        for (int i = 0; i < 5; i++) {
            if (pipe(pp) == 0) {
                send_one(q[0], pp[0]);
                send_one(q[1], pp[1]);
                close(pp[0]);
                close(pp[1]);
            }
        }
        close(q[0]);
        close(q[1]);
    }
    after = settled_open_files(base);
    CHECK("unreceived_inflight_released", after <= base + LEAK_SLACK, "base=%ld after=%ld", base, after);
    return 0;
}
