/* the event plumbing of a GUI program: pipe2, poll/select, epoll, eventfd, timerfd, signalfd, socketpair + fd passing, inotify. */
#define TNAME "events"
#include "t.h"
#include <fcntl.h>
#include <poll.h>
#include <signal.h>
#include <stdlib.h>
#include <sys/epoll.h>
#include <sys/eventfd.h>
#include <sys/inotify.h>
#include <sys/select.h>
#include <sys/signalfd.h>
#include <sys/socket.h>
#include <sys/stat.h>
#include <sys/timerfd.h>
#include <sys/un.h>
#include <sys/wait.h>
#include <time.h>

static long now_ms(void) { struct timespec t; clock_gettime(CLOCK_MONOTONIC, &t); return t.tv_sec * 1000 + t.tv_nsec / 1000000; }

int main(void)
{
    int p[2];
    errno = 0;
    int r = pipe2(p, O_NONBLOCK | O_CLOEXEC);
    CHECKC("pipe2", r == 0);
    if (r == 0) {
        char c;
        errno = 0; ssize_t n = read(p[0], &c, 1);
        CHECK("pipe_nonblock_eagain", n == -1 && errno == EAGAIN, "read -> %zd errno %d", n, errno);
        int fl = fcntl(p[0], F_GETFD);
        CHECK("pipe_cloexec", fl >= 0 && (fl & FD_CLOEXEC), "FD_CLOEXEC not set (%d)", fl);
        int fl2 = fcntl(p[0], F_GETFL);
        CHECK("pipe_o_nonblock_flag", fl2 >= 0 && (fl2 & O_NONBLOCK), "O_NONBLOCK not reported");
        struct pollfd pf = { p[0], POLLIN, 0 };
        CHECK("poll_empty_pipe", poll(&pf, 1, 20) == 0, "poll reported readiness on an empty pipe");
        (void)!write(p[1], "z", 1);
        pf.revents = 0;
        CHECK("poll_ready_pipe", poll(&pf, 1, 1000) == 1 && (pf.revents & POLLIN), "poll did not see the byte");
        fd_set rs; FD_ZERO(&rs); FD_SET(p[0], &rs); struct timeval tv = { 1, 0 };
        CHECK("select_ready_pipe", select(p[0] + 1, &rs, 0, 0, &tv) == 1, "select failed");
        close(p[1]);
        n = read(p[0], &c, 1); n = read(p[0], &c, 1);
        CHECK("pipe_eof_after_close", n == 0, "read -> %zd", n);
        pf.revents = 0;
        poll(&pf, 1, 100);
        CHECK("poll_hup", (pf.revents & POLLHUP) != 0, "revents 0x%x", pf.revents);
        close(p[0]);
    }

    /* ---- epoll */
    errno = 0;
    int ep = epoll_create1(EPOLL_CLOEXEC);
    CHECKC("epoll_create1", ep >= 0);
    int pp[2]; (void)!pipe(pp);
    if (ep >= 0) {
        struct epoll_event ev = { .events = EPOLLIN, .data.u32 = 77 };
        errno = 0; r = epoll_ctl(ep, EPOLL_CTL_ADD, pp[0], &ev);
        CHECKC("epoll_ctl_add", r == 0);
        struct epoll_event out[4];
        r = epoll_wait(ep, out, 4, 20);
        CHECK("epoll_wait_timeout", r == 0, "epoll_wait -> %d", r);
        (void)!write(pp[1], "a", 1);
        r = epoll_wait(ep, out, 4, 1000);
        CHECK("epoll_wait_ready", r == 1 && out[0].data.u32 == 77 && (out[0].events & EPOLLIN), "r=%d", r);
        /* level triggered: still ready */
        r = epoll_wait(ep, out, 4, 100);
        CHECK("epoll_level_triggered", r == 1, "second wait returned %d", r);
        /* edge triggered */
        ev.events = EPOLLIN | EPOLLET; r = epoll_ctl(ep, EPOLL_CTL_MOD, pp[0], &ev);
        CHECKC("epoll_ctl_mod_et", r == 0);
        epoll_wait(ep, out, 4, 100);
        r = epoll_wait(ep, out, 4, 50);
        CHECK("epoll_edge_triggered", r == 0, "edge-triggered fd reported again (%d)", r);
        r = epoll_ctl(ep, EPOLL_CTL_DEL, pp[0], 0);
        CHECKC("epoll_ctl_del", r == 0);
        /* wake from another thread-less source: timer via alarm is in t_signals; here a blocking wait woken by a child writing */
        struct epoll_event ev2 = { .events = EPOLLIN, .data.u32 = 5 }; epoll_ctl(ep, EPOLL_CTL_ADD, pp[0], &ev2);
        char drain[8]; (void)!read(pp[0], drain, 8);
        pid_t k = fork(); if (k == 0) { usleep(60000); (void)!write(pp[1], "w", 1); _exit(0); }
        long t0 = now_ms(); r = epoll_wait(ep, out, 4, 3000); long dt = now_ms() - t0;
        CHECK("epoll_blocks_until_event", r == 1 && dt >= 30 && dt < 2500, "r=%d after %ld ms", r, dt);
        waitpid(k, 0, 0);
    }

    /* ---- eventfd */
    errno = 0; int efd = eventfd(0, EFD_NONBLOCK | EFD_CLOEXEC);
    CHECKC("eventfd", efd >= 0);
    if (efd >= 0) {
        uint64_t v = 5;
        (void)!write(efd, &v, 8); v = 3; (void)!write(efd, &v, 8);
        v = 0; ssize_t n = read(efd, &v, 8);
        CHECK("eventfd_counter_sum", n == 8 && v == 8, "n=%zd v=%llu", n, (unsigned long long)v);
        errno = 0; n = read(efd, &v, 8);
        CHECK("eventfd_empty_eagain", n == -1 && errno == EAGAIN, "n=%zd errno %d", n, errno);
        if (ep >= 0) { struct epoll_event e3 = { .events = EPOLLIN, .data.u32 = 9 }; epoll_ctl(ep, EPOLL_CTL_ADD, efd, &e3); v = 1; (void)!write(efd, &v, 8); struct epoll_event o[2]; r = epoll_wait(ep, o, 2, 200); CHECK("eventfd_in_epoll", r >= 1, "eventfd not seen by epoll (%d)", r); }
        int es = eventfd(2, EFD_SEMAPHORE | EFD_NONBLOCK);
        if (es >= 0) { v = 0; (void)!read(es, &v, 8); CHECK("eventfd_semaphore", v == 1, "semaphore read gave %llu", (unsigned long long)v); }
        else GAP("eventfd_semaphore", "errno %d", errno);
    }

    /* ---- timerfd */
    errno = 0; int tfd = timerfd_create(CLOCK_MONOTONIC, TFD_NONBLOCK | TFD_CLOEXEC);
    CHECKC("timerfd_create", tfd >= 0);
    if (tfd >= 0) {
        struct itimerspec its = { { 0, 0 }, { 0, 60 * 1000 * 1000 } };
        errno = 0; r = timerfd_settime(tfd, 0, &its, 0);
        CHECKC("timerfd_settime", r == 0);
        struct pollfd pf = { tfd, POLLIN, 0 };
        long t0 = now_ms(); r = poll(&pf, 1, 2000); long dt = now_ms() - t0;
        CHECK("timerfd_fires", r == 1 && dt >= 40 && dt < 1500, "poll=%d after %ld ms", r, dt);
        uint64_t exp = 0; ssize_t n = read(tfd, &exp, 8);
        CHECK("timerfd_read_count", n == 8 && exp >= 1, "n=%zd exp=%llu", n, (unsigned long long)exp);
        struct itimerspec per = { { 0, 20 * 1000 * 1000 }, { 0, 20 * 1000 * 1000 } };
        timerfd_settime(tfd, 0, &per, 0); usleep(110000); exp = 0; n = read(tfd, &exp, 8);
        CHECK("timerfd_periodic", n == 8 && exp >= 3, "expirations %llu in 110 ms of a 20 ms timer", (unsigned long long)exp);
    }

    /* ---- signalfd */
    sigset_t ss; sigemptyset(&ss); sigaddset(&ss, SIGUSR1);
    sigprocmask(SIG_BLOCK, &ss, 0);
    errno = 0; int sfd = signalfd(-1, &ss, SFD_NONBLOCK | SFD_CLOEXEC);
    CHECKC("signalfd", sfd >= 0);
    if (sfd >= 0) {
        raise(SIGUSR1);
        struct signalfd_siginfo si; ssize_t n = read(sfd, &si, sizeof si);
        CHECK("signalfd_read", n == (ssize_t)sizeof si && si.ssi_signo == SIGUSR1, "n=%zd signo=%u", n, si.ssi_signo);
    }

    /* ---- socketpair, fd passing (Wayland and IPC use exactly this) */
    int sv[2]; errno = 0;
    r = socketpair(AF_UNIX, SOCK_STREAM | SOCK_CLOEXEC, 0, sv);
    CHECKC("socketpair_stream", r == 0);
    if (r == 0) {
        (void)!write(sv[0], "ping", 4); char b[16] = { 0 }; ssize_t n = read(sv[1], b, sizeof b);
        CHECK("socketpair_roundtrip", n == 4 && !memcmp(b, "ping", 4), "n=%zd", n);
        (void)!write(sv[1], "pong", 4); n = recv(sv[0], b, sizeof b, 0);
        CHECK("socketpair_recv", n == 4, "recv -> %zd", n);
        /* send a pipe fd over the socket */
        int px[2]; (void)!pipe(px);
        char cb[CMSG_SPACE(sizeof(int))]; memset(cb, 0, sizeof cb);
        struct iovec iov = { "F", 1 };
        struct msghdr mh = { 0 }; mh.msg_iov = &iov; mh.msg_iovlen = 1; mh.msg_control = cb; mh.msg_controllen = sizeof cb;
        struct cmsghdr *cm = CMSG_FIRSTHDR(&mh); cm->cmsg_level = SOL_SOCKET; cm->cmsg_type = SCM_RIGHTS; cm->cmsg_len = CMSG_LEN(sizeof(int)); memcpy(CMSG_DATA(cm), &px[1], sizeof(int));
        errno = 0; n = sendmsg(sv[0], &mh, 0);
        CHECKC("scm_rights_sendmsg", n == 1);
        if (n == 1) {
            char rb[1]; struct iovec riov = { rb, 1 }; char rcb[CMSG_SPACE(sizeof(int))]; struct msghdr rm = { 0 };
            rm.msg_iov = &riov; rm.msg_iovlen = 1; rm.msg_control = rcb; rm.msg_controllen = sizeof rcb;
            n = recvmsg(sv[1], &rm, 0);
            struct cmsghdr *rc = n == 1 ? CMSG_FIRSTHDR(&rm) : 0;
            int got = -1; if (rc && rc->cmsg_type == SCM_RIGHTS) memcpy(&got, CMSG_DATA(rc), sizeof got);
            CHECK("scm_rights_recvmsg", got >= 0, "no descriptor arrived");
            if (got >= 0) { (void)!write(got, "viafd", 5); char o[8] = { 0 }; (void)!read(px[0], o, 5); CHECK("scm_rights_fd_works", !strcmp(o, "viafd"), "passed fd writes elsewhere ('%s')", o); }
        }
        struct pollfd pf = { sv[1], POLLIN, 0 }; r = poll(&pf, 1, 20);
        CHECK("socket_poll_empty", r == 0, "poll on an empty socket returned %d", r);
        close(sv[0]); r = poll(&pf, 1, 200);
        CHECK("socket_peer_close_seen", r == 1 && (pf.revents & (POLLHUP | POLLIN)), "close of the peer not visible (r=%d rev=0x%x)", r, pf.revents);
    }
    errno = 0; r = socketpair(AF_UNIX, SOCK_DGRAM, 0, sv);
    CHECKC("socketpair_dgram", r == 0);
    if (r == 0) { (void)!send(sv[0], "d1", 2, 0); (void)!send(sv[0], "d2", 2, 0); char b[8]; ssize_t a = recv(sv[1], b, sizeof b, 0), c = recv(sv[1], b, sizeof b, 0); CHECK("dgram_boundaries", a == 2 && c == 2, "message boundaries lost: %zd %zd", a, c); }

    /* ---- named AF_UNIX socket in the file system: bind/listen/accept/connect */
    int ls = socket(AF_UNIX, SOCK_STREAM, 0); struct sockaddr_un sa = { .sun_family = AF_UNIX }; strcpy(sa.sun_path, "/tmp/ub.sock"); unlink(sa.sun_path);
    errno = 0; r = bind(ls, (struct sockaddr *)&sa, sizeof sa);
    CHECKC("unix_bind", r == 0);
    if (r == 0) {
        listen(ls, 4);
        pid_t ck = fork();
        if (ck == 0) { int cs = socket(AF_UNIX, SOCK_STREAM, 0); if (connect(cs, (struct sockaddr *)&sa, sizeof sa) != 0) _exit(2); (void)!write(cs, "hi", 2); char b[4]; (void)!read(cs, b, 2); _exit(b[0] == 'o' ? 0 : 3); }
        errno = 0; int as = accept(ls, 0, 0);
        CHECKC("unix_accept", as >= 0);
        if (as >= 0) { char b[4] = { 0 }; (void)!read(as, b, 2); CHECK("unix_stream_data", !strcmp(b, "hi"), "got '%s'", b); (void)!write(as, "ok", 2); int st; waitpid(ck, &st, 0); CHECK("unix_client_exit", WIFEXITED(st) && WEXITSTATUS(st) == 0, "client status 0x%x", st); }
    }
    /* ---- TCP loopback socket exists? (needed by many programs even for local IPC) */
    errno = 0; int ts = socket(AF_INET, SOCK_STREAM, 0);
    CHECKC("tcp_socket", ts >= 0);
    /* ---- inotify (file monitors of toolkits). A process has few descriptors here (16): give back what the checks above are done with. */
    close(ep); close(efd); close(tfd); close(sfd); close(sv[0]); close(sv[1]); close(ls);
    /* ---- inotify */
    errno = 0; int in = inotify_init1(IN_NONBLOCK | IN_CLOEXEC);
    CHECKC("inotify_init", in >= 0);
    /* ---- ppoll with a signal mask, pselect */
    struct timespec z = { 0, 10 * 1000 * 1000 }; struct pollfd none = { -1, 0, 0 };
    errno = 0; r = ppoll(&none, 1, &z, 0);
    CHECKC("ppoll", r == 0);
    return 0;
}
