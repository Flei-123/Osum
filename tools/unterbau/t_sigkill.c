#define TNAME "sigkill"
#include "t.h"
#include <fcntl.h>
#include <signal.h>
#include <sys/syscall.h>
#include <sys/wait.h>

typedef void (*child_fn)(void);

static void child_pause(void)
{
    alarm(1);
    pause();
}

static void child_nanosleep(void)
{
    alarm(1);
    struct timespec ts = {30, 0};
    nanosleep(&ts, 0);
}

static void child_pipe_read(void)
{
    int fds[2];
    char c;
    if (pipe(fds) != 0)
        _exit(2);
    alarm(1);
    (void)!read(fds[0], &c, 1);
}

static void child_pause_garbage_args(void)
{
    alarm(1);
    syscall(SYS_pause, -1L, 0L, 0L, 0L, 0L, 0L);
}

static void child_pause_after_tid(void)
{
    static int tid_word;
    syscall(SYS_set_tid_address, &tid_word);
    alarm(1);
    pause();
}

static void check_killed_by_alarm(const char *name, child_fn fn)
{
    pid_t pid = fork();
    if (pid == 0) {
        fn();
        _exit(0);
    }
    int status = 0;
    if (pid < 0 || waitpid(pid, &status, 0) != pid)
        FAIL(name, "fork or wait failed");
    else
        CHECK(name, WIFSIGNALED(status) && WTERMSIG(status) == SIGALRM, "status=0x%x exit=%d", status, WEXITSTATUS(status));
}

int main(void)
{
    alarm(300);
    check_killed_by_alarm("pause", child_pause);
    check_killed_by_alarm("pause_garbage_args", child_pause_garbage_args);
    check_killed_by_alarm("nanosleep", child_nanosleep);
    check_killed_by_alarm("pipe_read", child_pipe_read);
    check_killed_by_alarm("pause_after_tid", child_pause_after_tid);
    return 0;
}
