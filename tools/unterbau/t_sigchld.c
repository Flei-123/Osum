#define TNAME "sigchld"
#include "t.h"
#include <signal.h>
#include <sys/wait.h>

#define CHILD_STATUS 7

static volatile sig_atomic_t seen;
static volatile pid_t info_pid;
static volatile int info_status;
static volatile int info_code;
static volatile int info_signo;
static volatile uid_t info_uid;

static void on_chld(int sig, siginfo_t *si, void *ctx)
{
    (void)ctx;
    info_signo = sig;
    info_pid = si->si_pid;
    info_uid = si->si_uid;
    info_status = si->si_status;
    info_code = si->si_code;
    seen = 1;
}

int main(void)
{
    struct sigaction sa;
    memset(&sa, 0, sizeof sa);
    sa.sa_sigaction = on_chld;
    sa.sa_flags = SA_SIGINFO;
    sigemptyset(&sa.sa_mask);
    CHECK("sigaction_installed", sigaction(SIGCHLD, &sa, 0) == 0, "errno=%d", errno);
    pid_t kid = fork();
    if (kid == 0) _exit(CHILD_STATUS);
    for (int i = 0; i < 2000 && !seen; i++) usleep(1000);
    CHECK("sigchld_delivered", seen, "seen=%d", (int)seen);
    CHECK("sigchld_si_signo", info_signo == SIGCHLD, "signo=%d", info_signo);
    CHECK("sigchld_si_pid", info_pid == kid, "si_pid=%d kid=%d", (int)info_pid, (int)kid);
    CHECK("sigchld_si_uid", info_uid == getuid(), "si_uid=%d uid=%d", (int)info_uid, (int)getuid());
    CHECK("sigchld_si_status", info_status == CHILD_STATUS, "si_status=%d", info_status);
    CHECK("sigchld_si_code", info_code == CLD_EXITED, "si_code=%d", info_code);
    int status = 0;
    CHECK("sigchld_wait_after", waitpid(kid, &status, 0) == kid && WIFEXITED(status) && WEXITSTATUS(status) == CHILD_STATUS, "status=%d errno=%d", status, errno);
    return 0;
}
