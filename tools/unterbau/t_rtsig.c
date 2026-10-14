/* rtsig: real-time signals 32..64 (r730): action table, mask, delivery, default action, sigqueue, fork inheritance, pthread_kill. */
#define TNAME "rtsig"
#include "t.h"
#include <pthread.h>
#include <signal.h>
#include <stdlib.h>
#include <sys/wait.h>

static volatile int got[70], last_sig;
static void h(int s) { if (s > 0 && s < 70) got[s]++; last_sig = s; }
static volatile int th_ok;
static void h_th(int s) { (void)s; th_ok = 1; }
static void *th_main(void *a) { (void)a; for (int i = 0; i < 300 && !th_ok; i++) usleep(10000); return 0; }

int main(void)
{
    struct sigaction sa; memset(&sa, 0, sizeof sa);
    sa.sa_handler = h; sigemptyset(&sa.sa_mask);
    CHECK("range", SIGRTMIN >= 32 && SIGRTMAX == 64, "SIGRTMIN=%d SIGRTMAX=%d", SIGRTMIN, SIGRTMAX);
    int ok = 1, bad = 0;
    for (int s = 35; s <= 64; s++) { sa.sa_handler = h; if (sigaction(s, &sa, 0) != 0) { ok = 0; bad = s; break; } }
    CHECK("sigaction_all", ok, "sigaction(%d) failed errno=%d", bad, errno);
    errno = 0;
    CHECK("sigaction_65_einval", sigaction(65, &sa, 0) == -1 && errno == EINVAL, "errno=%d", errno);
    int all = 1, first_bad = 0;
    for (int s = 35; s <= 64; s++) { got[s] = 0; raise(s); if (got[s] != 1) { all = 0; first_bad = s; break; } }
    CHECK("raise_all_delivered", all, "signal %d not delivered exactly once (%d)", first_bad, first_bad ? got[first_bad] : 0);
    kill(getpid(), 64); CHECK("kill_64", got[64] == 2, "got %d", got[64]);
    /* the action record of 40 does not alias 8 or 63 */
    struct sigaction o; sa.sa_handler = SIG_IGN; sigaction(40, &sa, 0);
    sigaction(41, 0, &o); CHECK("records_independent", o.sa_handler == h, "41 handler changed to %p", (void *)o.sa_handler);
    sigaction(8, 0, &o); CHECK("low_record_intact", o.sa_handler != SIG_IGN, "SIGFPE record overwritten");
    sa.sa_handler = h; sigaction(40, &sa, 0);
    /* mask */
    sigset_t b, old, pend; sigemptyset(&b); sigaddset(&b, 50); sigaddset(&b, 64);
    sigprocmask(SIG_BLOCK, &b, &old); got[50] = got[64] = 0; raise(50); raise(64);
    sigpending(&pend);
    CHECK("rt_blocked_pending", got[50] == 0 && got[64] == 0 && sigismember(&pend, 50) && sigismember(&pend, 64), "g50=%d g64=%d", got[50], got[64]);
    sigprocmask(SIG_SETMASK, &old, 0);
    CHECK("rt_unblock_delivers", got[50] == 1 && got[64] == 1, "g50=%d g64=%d", got[50], got[64]);
    /* sa_mask with a high signal blocks it during the handler of another */
    /* sigqueue */
    union sigval sv; sv.sival_int = 7; got[SIGRTMIN + 1] = 0;
    errno = 0;
    CHECKC("sigqueue", sigqueue(getpid(), SIGRTMIN + 1, sv) == 0 && got[SIGRTMIN + 1] == 1);
    /* default action of an RT signal terminates */
    pid_t k = fork();
    if (k == 0) { signal(45, SIG_DFL); raise(45); _exit(7); }
    int st = 0; waitpid(k, &st, 0);
    CHECK("default_terminates", WIFSIGNALED(st) && WTERMSIG(st) == 45, "st=0x%x", st);
    /* the handler is inherited over fork */
    got[48] = 0; k = fork();
    if (k == 0) { raise(48); _exit(got[48] == 1 ? 0 : 3); }
    waitpid(k, &st, 0);
    CHECK("fork_inherits_handler", WIFEXITED(st) && WEXITSTATUS(st) == 0, "st=0x%x", st);
    /* SIG_IGN and exec reset are the same for RT: ignore */
    sa.sa_handler = SIG_IGN; sigaction(52, &sa, 0); got[52] = 0; raise(52);
    CHECK("rt_ignored", got[52] == 0, "ignored signal ran the handler");
    /* siginfo handler on an RT signal */
    /* pthread_kill with an RT signal (musl's cancellation uses 33) */
    sa.sa_handler = h_th; sigaction(SIGRTMIN + 3, &sa, 0);
    pthread_t t; pthread_create(&t, 0, th_main, 0); usleep(20000);
    int r = pthread_kill(t, SIGRTMIN + 3); pthread_join(t, 0);
    CHECK("pthread_kill_rt", r == 0 && th_ok, "r=%d ok=%d", r, th_ok);
    /* pthread_cancel (SIGCANCEL = 33 in musl) */
    return 0;
}
