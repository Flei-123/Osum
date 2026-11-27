#define TNAME "tcpmany"
#include "t.h"
#include <arpa/inet.h>
#include <fcntl.h>
#include <netinet/in.h>
#include <poll.h>
#include <sys/socket.h>

#define CONN_WANTED 24
#define CONN_PROBE_MAX 80
#define LISTEN_PORT 5444
#define CONNECT_WAIT_MS 1000
#define IO_WAIT_MS 2000
#define BACKLOG 128

static struct sockaddr_in loopback(int port)
{
    struct sockaddr_in a;
    memset(&a, 0, sizeof a);
    a.sin_family = AF_INET;
    a.sin_port = htons(port);
    inet_pton(AF_INET, "127.0.0.1", &a.sin_addr);
    return a;
}

static int listener_open(void)
{
    int fd = socket(AF_INET, SOCK_STREAM | SOCK_CLOEXEC | SOCK_NONBLOCK, 0);
    if (fd < 0)
        return -1;
    int one = 1;
    setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &one, sizeof one);
    struct sockaddr_in a = loopback(LISTEN_PORT);
    if (bind(fd, (struct sockaddr *)&a, sizeof a) != 0 || listen(fd, BACKLOG) != 0) {
        close(fd);
        return -1;
    }
    return fd;
}

static int client_start(void)
{
    int fd = socket(AF_INET, SOCK_STREAM | SOCK_CLOEXEC | SOCK_NONBLOCK, 0);
    if (fd < 0)
        return -1;
    struct sockaddr_in a = loopback(LISTEN_PORT);
    int r = connect(fd, (struct sockaddr *)&a, sizeof a);
    if (r != 0 && errno != EINPROGRESS) {
        close(fd);
        return -1;
    }
    return fd;
}

static int client_established(int fd)
{
    struct pollfd p = { .fd = fd, .events = POLLOUT };
    if (poll(&p, 1, CONNECT_WAIT_MS) <= 0)
        return 0;
    int err = 0;
    socklen_t len = sizeof err;
    if (getsockopt(fd, SOL_SOCKET, SO_ERROR, &err, &len) != 0)
        return 0;
    return err == 0;
}

static int accept_one(int lfd)
{
    struct pollfd p = { .fd = lfd, .events = POLLIN };
    if (poll(&p, 1, CONNECT_WAIT_MS) <= 0)
        return -1;
    return accept4(lfd, NULL, NULL, SOCK_NONBLOCK | SOCK_CLOEXEC);
}

static void close_all(int *fds, int n)
{
    for (int i = 0; i < n; i++)
        if (fds[i] >= 0)
            close(fds[i]);
}

static int connect_many(int lfd, int *clients, int *servers, int max, int *accepted)
{
    int established = 0;
    int started = 0;
    *accepted = 0;
    memset(clients, -1, max * sizeof(int));
    memset(servers, -1, max * sizeof(int));
    while (started < max) {
        int c = client_start();
        if (c < 0)
            break;
        clients[started++] = c;
    }
    for (int i = 0; i < started; i++) {
        if (client_established(clients[i]))
            established++;
        int s = accept_one(lfd);
        if (s >= 0)
            servers[(*accepted)++] = s;
    }
    return established;
}

static int echo_byte(int from, int to_echo, int back)
{
    char c = 'x';
    char got = 0;
    struct pollfd p;
    if (write(from, &c, 1) != 1)
        return 0;
    p.fd = to_echo;
    p.events = POLLIN;
    if (poll(&p, 1, IO_WAIT_MS) <= 0 || read(to_echo, &got, 1) != 1)
        return 0;
    if (write(to_echo, &got, 1) != 1)
        return 0;
    p.fd = back;
    if (poll(&p, 1, IO_WAIT_MS) <= 0 || read(back, &got, 1) != 1)
        return 0;
    return got == 'x';
}

static int echo_all(int *clients, int *servers, int n)
{
    int ok = 0;
    for (int i = 0; i < n; i++)
        ok += echo_byte(clients[i], servers[i], clients[i]);
    return ok;
}

int main(int argc, char **argv)
{
    if (argc > 1)
        return 0;
    int clients[CONN_PROBE_MAX];
    int servers[CONN_PROBE_MAX];
    int accepted = 0;
    int lfd = listener_open();
    if (lfd < 0) {
        FAIL("listener_open", "errno=%d", errno);
        return 0;
    }

    int est = connect_many(lfd, clients, servers, CONN_WANTED, &accepted);
    CHECK("connect_24_at_once", est >= CONN_WANTED, "only %d of %d established", est, CONN_WANTED);
    CHECK("accept_24_at_once", accepted >= CONN_WANTED, "only %d of %d accepted", accepted, CONN_WANTED);
    int echoed = echo_all(clients, servers, accepted < est ? accepted : est);
    CHECK("echo_24_pairs", echoed >= CONN_WANTED, "only %d echoed", echoed);
    close_all(clients, CONN_WANTED);
    close_all(servers, accepted);
    usleep(200000);

    int est2 = connect_many(lfd, clients, servers, CONN_WANTED, &accepted);
    CHECK("reuse_after_close", est2 >= CONN_WANTED && accepted >= CONN_WANTED,
        "first %d then %d established, %d accepted", est, est2, accepted);
    close_all(clients, CONN_WANTED);
    close_all(servers, accepted);
    close(lfd);
    return 0;
}
