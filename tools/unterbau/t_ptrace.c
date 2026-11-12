#define TNAME "ptrace"
#include "t.h"
#include <elf.h>
#include <signal.h>
#include <sys/uio.h>
#include <ucontext.h>
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

static volatile int chld_count;
static volatile long handler_rbx;

static void on_chld(int sig)
{
    (void)sig;
    chld_count++;
}

static void on_usr1(int sig, siginfo_t *info, void *ctx)
{
    (void)sig;
    (void)info;
    handler_rbx = ((ucontext_t *)ctx)->uc_mcontext.gregs[REG_RBX];
}

static void body_ignored(void)
{
    signal(SIGUSR1, SIG_IGN);
    raise(SIGUSR1);
}

static void body_handler(void)
{
    struct sigaction sa;
    memset(&sa, 0, sizeof sa);
    sa.sa_sigaction = on_usr1;
    sa.sa_flags = SA_SIGINFO;
    sigaction(SIGUSR1, &sa, 0);
    raise(SIGUSR1);
    _exit(handler_rbx == 0x5a5a ? 7 : 8);
}

static __attribute__((noinline)) int text_marker(void)
{
    return 1;
}

static void body_text_marker(void)
{
    _exit(text_marker() == 2 ? 7 : 8);
}

static void check_sigchld(void)
{
    struct sigaction sa;
    memset(&sa, 0, sizeof sa);
    sa.sa_handler = on_chld;
    sigaction(SIGCHLD, &sa, 0);
    chld_count = 0;
    int st = 0;
    pid_t pid = spawn_traced(body_getpid);
    waitpid(pid, &st, 0);
    CHECK("sigchld_to_tracer", chld_count >= 1, "count %d", chld_count);
    signal(SIGCHLD, SIG_DFL);
    kill(pid, SIGKILL);
    waitpid(pid, &st, 0);
}

static void check_ignored_signal(void)
{
    int st = 0;
    pid_t pid = spawn_traced(body_ignored);
    waitpid(pid, &st, 0);
    ptrace(PTRACE_CONT, pid, 0, 0);
    pid_t got = waitpid(pid, &st, 0);
    CHECK("ignored_signal_reported", got == pid && WIFSTOPPED(st) && WSTOPSIG(st) == SIGUSR1, "got %d st %x", (int)got, st);
    ptrace(PTRACE_CONT, pid, 0, 0);
    waitpid(pid, &st, 0);
    CHECK("ignored_signal_exit", WIFEXITED(st) && WEXITSTATUS(st) == 7, "st %x", st);
}

static void check_regset(void)
{
    int st = 0;
    pid_t pid = spawn_traced(body_getpid);
    waitpid(pid, &st, 0);
    struct user_regs_struct regs, set;
    struct iovec iov = { &set, sizeof set };
    ptrace(PTRACE_GETREGS, pid, 0, &regs);
    errno = 0;
    long r = ptrace(PTRACE_GETREGSET, pid, (void *)NT_PRSTATUS, &iov);
    CHECKC("getregset", r == 0 && iov.iov_len == sizeof set && set.rip == regs.rip && set.rsp == regs.rsp);
    set.rbx = 0x77;
    errno = 0;
    r = ptrace(PTRACE_SETREGSET, pid, (void *)NT_PRSTATUS, &iov);
    ptrace(PTRACE_GETREGS, pid, 0, &regs);
    CHECKC("setregset", r == 0 && regs.rbx == 0x77);
    kill(pid, SIGKILL);
    waitpid(pid, &st, 0);
}

static void check_setregs_in_signal_stop(void)
{
    int st = 0;
    pid_t pid = spawn_traced(body_handler);
    waitpid(pid, &st, 0);
    ptrace(PTRACE_CONT, pid, 0, 0);
    waitpid(pid, &st, 0);
    struct user_regs_struct regs;
    int stopped = WIFSTOPPED(st) && WSTOPSIG(st) == SIGUSR1;
    if (stopped) {
        ptrace(PTRACE_GETREGS, pid, 0, &regs);
        regs.rbx = 0x5a5a;
        ptrace(PTRACE_SETREGS, pid, 0, &regs);
        ptrace(PTRACE_CONT, pid, 0, (void *)(long)SIGUSR1);
        waitpid(pid, &st, 0);
    }
    CHECK("setregs_in_signal_stop", stopped && WIFEXITED(st) && WEXITSTATUS(st) == 7, "stopped %d st %x", stopped, st);
}

static void check_interrupt(void)
{
    int st = 0;
    pid_t pid = fork();
    if (pid == 0)
        for (;;)
            pause();
    errno = 0;
    long r = ptrace(PTRACE_SEIZE, pid, 0, 0);
    CHECKC("seize", r == 0);
    errno = 0;
    r = ptrace(PTRACE_INTERRUPT, pid, 0, 0);
    pid_t got = waitpid(pid, &st, __WALL);
    CHECK("interrupt_event_stop", r == 0 && got == pid && WIFSTOPPED(st) && (st >> 16) == PTRACE_EVENT_STOP, "r %ld got %d st %x", r, (int)got, st);
    errno = 0;
    CHECKC("listen", ptrace(PTRACE_LISTEN, pid, 0, 0) == 0);
    kill(pid, SIGKILL);
    waitpid(pid, &st, __WALL);
}

static void check_exit_report_nonparent(void)
{
    int go[2], ready[2], st = 0;
    if (pipe(go) != 0 || pipe(ready) != 0)
        return;
    pid_t target = fork();
    if (target == 0) {
        char c;
        (void)!read(go[0], &c, 1);
        _exit(7);
    }
    pid_t tracer = fork();
    if (tracer == 0) {
        int tst = 0;
        if (ptrace(PTRACE_SEIZE, target, 0, 0) != 0)
            _exit(90);
        (void)!write(ready[1], "r", 1);
        pid_t got = waitpid(target, &tst, __WALL);
        _exit(got == target && WIFEXITED(tst) && WEXITSTATUS(tst) == 7 ? 0 : 91);
    }
    char c;
    (void)!read(ready[0], &c, 1);
    (void)!write(go[1], "g", 1);
    waitpid(tracer, &st, 0);
    CHECK("exit_report_nonparent", WIFEXITED(st) && WEXITSTATUS(st) == 0, "tracer st %x", st);
    waitpid(target, &st, 0);
}

static void check_poke_text_private(void)
{
    int st = 0;
    pid_t pid = spawn_traced(body_text_marker);
    waitpid(pid, &st, 0);
    unsigned char patch[8] = { 0xb8, 0x02, 0x00, 0x00, 0x00, 0xc3, 0x90, 0x90 };
    errno = 0;
    long orig = ptrace(PTRACE_PEEKTEXT, pid, (void *)text_marker, 0);
    long keep = orig;
    memcpy(((char *)&keep), patch, 6);
    long r = ptrace(PTRACE_POKETEXT, pid, (void *)text_marker, (void *)keep);
    CHECKC("poketext", r == 0);
    CHECK("poketext_not_visible_in_tracer", text_marker() == 1, "tracer saw %d", text_marker());
    ptrace(PTRACE_CONT, pid, 0, 0);
    waitpid(pid, &st, 0);
    CHECK("poketext_visible_in_tracee", WIFEXITED(st) && WEXITSTATUS(st) == 7, "st %x", st);
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
    check_sigchld();
    check_ignored_signal();
    check_regset();
    check_setregs_in_signal_stop();
    check_interrupt();
    check_exit_report_nonparent();
    check_poke_text_private();
    return 0;
}
