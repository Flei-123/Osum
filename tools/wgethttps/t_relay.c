#include <errno.h>
#include <poll.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/socket.h>
#include <sys/wait.h>
#include <netinet/in.h>
#include <arpa/inet.h>
#include <unistd.h>

static void report(const char *name, const char *value) { printf("WT %s %s\n", name, value); fflush(stdout); }

static int connect_tcp(const char *ip, int port)
{
    int fd = socket(AF_INET, SOCK_STREAM, 0);
    struct sockaddr_in sa = { .sin_family = AF_INET, .sin_port = htons(port) };
    inet_pton(AF_INET, ip, &sa.sin_addr);
    if (fd < 0 || connect(fd, (struct sockaddr *)&sa, sizeof sa) != 0) return -1;
    return fd;
}

static void relay_child(int net_fd)
{
    struct pollfd pfd[2] = { { .fd = 0, .events = POLLIN }, { .fd = net_fd, .events = POLLIN } };
    char buf[2048];
    int open_count = 2;
    while (open_count > 0) {
        int pr = poll(pfd, 2, 20000);
        dprintf(2, "CH poll=%d r0=%x r1=%x\n", pr, pfd[0].revents, pfd[1].revents);
        if (pr <= 0) _exit(3);
        for (int i = 0; i < 2; i++) {
            if (!(pfd[i].revents & (POLLIN | POLLHUP))) continue;
            ssize_t n = read(pfd[i].fd, buf, sizeof buf);
            dprintf(2, "CH read i=%d n=%zd errno=%d\n", i, n, errno);
            if (n < 0) _exit(4);
            if (n == 0) { pfd[i].fd = -1; open_count--; if (i == 1) _exit(0); continue; }
            if (write(i == 0 ? net_fd : 1, buf, n) != n) _exit(5);
        }
    }
    _exit(0);
}

int main(int argc, char **argv)
{
    int port = atoi(argv[1]);
    int net_fd = connect_tcp("10.0.2.2", port);
    if (net_fd < 0) { report("relay-connect", "FAIL"); return 1; }
    int sp[2];
    if (socketpair(AF_UNIX, SOCK_STREAM, 0, sp) != 0) { report("relay-socketpair", "FAIL"); return 1; }
    pid_t pid = fork();
    if (pid == 0) {
        close(sp[0]);
        dup2(sp[1], 0); close(sp[1]);
        dup2(0, 1);
        relay_child(net_fd);
    }
    close(sp[1]);
    int use_fd = sp[0];
    if (argc < 3 || argv[2][0] != 'd') { dup2(sp[0], net_fd); close(sp[0]); use_fd = net_fd; }
    const char *req = "GET /h.txt HTTP/1.0\r\n\r\n";
    if (write(use_fd, req, strlen(req)) < 0) { report("relay-write", strerror(errno)); return 1; }
    char buf[1024]; size_t have = 0;
    for (;;) {
        ssize_t n = read(use_fd, buf + have, sizeof buf - 1 - have);
        if (n < 0) { char m[64]; snprintf(m, sizeof m, "read errno %d after %zu bytes", errno, have); report("relay-read", m); return 1; }
        if (n == 0) break;
        have += n;
    }
    buf[have] = 0;
    char *body = strstr(buf, "\r\n\r\n");
    report("relay", body ? strtok(body + 4, "\r\n") : "nobody");
    int st; waitpid(pid, &st, 0);
    return 0;
}
