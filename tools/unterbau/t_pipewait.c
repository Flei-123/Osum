#define TNAME "pipewait"
#include "t.h"
#include <fcntl.h>
#include <signal.h>
#include <stdlib.h>
#include <sys/wait.h>

#define SLOW_SECONDS 6
#define BULK_BYTES (256 * 1024)
#define CHUNK_BYTES 4096
#define INTERRUPT_MS 300000

static void on_alarm(int sig)
{
    (void)sig;
}

static void slow_writer(void)
{
    int fds[2];
    char c = 'x';
    char got = 0;
    CHECK("pipe", pipe(fds) == 0, "errno=%d", errno);
    pid_t pid = fork();
    if (pid == 0) {
        close(fds[0]);
        sleep(SLOW_SECONDS);
        (void)!write(fds[1], &c, 1);
        _exit(0);
    }
    close(fds[1]);
    errno = 0;
    ssize_t n = read(fds[0], &got, 1);
    CHECK("read_waits_for_slow_writer", n == 1 && got == 'x', "n=%zd errno=%d", n, errno);
    n = read(fds[0], &got, 1);
    CHECK("read_eof_after_writer_exit", n == 0, "n=%zd errno=%d", n, errno);
    waitpid(pid, 0, 0);
    close(fds[0]);
}

static void slow_reader(void)
{
    int fds[2];
    static char data[BULK_BYTES];
    static char sink[CHUNK_BYTES];
    CHECK("pipe2", pipe(fds) == 0, "errno=%d", errno);
    pid_t pid = fork();
    if (pid == 0) {
        close(fds[1]);
        sleep(SLOW_SECONDS);
        long total = 0;
        ssize_t n;
        while ((n = read(fds[0], sink, sizeof sink)) > 0)
            total += n;
        _exit(total == BULK_BYTES ? 0 : 1);
    }
    close(fds[0]);
    memset(data, 'd', sizeof data);
    errno = 0;
    size_t off = 0;
    ssize_t n = 0;
    while (off < sizeof data && (n = write(fds[1], data + off, sizeof data - off)) > 0)
        off += (size_t)n;
    CHECK("write_waits_for_slow_reader", off == sizeof data, "off=%zu n=%zd errno=%d", off, n, errno);
    close(fds[1]);
    int status = 0;
    waitpid(pid, &status, 0);
    CHECK("reader_got_every_byte", WIFEXITED(status) && WEXITSTATUS(status) == 0, "status=0x%x", status);
}

static void interrupted_read(void)
{
    int fds[2];
    char got;
    struct sigaction sa;
    CHECK("pipe3", pipe(fds) == 0, "errno=%d", errno);
    memset(&sa, 0, sizeof sa);
    sa.sa_handler = on_alarm;
    sigaction(SIGALRM, &sa, 0);
    ualarm(INTERRUPT_MS, 0);
    errno = 0;
    ssize_t n = read(fds[0], &got, 1);
    CHECK("read_interrupted_by_signal", n == -1 && errno == EINTR, "n=%zd errno=%d", n, errno);
    close(fds[0]);
    close(fds[1]);
}

int main(void)
{
    alarm(90);
    slow_writer();
    slow_reader();
    interrupted_read();
    return 0;
}
