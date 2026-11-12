#define TNAME "ptrace"
#include "t.h"
#include <signal.h>
#include <stdlib.h>
#include <sys/ptrace.h>
#include <sys/syscall.h>
#include <sys/user.h>
#include <sys/wait.h>

static volatile long shared_word = 0x1234;

static pid_t spawn_traced(void (*body)(void))
{
    pid_t pid = fork();
    if (pid == 0) {
        if (ptrace(PTRACE_TRACEME, 0, 0, 0) != 0)
            _exit(90);
        raise(SIGSTOP);
        body();
        _exit(7);
    }
    return pid;
}

static void body_getpid(void)
{
    syscall(SYS_getpid);
    syscall(SYS_getppid);
}

static void body_spin(void)
{
    for (;;)
        pause();
}

static void body_step(void)
{
    volatile int x = 0;
    for (int i = 0; i < 4; i++)
        x += i;
}

static void body_peek(void)
{
    shared_word = shared_word + 1;
}

static void check_traceme_stop(void)
{
    int st = 0;
    pid_t pid = spawn_traced(body_getpid);
    pid_t got = waitpid(pid, &st, 0);
    CHECK("sigstop_reported", got == pid && WIFSTOPPED(st) && WSTOPSIG(st) == SIGSTOP, "got %d st %x", (int)got, st);
    errno = 0;
    CHECKC("cont", ptrace(PTRACE_CONT, pid, 0, 0) == 0);
    got = waitpid(pid, &st, 0);
    CHECK("exit_status", got == pid && WIFEXITED(st) && WEXITSTATUS(st) == 7, "st %x", st);
}

static void check_syscall_loop(void)
{
    int st = 0, enters = 0, exits = 0, saw_getpid = 0, saw_getppid = 0, inside = 0;
    pid_t pid = spawn_traced(body_getpid);
    waitpid(pid, &st, 0);
    for (int guard = 0; guard < 200; guard++) {
        errno = 0;
        if (ptrace(PTRACE_SYSCALL, pid, 0, 0) != 0)
            break;
        if (waitpid(pid, &st, 0) != pid || !WIFSTOPPED(st))
            break;
        struct user_regs_struct regs;
        errno = 0;
        if (ptrace(PTRACE_GETREGS, pid, 0, &regs) != 0)
            break;
        if (!inside) {
            enters++;
            if ((long)regs.orig_rax == SYS_getpid)
                saw_getpid = 1;
            if ((long)regs.orig_rax == SYS_getppid)
                saw_getppid = 1;
        } else {
            exits++;
        }
        inside = !inside;
    }
    CHECK("syscall_stops", enters > 0 && exits > 0 && enters - exits <= 1, "enters %d exits %d", enters, exits);
    CHECK("orig_rax_getpid", saw_getpid, "not seen");
    CHECK("orig_rax_getppid", saw_getppid, "not seen");
    kill(pid, SIGKILL);
    waitpid(pid, &st, 0);
}

static void check_peek_poke(void)
{
    int st = 0;
    pid_t pid = spawn_traced(body_peek);
    waitpid(pid, &st, 0);
    errno = 0;
    long v = ptrace(PTRACE_PEEKDATA, pid, (void *)&shared_word, 0);
    CHECK("peekdata", errno == 0 && v == 0x1234, "v %lx errno %d", v, errno);
    errno = 0;
    long r = ptrace(PTRACE_POKEDATA, pid, (void *)&shared_word, (void *)0x4321);
    CHECKC("pokedata", r == 0);
    errno = 0;
    v = ptrace(PTRACE_PEEKDATA, pid, (void *)&shared_word, 0);
    CHECK("peek_after_poke", errno == 0 && v == 0x4321, "v %lx", v);
    CHECK("poke_not_visible_in_tracer", shared_word == 0x1234, "tracer saw %lx", (long)shared_word);
    ptrace(PTRACE_CONT, pid, 0, 0);
    waitpid(pid, &st, 0);
    CHECK("peek_poke_child_exit", WIFEXITED(st) && WEXITSTATUS(st) == 7, "st %x", st);
}

static void check_singlestep(void)
{
    int st = 0, steps = 0;
    pid_t pid = spawn_traced(body_step);
    waitpid(pid, &st, 0);
    for (int guard = 0; guard < 400; guard++) {
        errno = 0;
        if (ptrace(PTRACE_SINGLESTEP, pid, 0, 0) != 0)
            break;
        if (waitpid(pid, &st, 0) != pid)
            break;
        if (!WIFSTOPPED(st))
            break;
        if (WSTOPSIG(st) == SIGTRAP)
            steps++;
        if (steps >= 5)
            break;
    }
    CHECK("singlestep_traps", steps >= 5, "steps %d", steps);
    kill(pid, SIGKILL);
    waitpid(pid, &st, 0);
}

static void check_kill(void)
{
    int st = 0;
    pid_t pid = spawn_traced(body_spin);
    waitpid(pid, &st, 0);
    errno = 0;
    CHECKC("kill_request", ptrace(PTRACE_KILL, pid, 0, 0) == 0);
    pid_t got = waitpid(pid, &st, 0);
    CHECK("kill_reaped", got == pid && WIFSIGNALED(st) && WTERMSIG(st) == SIGKILL, "got %d st %x", (int)got, st);
}

static void check_regs_rip(void)
{
    int st = 0;
    pid_t pid = spawn_traced(body_getpid);
    waitpid(pid, &st, 0);
    struct user_regs_struct regs;
    errno = 0;
    int r = ptrace(PTRACE_GETREGS, pid, 0, &regs);
    CHECKC("getregs", r == 0);
    CHECK("regs_rip_rsp", r == 0 && regs.rip != 0 && regs.rsp != 0, "rip %llx rsp %llx", regs.rip, regs.rsp);
    errno = 0;
    CHECK("ptrace_bad_pid", ptrace(PTRACE_CONT, 999999, 0, 0) == -1 && errno == ESRCH, "errno %d", errno);
    kill(pid, SIGKILL);
    waitpid(pid, &st, 0);
}

int main(void)
{
    alarm(60);
    check_traceme_stop();
    check_syscall_loop();
    check_peek_poke();
    check_singlestep();
    check_kill();
    check_regs_rip();
    return 0;
}
