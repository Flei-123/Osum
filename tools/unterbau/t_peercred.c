#define TNAME "peercred"
#include "t.h"
#include <sys/socket.h>
#include <sys/un.h>
#include <sys/wait.h>

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
    CHECK("pair_short_buffer_einval", (l = 4, getsockopt(sv[0], SOL_SOCKET, SO_PEERCRED, &c, &l) == -1 && errno == EINVAL), "errno=%d", errno);
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

int main(void)
{
    pair_check();
    listener_check();
    fork_check();
    return 0;
}
