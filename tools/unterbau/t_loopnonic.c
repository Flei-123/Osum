#define TNAME "loopnonic"
#include "t.h"
#include <arpa/inet.h>
#include <netinet/in.h>
#include <sys/socket.h>
#include <sys/wait.h>

#define PORT 5701
#define BIG 200000

static struct sockaddr_in loop_addr(int port)
{
    struct sockaddr_in a;
    memset(&a, 0, sizeof a);
    a.sin_family = AF_INET;
    a.sin_port = htons(port);
    inet_pton(AF_INET, "127.0.0.1", &a.sin_addr);
    return a;
}

static int is_loopback_name(int fd, int peer)
{
    struct sockaddr_in a;
    socklen_t len = sizeof a;
    int r = peer ? getpeername(fd, (struct sockaddr *)&a, &len) : getsockname(fd, (struct sockaddr *)&a, &len);
    return r == 0 && a.sin_addr.s_addr == htonl(INADDR_LOOPBACK);
}

static ssize_t read_full(int fd, char *buf, size_t n)
{
    size_t got = 0;
    while (got < n) {
        ssize_t r = read(fd, buf + got, n - got);
        if (r <= 0) return got ? (ssize_t)got : r;
        got += r;
    }
    return got;
}

int main(void)
{
    int l = socket(AF_INET, SOCK_STREAM, 0);
    CHECK("socket_without_nic", l >= 0, "errno=%d", errno);
    if (l < 0) return 0;
    struct sockaddr_in a = loop_addr(PORT);
    CHECK("bind_loopback", bind(l, (struct sockaddr *)&a, sizeof a) == 0, "errno=%d", errno);
    CHECK("listen", listen(l, 4) == 0, "errno=%d", errno);
    CHECK("listener_sockname_loopback", is_loopback_name(l, 0), "");

    int c = socket(AF_INET, SOCK_STREAM, 0);
    CHECK("connect", connect(c, (struct sockaddr *)&a, sizeof a) == 0, "errno=%d", errno);
    int s = accept(l, 0, 0);
    CHECK("accept", s >= 0, "errno=%d", errno);
    CHECK("client_sockname_loopback", is_loopback_name(c, 0), "");
    CHECK("client_peername_loopback", is_loopback_name(c, 1), "");
    CHECK("server_sockname_loopback", is_loopback_name(s, 0), "");
    CHECK("server_peername_loopback", is_loopback_name(s, 1), "");

    char buf[8];
    CHECK("roundtrip", write(c, "hello", 5) == 5 && read_full(s, buf, 5) == 5 && memcmp(buf, "hello", 5) == 0, "errno=%d", errno);

    pid_t pid = fork();
    if (pid == 0) {
        static char big[BIG];
        memset(big, 'x', sizeof big);
        ssize_t w = send(c, big, sizeof big, 0);
        _exit(w == (ssize_t)sizeof big ? 0 : 2);
    }
    long total = 0;
    char chunk[4096];
    ssize_t r;
    while (total < BIG && (r = read(s, chunk, sizeof chunk)) > 0) total += r;
    int status = 0;
    waitpid(pid, &status, 0);
    CHECK("blocking_write_full_count", WIFEXITED(status) && WEXITSTATUS(status) == 0, "status=%d", status);
    CHECK("blocking_write_all_bytes", total == BIG, "total=%ld", total);

    int n = socket(AF_INET, SOCK_STREAM | SOCK_NONBLOCK, 0);
    struct sockaddr_in far;
    memset(&far, 0, sizeof far);
    far.sin_family = AF_INET;
    far.sin_port = htons(80);
    inet_pton(AF_INET, "10.9.9.9", &far.sin_addr);
    int fr = connect(n, (struct sockaddr *)&far, sizeof far);
    CHECK("external_connect_not_success", fr != 0, "r=%d", fr);

    close(n);
    close(c);
    close(s);
    close(l);
    return 0;
}
