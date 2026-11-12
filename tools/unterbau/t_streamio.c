#define TNAME "streamio"
#include "t.h"
#include <signal.h>
#include <stdlib.h>
#include <sys/socket.h>
#include <sys/wait.h>

#define BIG_BYTES (256 * 1024)
#define CHUNK_BYTES 4096
#define LONG_WAIT_SECONDS 35

static char payload[BIG_BYTES];
static char sink[CHUNK_BYTES];

static int drain_all(int fd)
{
    long total = 0;
    ssize_t n;
    while ((n = read(fd, sink, sizeof sink)) > 0)
        total += n;
    return total == BIG_BYTES ? 0 : 1;
}

static void big_write(const char *name, int fds[2])
{
    pid_t pid = fork();
    if (pid == 0) {
        close(fds[1]);
        _exit(drain_all(fds[0]));
    }
    close(fds[0]);
    memset(payload, 'p', sizeof payload);
    errno = 0;
    ssize_t n = write(fds[1], payload, sizeof payload);
    char label[64];
    snprintf(label, sizeof label, "%s_single_write_complete", name);
    CHECK(label, n == (ssize_t)sizeof payload, "n=%zd errno=%d", n, errno);
    close(fds[1]);
    int status = 0;
    waitpid(pid, &status, 0);
    snprintf(label, sizeof label, "%s_reader_got_every_byte", name);
    CHECK(label, WIFEXITED(status) && WEXITSTATUS(status) == 0, "status=0x%x", status);
}

static void long_recv_wait(void)
{
    int sv[2];
    char c = 'z';
    char got = 0;
    CHECK("socketpair_wait", socketpair(AF_UNIX, SOCK_STREAM, 0, sv) == 0, "errno=%d", errno);
    pid_t pid = fork();
    if (pid == 0) {
        close(sv[0]);
        sleep(LONG_WAIT_SECONDS);
        (void)!write(sv[1], &c, 1);
        _exit(0);
    }
    close(sv[1]);
    errno = 0;
    ssize_t n = recv(sv[0], &got, 1, 0);
    CHECK("recv_waits_past_30s", n == 1 && got == 'z', "n=%zd errno=%d", n, errno);
    waitpid(pid, 0, 0);
    close(sv[0]);
}

int main(void)
{
    alarm(120);
    int fds[2];
    CHECK("pipe", pipe(fds) == 0, "errno=%d", errno);
    big_write("pipe", fds);
    CHECK("socketpair", socketpair(AF_UNIX, SOCK_STREAM, 0, fds) == 0, "errno=%d", errno);
    big_write("socketpair", fds);
    long_recv_wait();
    return 0;
}
