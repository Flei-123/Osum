#define TNAME "sarestart"
#include "t.h"
#include <signal.h>
#include <stdlib.h>
#include <sys/socket.h>
#include <sys/wait.h>

#define ALARM_US 300000
#define WRITER_DELAY_S 1

static volatile int handler_runs;

static void on_alarm(int sig)
{
    (void)sig;
    handler_runs++;
}

static void install(int flags)
{
    struct sigaction sa;
    memset(&sa, 0, sizeof sa);
    sa.sa_handler = on_alarm;
    sa.sa_flags = flags;
    sigaction(SIGALRM, &sa, 0);
    handler_runs = 0;
}

static pid_t delayed_writer(int fd, int closefd)
{
    pid_t pid = fork();
    if (pid == 0) {
        close(closefd);
        sleep(WRITER_DELAY_S);
        (void)!write(fd, "r", 1);
        _exit(0);
    }
    return pid;
}

static void pipe_read_case(const char *name, int flags, int expect_restart)
{
    int fds[2];
    char got = 0;
    char label[64];
    pipe(fds);
    pid_t pid = delayed_writer(fds[1], fds[0]);
    close(fds[1]);
    install(flags);
    ualarm(ALARM_US, 0);
    errno = 0;
    ssize_t n = read(fds[0], &got, 1);
    int err = errno;
    snprintf(label, sizeof label, "%s_read_result", name);
    if (expect_restart)
        CHECK(label, n == 1 && got == 'r', "n=%zd errno=%d", n, err);
    else
        CHECK(label, n == -1 && err == EINTR, "n=%zd errno=%d", n, err);
    snprintf(label, sizeof label, "%s_handler_ran", name);
    CHECK(label, handler_runs == 1, "runs=%d", handler_runs);
    waitpid(pid, 0, 0);
    close(fds[0]);
}

static void socket_recv_case(void)
{
    int sv[2];
    char got = 0;
    socketpair(AF_UNIX, SOCK_STREAM, 0, sv);
    pid_t pid = delayed_writer(sv[1], sv[0]);
    close(sv[1]);
    install(SA_RESTART);
    ualarm(ALARM_US, 0);
    errno = 0;
    ssize_t n = recv(sv[0], &got, 1, 0);
    CHECK("restart_recv_result", n == 1 && got == 'r', "n=%zd errno=%d", n, errno);
    CHECK("restart_recv_handler_ran", handler_runs == 1, "runs=%d", handler_runs);
    waitpid(pid, 0, 0);
    close(sv[0]);
}

static void wait4_case(void)
{
    install(SA_RESTART);
    pid_t pid = fork();
    if (pid == 0) {
        sleep(WRITER_DELAY_S);
        _exit(7);
    }
    ualarm(ALARM_US, 0);
    int status = 0;
    errno = 0;
    pid_t r = waitpid(pid, &status, 0);
    CHECK("restart_waitpid_result", r == pid && WIFEXITED(status) && WEXITSTATUS(status) == 7, "r=%d errno=%d", (int)r, errno);
    CHECK("restart_waitpid_handler_ran", handler_runs == 1, "runs=%d", handler_runs);
}

static void ignored_signal_case(void)
{
    int fds[2];
    char got = 0;
    pipe(fds);
    signal(SIGCHLD, SIG_DFL);
    pid_t quick = fork();
    if (quick == 0)
        _exit(0);
    pid_t pid = delayed_writer(fds[1], fds[0]);
    close(fds[1]);
    errno = 0;
    ssize_t n = read(fds[0], &got, 1);
    CHECK("default_ignored_signal_restarts_read", n == 1 && got == 'r', "n=%zd errno=%d", n, errno);
    waitpid(quick, 0, 0);
    waitpid(pid, 0, 0);
    close(fds[0]);
}

int main(void)
{
    alarm(60);
    pipe_read_case("norestart", 0, 0);
    pipe_read_case("restart", SA_RESTART, 1);
    socket_recv_case();
    wait4_case();
    ignored_signal_case();
    return 0;
}
