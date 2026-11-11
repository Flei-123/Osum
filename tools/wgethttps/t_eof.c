#include <errno.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/socket.h>
#include <sys/wait.h>
#include <netinet/in.h>
#include <arpa/inet.h>
#include <unistd.h>

static int connect_tcp(int port)
{
    int fd = socket(AF_INET, SOCK_STREAM, 0);
    struct sockaddr_in sa = { .sin_family = AF_INET, .sin_port = htons(port) };
    inet_pton(AF_INET, "10.0.2.2", &sa.sin_addr);
    if (fd < 0 || connect(fd, (struct sockaddr *)&sa, sizeof sa) != 0) return -1;
    return fd;
}

static void drain(const char *name, int fd, pid_t pid)
{
    char buf[64], m[96];
    size_t have = 0;
    ssize_t n;
    while ((n = read(fd, buf, sizeof buf)) > 0) have += n;
    snprintf(m, sizeof m, n == 0 ? "eof after %zu bytes" : "errno %d after %zu bytes", n == 0 ? (int)have : errno, have);
    if (n < 0) snprintf(m, sizeof m, "errno %d after %zu bytes", errno, have);
    printf("WT %s %s\n", name, m);
    fflush(stdout);
    waitpid(pid, NULL, 0);
}

static void variant(const char *name, int duplicate, int hold_tcp, int port)
{
    int sp[2];
    int net_fd = hold_tcp ? connect_tcp(port) : -1;
    if (socketpair(AF_UNIX, SOCK_STREAM, 0, sp) != 0) { printf("WT %s socketpair-failed\n", name); return; }
    pid_t pid = fork();
    if (pid == 0) {
        close(sp[0]);
        int out = sp[1];
        if (duplicate) { dup2(sp[1], 0); close(sp[1]); dup2(0, 1); out = 1; }
        if (write(out, "hello", 5) != 5) _exit(2);
        _exit(0);
    }
    close(sp[1]);
    if (net_fd >= 0) close(net_fd);
    drain(name, sp[0], pid);
}

int main(int argc, char **argv)
{
    int port = atoi(argv[1]);
    variant("eof-plain", 0, 0, port);
    variant("eof-dup", 1, 0, port);
    variant("eof-tcp", 0, 1, port);
    variant("eof-dup-tcp", 1, 1, port);
    return 0;
}
