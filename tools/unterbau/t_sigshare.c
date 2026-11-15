#define TNAME "sigshare"
#include "t.h"
#include <pthread.h>
#include <signal.h>
#include <stdatomic.h>
#include <sys/syscall.h>

#define SIG_PROBE (SIGRTMIN + 1)
#define WAIT_TURNS 200
#define WAIT_STEP_US 10000

static atomic_int hits;
static atomic_int worker_ready;
static atomic_int worker_stop;
static atomic_int worker_tid;

static void on_probe(int sig)
{
    (void)sig;
    atomic_fetch_add(&hits, 1);
}

static void *worker(void *arg)
{
    (void)arg;
    atomic_store(&worker_tid, (int)syscall(SYS_gettid));
    atomic_store(&worker_ready, 1);
    while (!atomic_load(&worker_stop))
        usleep(1000);
    return 0;
}

static int wait_hits(int want)
{
    for (int i = 0; i < WAIT_TURNS && atomic_load(&hits) < want; i++)
        usleep(WAIT_STEP_US);
    return atomic_load(&hits) >= want;
}

int main(void)
{
    pthread_t th;
    pthread_create(&th, 0, worker, 0);
    while (!atomic_load(&worker_ready))
        usleep(1000);
    struct sigaction sa = { 0 };
    sa.sa_handler = on_probe;
    sigemptyset(&sa.sa_mask);
    CHECK("sigaction", sigaction(SIG_PROBE, &sa, 0) == 0, "errno=%d", errno);
    syscall(SYS_tgkill, getpid(), atomic_load(&worker_tid), SIG_PROBE);
    CHECK("sibling_runs_handler", wait_hits(1), "hits=%d (handler installed after the thread started)", atomic_load(&hits));
    syscall(SYS_tgkill, getpid(), getpid(), SIG_PROBE);
    CHECK("caller_runs_handler", wait_hits(2), "hits=%d", atomic_load(&hits));
    atomic_store(&worker_stop, 1);
    pthread_join(th, 0);
    return 0;
}
