#define TNAME "ephemeral"
#include "t.h"
#include <arpa/inet.h>
#include <netinet/in.h>
#include <sys/socket.h>

#define NODE_BACKLOG 511
#define PORT_MIN 1024

static struct sockaddr_in loopback(int port)
{
    struct sockaddr_in a;
    memset(&a, 0, sizeof a);
    a.sin_family = AF_INET;
    a.sin_port = htons(port);
    inet_pton(AF_INET, "127.0.0.1", &a.sin_addr);
    return a;
}

static int local_port(int fd)
{
    struct sockaddr_in a;
    socklen_t n = sizeof a;
    if (getsockname(fd, (struct sockaddr *)&a, &n) != 0)
        return -1;
    return ntohs(a.sin_port);
}

static int bound_listener(int *port)
{
    int l = socket(AF_INET, SOCK_STREAM | SOCK_NONBLOCK | SOCK_CLOEXEC, 0);
    int one = 1;
    setsockopt(l, SOL_SOCKET, SO_REUSEADDR, &one, sizeof one);
    struct sockaddr_in a = loopback(0);
    if (bind(l, (struct sockaddr *)&a, sizeof a) != 0)
        return -1;
    *port = local_port(l);
    return l;
}

int main(void)
{
    int port = 0;
    int l = bound_listener(&port);
    if (l < 0)
        FAIL("bind_port_zero", "bind failed");
    else if (port < PORT_MIN)
        FAIL("bind_port_zero", "getsockname port %d", port);
    else
        PASS("bind_port_zero");
    errno = 0;
    int r = listen(l, NODE_BACKLOG);
    if (r != 0)
        FAIL("listen_backlog_511", "listen rc=%d errno=%d", r, errno);
    else
        PASS("listen_backlog_511");
    int same = local_port(l) == port;
    if (same)
        PASS("port_stable_after_listen");
    else
        FAIL("port_stable_after_listen", "port changed");
    int c = socket(AF_INET, SOCK_STREAM, 0);
    struct sockaddr_in a = loopback(port);
    int cr = connect(c, (struct sockaddr *)&a, sizeof a);
    int acc = -1;
    int tries = 0;
    while (acc < 0 && tries++ < 200) {
        acc = accept(l, NULL, NULL);
        if (acc < 0)
            usleep(10000);
    }
    if (cr == 0 && acc >= 0)
        PASS("connect_accept_ephemeral");
    else
        FAIL("connect_accept_ephemeral", "connect=%d accept=%d", cr, acc);
    int l2 = socket(AF_INET, SOCK_STREAM, 0);
    if (listen(l2, 16) == 0 && local_port(l2) >= PORT_MIN && local_port(l2) != port)
        PASS("listen_autobind");
    else
        FAIL("listen_autobind", "port %d", local_port(l2));
    int p2 = 0;
    int l3 = bound_listener(&p2);
    if (l3 >= 0 && p2 >= PORT_MIN && p2 != port && p2 != local_port(l2))
        PASS("distinct_ephemeral_ports");
    else
        FAIL("distinct_ephemeral_ports", "p1=%d p2=%d", port, p2);
    return 0;
}
