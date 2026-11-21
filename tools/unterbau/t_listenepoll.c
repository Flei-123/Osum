#define TNAME "listenepoll"
#include "t.h"
#include <arpa/inet.h>
#include <netinet/in.h>
#include <signal.h>
#include <sys/epoll.h>
#include <sys/ioctl.h>
#include <sys/socket.h>
#include <sys/syscall.h>
#include <sys/wait.h>

#define BASE_PORT 5710
#define WAIT_MS 3000
#define EPOLLEXCLUSIVE_BIT (1u << 28)

static struct sockaddr_in loop_addr(int port)
{
    struct sockaddr_in a;
    memset(&a, 0, sizeof a);
    a.sin_family = AF_INET;
    a.sin_port = htons(port);
    inet_pton(AF_INET, "127.0.0.1", &a.sin_addr);
    return a;
}

static int listen_twice;
static int listen_nonblock;

static int make_listener(int port)
{
    int l = socket(AF_INET, SOCK_STREAM, 0);
    int one = 1;
    setsockopt(l, SOL_SOCKET, SO_REUSEADDR, &one, sizeof one);
    if (listen_nonblock)
        ioctl(l, FIONBIO, &one);
    struct sockaddr_in a = loop_addr(port);
    if (bind(l, (struct sockaddr *)&a, sizeof a) != 0 || listen(l, 8) != 0)
        return -1;
    if (listen_twice && listen(l, 8) != 0)
        return -1;
    return l;
}

static int wait_pwait(int ep, struct epoll_event *ev, int ms)
{
    return syscall(SYS_epoll_pwait, ep, ev, 1, ms, NULL, 8);
}

static int connect_to(int port)
{
    int c = socket(AF_INET, SOCK_STREAM, 0);
    struct sockaddr_in a = loop_addr(port);
    if (connect(c, (struct sockaddr *)&a, sizeof a) != 0)
        return -1;
    return c;
}

static int child_wait_for_accept(int l, unsigned events, int use_pwait, int port, int use_second)
{
    int p[2];
    if (pipe(p) != 0)
        return -1;
    pid_t pid = fork();
    if (pid == 0) {
        int ep = epoll_create1(0);
        struct epoll_event ev;
        memset(&ev, 0, sizeof ev);
        ev.events = events;
        ev.data.u64 = 77;
        int ok = epoll_ctl(ep, EPOLL_CTL_ADD, l, &ev) == 0;
        if (use_second) {
            int l2 = make_listener(port + 100);
            ev.data.u64 = 78;
            ok = ok && l2 >= 0 && epoll_ctl(ep, EPOLL_CTL_ADD, l2, &ev) == 0;
        }
        char go = ok ? 'g' : 'x';
        (void)!write(p[1], &go, 1);
        struct epoll_event out;
        memset(&out, 0, sizeof out);
        int n = use_pwait ? wait_pwait(ep, &out, WAIT_MS) : epoll_wait(ep, &out, 1, WAIT_MS);
        int fd = -1;
        if (n == 1)
            fd = accept(l, 0, 0);
        _exit(n == 1 && fd >= 0 && out.data.u64 == 77 ? 0 : 1);
    }
    char go = 0;
    (void)!read(p[0], &go, 1);
    close(p[0]);
    close(p[1]);
    int result = -1;
    if (go == 'g') {
        struct timespec ts = {0, 200000000};
        nanosleep(&ts, 0);
        int c = connect_to(port);
        int st = 0;
        waitpid(pid, &st, 0);
        result = c >= 0 && WIFEXITED(st) && WEXITSTATUS(st) == 0;
        if (c >= 0)
            close(c);
    } else {
        waitpid(pid, 0, 0);
    }
    return result;
}

static void run_case(const char *name, unsigned events, int use_pwait, int port_off, int use_second)
{
    int port = BASE_PORT + port_off;
    int l = make_listener(port);
    if (l < 0) {
        FAIL(name, "listen errno=%d", errno);
        return;
    }
    int r = child_wait_for_accept(l, events, use_pwait, port, use_second);
    CHECK(name, r == 1, "result=%d", r);
    close(l);
}

static void own_process_case(void)
{
    int port = BASE_PORT + 20;
    int l = make_listener(port);
    int ep = epoll_create1(0);
    struct epoll_event ev;
    memset(&ev, 0, sizeof ev);
    ev.events = EPOLLIN;
    epoll_ctl(ep, EPOLL_CTL_ADD, l, &ev);
    int c = connect_to(port);
    struct epoll_event out;
    int n = epoll_wait(ep, &out, 1, WAIT_MS);
    CHECK("same_process_connect_before_wait", c >= 0 && n == 1, "n=%d", n);
    close(c);
    close(l);
    close(ep);
}

static void late_connect_in_same_process_case(void)
{
    int port = BASE_PORT + 21;
    int l = make_listener(port);
    int ep = epoll_create1(0);
    struct epoll_event ev;
    memset(&ev, 0, sizeof ev);
    ev.events = EPOLLIN;
    epoll_ctl(ep, EPOLL_CTL_ADD, l, &ev);
    pid_t pid = fork();
    if (pid == 0) {
        struct timespec ts = {0, 300000000};
        nanosleep(&ts, 0);
        int c = connect_to(port);
        nanosleep(&ts, 0);
        if (c >= 0)
            close(c);
        _exit(0);
    }
    struct epoll_event out;
    int n = epoll_wait(ep, &out, 1, WAIT_MS);
    CHECK("same_process_connect_during_wait", n == 1, "n=%d", n);
    waitpid(pid, 0, 0);
    close(l);
    close(ep);
}

int main(void)
{
    signal(SIGPIPE, SIG_IGN);
    own_process_case();
    late_connect_in_same_process_case();
    run_case("inherited_listener_epoll_wait", EPOLLIN, 0, 0, 0);
    run_case("inherited_listener_epoll_pwait", EPOLLIN, 1, 1, 0);
    run_case("inherited_listener_rdhup", EPOLLIN | EPOLLRDHUP, 1, 2, 0);
    run_case("inherited_listener_exclusive", EPOLLIN | EPOLLEXCLUSIVE_BIT, 1, 3, 0);
    run_case("inherited_listener_two_listeners", EPOLLIN | EPOLLRDHUP, 1, 4, 1);
    listen_twice = 1;
    run_case("listen_twice_inherited", EPOLLIN | EPOLLRDHUP, 1, 5, 0);
    listen_nonblock = 1;
    run_case("listen_twice_nonblock_inherited", EPOLLIN | EPOLLRDHUP, 1, 7, 0);
    return 0;
}
