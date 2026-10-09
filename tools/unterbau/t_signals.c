/* signals: handlers, masks, SIGCHLD, SIGSEGV with siginfo, sigaltstack, timers, signals to threads. */
#define TNAME "signals"
#include "t.h"
#include <pthread.h>
#include <setjmp.h>
#include <signal.h>
#include <stdlib.h>
#include <sys/syscall.h>
#include <sys/time.h>
#include <sys/wait.h>
#include <time.h>

static volatile int got, got_info_code, got_on_alt;
static volatile void *got_addr;
static sigjmp_buf jb;
static char altstk[64 * 1024];
static void h1(int s) { got = s; }
static void h_info(int s, siginfo_t *si, void *u) { (void)u; got = s; got_info_code = si->si_code; got_addr = si->si_addr; }
static struct sigaction g_jump;
static volatile int have_info;
static void h_jump(int s, siginfo_t *si, void *u) { (void)u; got = s; have_info = si != 0; if (si) { got_addr = si->si_addr; got_info_code = si->si_code; } sigaction(s, &g_jump, 0); siglongjmp(jb, 1); }
static void h_alt(int s) { char probe; got = s; got_on_alt = (&probe >= altstk && &probe < altstk + sizeof altstk); }
static volatile int chld;
static void h_chld(int s) { (void)s; chld++; }
static volatile pthread_t th_self; static volatile int th_got, th_ready;
static void h_th(int s) { (void)s; th_got = pthread_equal(pthread_self(), th_self) ? 2 : 1; }
static void *th_main(void *a) { (void)a; th_self = pthread_self(); th_ready = 1; for (int i = 0; i < 300 && !th_got; i++) usleep(10000); return 0; }
static volatile int order[4], on;
static void h_a(int s) { (void)s; order[on++] = 1; }
static void h_b(int s) { (void)s; order[on++] = 2; }

