#define TNAME "sysall"
#include "t.h"
#include <signal.h>
#include <stdlib.h>
#include <sys/syscall.h>
#include <sys/wait.h>
#include "sysall_table.h"

#define ENOSYS_EXIT 77
#define PROBE_SECONDS 3
#define TOTAL_SECONDS 900

int main(void)
{
    alarm(TOTAL_SECONDS);
    size_t i;
    for (i = 0; i < sizeof sysents / sizeof sysents[0]; i++) {
        char name[48];
        snprintf(name, sizeof name, "nr%03ld_%s", sysents[i].nr, sysents[i].name);
        if (sysents[i].skip)
            continue;
        pid_t pid = fork();
        if (pid == 0) {
            alarm(PROBE_SECONDS);
            errno = 0;
            long r = syscall(sysents[i].nr, -1L, 0L, 0L, 0L, 0L, 0L);
            _exit(r == -1 && errno == ENOSYS ? ENOSYS_EXIT : 0);
        }
        int status = 0;
        if (pid < 0 || waitpid(pid, &status, 0) != pid)
            FAIL(name, "fork or wait failed");
        else if (WIFEXITED(status) && WEXITSTATUS(status) == ENOSYS_EXIT)
            GAP(name, "nr=%ld", sysents[i].nr);
        else if (WIFEXITED(status) || (WIFSIGNALED(status) && WTERMSIG(status) == SIGALRM))
            PASS(name);
        else
            FAIL(name, "nr=%ld killed by signal %d", sysents[i].nr, WTERMSIG(status));
    }
    return 0;
}
