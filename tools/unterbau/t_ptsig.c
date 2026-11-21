#define TNAME "ptsig"
#include "t.h"
#include <signal.h>
#include <stdio.h>
#include <sys/ptrace.h>
#include <sys/syscall.h>
#include <sys/user.h>
#include <sys/wait.h>

#ifndef PTRACE_GET_SYSCALL_INFO
#define PTRACE_GET_SYSCALL_INFO 0x420e
#endif
#ifndef PTRACE_SEIZE
#define PTRACE_SEIZE 0x4206
#define PTRACE_INTERRUPT 0x4207
#endif
#ifndef PTRACE_O_TRACESYSGOOD
#define PTRACE_O_TRACESYSGOOD 1
#endif

#define OP_ENTRY 1
#define OP_EXIT 2
#define MAX_STOPS 80
#define TRACE_CHARS 600
#define ERR_NOSYS_RAW ((unsigned long long)-38LL)

struct sysinfo_blob {
    unsigned char op;
    unsigned char pad[3];
    unsigned int arch;
    unsigned long long ip;
    unsigned long long sp;
    unsigned long long a;
    unsigned long long b[6];
};

struct stop_log {
    char text[TRACE_CHARS];
    int len;
    int doubled;
    int nosys_exit;
    int stops;
    int last_op;
    int sigreturn_exits;
};

static void on_chld(int sig)
{
    (void)sig;
}

static void tracee_body(void)
{
    struct sigaction sa;
    memset(&sa, 0, sizeof sa);
    sa.sa_handler = on_chld;
    sigaction(SIGCHLD, &sa, 0);
    pid_t child = fork();
    if (child == 0) {
        usleep(300000);
        _exit(0);
    }
    int st;
    wait4(-1, &st, 0, 0);
    wait4(-1, &st, WNOHANG, 0);
    _exit(7);
}

static void note(struct stop_log *log, const char *fmt, long a, long long b)
{
    if (log->len < TRACE_CHARS - 40)
        log->len += snprintf(log->text + log->len, TRACE_CHARS - log->len, fmt, a, b);
}

static void record_syscall_stop(pid_t pid, struct stop_log *log)
{
    struct sysinfo_blob blob;
    memset(&blob, 0, sizeof blob);
    if (ptrace(PTRACE_GET_SYSCALL_INFO, pid, sizeof blob, &blob) < 0)
        return;
    if (blob.op == OP_ENTRY) {
        if (log->last_op == OP_ENTRY) log->doubled++;
        note(log, "E%ld ", (long)blob.a, 0);
    } else if (blob.op == OP_EXIT) {
        if (log->last_op == OP_EXIT) log->doubled++;
        if (blob.a == ERR_NOSYS_RAW) log->nosys_exit++;
        note(log, "X=%ld ", (long)blob.a, 0);
    }
    log->last_op = blob.op;
}

static void drive(pid_t pid, struct stop_log *log, int resume_first)
{
    int st = 0;
    int inject = 0;
    long req = resume_first ? PTRACE_SYSCALL : PTRACE_SYSCALL;
    for (int i = 0; i < MAX_STOPS; i++) {
        if (ptrace(req, pid, 0, inject) != 0) break;
        inject = 0;
        if (waitpid(pid, &st, 0) != pid) break;
        if (WIFEXITED(st) || WIFSIGNALED(st)) {
            note(log, "EXIT%ld ", WIFEXITED(st) ? WEXITSTATUS(st) : -1, 0);
            return;
        }
        log->stops++;
        int sig = WSTOPSIG(st);
        if (sig == (SIGTRAP | 0x80)) {
            record_syscall_stop(pid, log);
        } else if ((st >> 16) != 0) {
            note(log, "EV%ld ", (long)(st >> 16), 0);
        } else {
            note(log, "S%ld ", (long)sig, 0);
            inject = sig == SIGSTOP ? 0 : sig;
        }
    }
}

static void check_traceme_signal(void)
{
    struct stop_log log;
    memset(&log, 0, sizeof log);
    pid_t pid = fork();
    if (pid == 0) {
        ptrace(PTRACE_TRACEME, 0, 0, 0);
        raise(SIGSTOP);
        tracee_body();
    }
    int st;
    waitpid(pid, &st, 0);
    ptrace(PTRACE_SETOPTIONS, pid, 0, PTRACE_O_TRACESYSGOOD);
    drive(pid, &log, 1);
    printf("PTSIG traceme: %s\n", log.text);
    CHECK("traceme_sigreturn_exit_stop", strstr(log.text, "E15 X=") != 0, "trace %s", log.text);
    CHECK("traceme_no_doubled_stops", log.doubled == 0, "doubled %d trace %s", log.doubled, log.text);
    CHECK("traceme_no_enosys_exit", log.nosys_exit == 0, "nosys %d trace %s", log.nosys_exit, log.text);
    kill(pid, SIGKILL);
    waitpid(pid, &st, 0);
}

static void check_seize_midcall(void)
{
    struct stop_log log;
    memset(&log, 0, sizeof log);
    pid_t pid = fork();
    if (pid == 0)
        tracee_body();
    usleep(100000);
    int st;
    long opts = PTRACE_O_TRACESYSGOOD;
    long r = ptrace(PTRACE_SEIZE, pid, 0, opts);
    CHECK("seize_ok", r == 0, "r %ld errno %d", r, errno);
    ptrace(PTRACE_INTERRUPT, pid, 0, 0);
    waitpid(pid, &st, 0);
    drive(pid, &log, 1);
    printf("PTSIG seize: %s\n", log.text);
    CHECK("seize_no_doubled_stops", log.doubled == 0, "doubled %d trace %s", log.doubled, log.text);
    CHECK("seize_no_enosys_exit", log.nosys_exit == 0, "nosys %d trace %s", log.nosys_exit, log.text);
    kill(pid, SIGKILL);
    waitpid(pid, &st, 0);
}

int main(void)
{
    alarm(40);
    check_traceme_signal();
    check_seize_midcall();
    return 0;
}