int main(void)
{
    struct sigaction sa; memset(&sa, 0, sizeof sa);
    sa.sa_handler = h1; sigemptyset(&sa.sa_mask);
    CHECKC("sigaction", sigaction(SIGUSR1, &sa, 0) == 0);
    got = 0; raise(SIGUSR1);
    CHECK("raise_handler_runs", got == SIGUSR1, "handler did not run (got %d)", got);
    got = 0; kill(getpid(), SIGUSR1);
    CHECK("kill_self_handler", got == SIGUSR1, "handler did not run");

    sigset_t b, old; sigemptyset(&b); sigaddset(&b, SIGUSR1);
    sigprocmask(SIG_BLOCK, &b, &old); got = 0; raise(SIGUSR1);
    sigset_t pend; sigpending(&pend);
    CHECK("blocked_signal_pending", got == 0 && sigismember(&pend, SIGUSR1), "got=%d pending=%d", got, sigismember(&pend, SIGUSR1));
    sigprocmask(SIG_SETMASK, &old, 0);
    CHECK("unblock_delivers", got == SIGUSR1, "pending signal not delivered on unblock");

    sa.sa_sigaction = h_info; sa.sa_flags = SA_SIGINFO; sigaction(SIGUSR2, &sa, 0);
    got = 0; got_info_code = 99; raise(SIGUSR2);
    CHECK("siginfo_delivered", got == SIGUSR2, "handler not run");
    CHECK("siginfo_si_code_tkill", got_info_code == SI_TKILL || got_info_code == SI_USER, "si_code %d", got_info_code);

    /* SIGSEGV with the fault address, resumed by siglongjmp */
    sa.sa_sigaction = h_jump; sa.sa_flags = SA_SIGINFO | SA_NODEFER; g_jump = sa; sigaction(SIGSEGV, &sa, 0);
    got = 0; got_addr = 0;
    if (sigsetjmp(jb, 1) == 0) { *(volatile int *)0x1234 = 1; }
    CHECK("sigsegv_caught", got == SIGSEGV, "SIGSEGV handler not run (got %d)", got);
    CHECK("sigsegv_siginfo_given", have_info, "SA_SIGINFO handler got a NULL siginfo");
    CHECK("sigsegv_si_addr", got_addr == (void *)0x1234, "si_addr %p, want 0x1234", (void *)got_addr);
    CHECK("sigsegv_si_code", got_info_code == SEGV_MAPERR || got_info_code == SEGV_ACCERR, "si_code %d", got_info_code);
    /* and again: the process must survive two faults */
    got = 0; if (sigsetjmp(jb, 1) == 0) { *(volatile int *)0x5678 = 1; }
    CHECK("sigsegv_twice", got == SIGSEGV, "second fault not caught");
    /* SIGSEGV on SIGBUS-like: invalid instruction / divide by zero */
    sa.sa_sigaction = h_jump; sigaction(SIGFPE, &sa, 0);
    got = 0; if (sigsetjmp(jb, 1) == 0) { volatile int z = 0; volatile int q = 5 / z; (void)q; }
    CHECK("sigfpe_divide_by_zero", got == SIGFPE, "SIGFPE not delivered (got %d)", got);
    sigaction(SIGILL, &sa, 0);
    got = 0; if (sigsetjmp(jb, 1) == 0) { __asm__ volatile("ud2"); }
    CHECK("sigill_ud2", got == SIGILL, "SIGILL not delivered (got %d)", got);

    /* alternate stack: needed to handle stack overflow */
    stack_t ss = { .ss_sp = altstk, .ss_size = sizeof altstk, .ss_flags = 0 };
    errno = 0; int r = sigaltstack(&ss, 0);
    CHECKC("sigaltstack", r == 0);
    if (r == 0) {
        sa.sa_handler = h_alt; sa.sa_flags = SA_ONSTACK; sigaction(SIGUSR1, &sa, 0);
        got_on_alt = 0; raise(SIGUSR1);
        CHECK("sigaltstack_used", got_on_alt == 1, "handler did not run on the alternate stack");
    }

    /* timers */
    sa.sa_handler = h1; sa.sa_flags = 0; sigaction(SIGALRM, &sa, 0);
    got = 0; errno = 0; alarm(1);
    for (int i = 0; i < 200 && !got; i++) usleep(10000);
    CHECK("alarm_fires", got == SIGALRM, "no SIGALRM within 2 s");
    struct itimerval itv = { { 0, 0 }, { 0, 50000 } }; got = 0; errno = 0;
    r = setitimer(ITIMER_REAL, &itv, 0);
    CHECKC("setitimer", r == 0);
    for (int i = 0; i < 100 && !got; i++) usleep(10000);
    CHECK("setitimer_fires", got == SIGALRM, "no SIGALRM from setitimer");
    /* a signal interrupts a sleep */
    got = 0; itv.it_value.tv_usec = 80000; setitimer(ITIMER_REAL, &itv, 0);
    struct timespec ts = { 3, 0 }; errno = 0; r = nanosleep(&ts, 0);
    CHECK("signal_interrupts_nanosleep", r == -1 && errno == EINTR && got == SIGALRM, "r=%d errno=%d got=%d", r, errno, got);
    /* sigsuspend */
    sigemptyset(&b); sigaddset(&b, SIGALRM); sigprocmask(SIG_BLOCK, &b, &old);
    got = 0; itv.it_value.tv_usec = 60000; setitimer(ITIMER_REAL, &itv, 0);
    sigset_t wait_mask; sigemptyset(&wait_mask); errno = 0; r = sigsuspend(&wait_mask);
    CHECK("sigsuspend", r == -1 && errno == EINTR && got == SIGALRM, "r=%d errno=%d got=%d", r, errno, got);
    sigprocmask(SIG_SETMASK, &old, 0);

    /* SIGCHLD */
    sa.sa_handler = h_chld; sa.sa_flags = SA_RESTART; sigaction(SIGCHLD, &sa, 0);
    chld = 0; pid_t k = fork(); if (k == 0) _exit(0);
    for (int i = 0; i < 200 && !chld; i++) usleep(10000);
    waitpid(k, 0, 0);
    CHECK("sigchld_on_child_exit", chld >= 1, "no SIGCHLD");
    signal(SIGCHLD, SIG_IGN);
    k = fork(); if (k == 0) _exit(0); usleep(100000);
    errno = 0; pid_t w = waitpid(k, 0, 0);
    CHECK("sigchld_ign_autoreap", w == -1 && errno == ECHILD, "child not auto-reaped (w=%d)", w);
    signal(SIGCHLD, SIG_DFL);

    /* default actions: SIGTERM kills a child, SIGSTOP/CONT */
    k = fork(); if (k == 0) { for (;;) pause(); }
    usleep(30000); kill(k, SIGTERM); int st; waitpid(k, &st, 0);
    CHECK("sigterm_default_kills", WIFSIGNALED(st) && WTERMSIG(st) == SIGTERM, "status 0x%x", st);
    k = fork(); if (k == 0) { for (;;) pause(); }
    usleep(30000); kill(k, SIGSTOP); pid_t sw = waitpid(k, &st, WUNTRACED);
    CHECK("sigstop_reported", sw == k && WIFSTOPPED(st), "waitpid WUNTRACED -> %d st=0x%x", sw, st);
    kill(k, SIGKILL); waitpid(k, 0, 0);
    errno = 0; r = kill(0x7fffff, 0);
    CHECK("kill_nonexistent_esrch", r == -1 && errno == ESRCH, "r=%d errno=%d", r, errno);

    /* signal to one thread */
    sa.sa_handler = h_th; sa.sa_flags = 0; sigaction(SIGUSR2, &sa, 0);
    pthread_t t; pthread_create(&t, 0, th_main, 0);
    while (!th_ready) usleep(1000);
    errno = 0; r = pthread_kill(t, SIGUSR2);
    pthread_join(t, 0);
    CHECK("pthread_kill_targets_thread", r == 0 && th_got == 2, "r=%d handler ran in %s", r, th_got == 1 ? "another thread" : "nobody");

    /* handler runs, then the order of two different signals */
    sa.sa_handler = h_a; sigaction(SIGUSR1, &sa, 0); sa.sa_handler = h_b; sigaction(SIGUSR2, &sa, 0);
    raise(SIGUSR1); raise(SIGUSR2);
    CHECK("two_signals_in_order", on == 2 && order[0] == 1 && order[1] == 2, "order %d %d (%d)", order[0], order[1], on);
    /* rt signals and sigqueue */
    union sigval sv; sv.sival_int = 123; got = 0;
    sa.sa_sigaction = h_info; sa.sa_flags = SA_SIGINFO; sigaction(SIGRTMIN, &sa, 0);
    errno = 0; r = sigqueue(getpid(), SIGRTMIN, sv);
    CHECKC("sigqueue_rt", r == 0 && got == SIGRTMIN);
    return 0;
}
