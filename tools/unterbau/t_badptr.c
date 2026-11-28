#define TNAME "badptr"
#include "t.h"
#include <signal.h>
#include <stdlib.h>
#include <sys/syscall.h>
#include <sys/wait.h>
#include "sysall_table.h"

#define PROBE_SECONDS 1
#define TOTAL_SECONDS 900
#define TOP_PAGE_LAST_WORD 0xFFFFFFFFFFFFFFFCUL

static int probe(unsigned long arg)
{
    size_t i;
    int reaped = 0;
    for (i = 0; i < sizeof sysents / sizeof sysents[0]; i++) {
        if (sysents[i].skip)
            continue;
        pid_t pid = fork();
        if (pid == 0) {
            alarm(PROBE_SECONDS);
            syscall(sysents[i].nr, arg, arg, arg, arg, arg, arg);
            _exit(0);
        }
        int status = 0;
        if (pid > 0 && waitpid(pid, &status, 0) == pid)
            reaped++;
    }
    return reaped;
}

int main(void)
{
    alarm(TOTAL_SECONDS);
    CHECK("minus_one", probe(~0UL) > 300, "too few children reaped");
    CHECK("top_page_last_word", probe(TOP_PAGE_LAST_WORD) > 300, "too few children reaped");
    CHECK("top_page_start", probe(0xFFFFFFFFFFFFF000UL) > 300, "too few children reaped");
    return 0;
}
