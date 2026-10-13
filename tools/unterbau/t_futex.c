/* futex with a real wait queue (r714): wake counts, FIFO, bitsets, requeue, wake_op, timeouts, signals, PI, hand-over latency. */
#define TNAME "futex"
#include "t.h"
#include <pthread.h>
#include <stdlib.h>
#include <sched.h>
#include <signal.h>
#include <sys/syscall.h>
#include <sys/time.h>
#include <time.h>
#include <stdint.h>

#define F_WAIT 0
#define F_WAKE 1
#define F_REQUEUE 3
#define F_CMP_REQUEUE 4
#define F_WAKE_OP 5
#define F_LOCK_PI 6
#define F_UNLOCK_PI 7
#define F_TRYLOCK_PI 8
#define F_WAIT_BITSET 9
#define F_WAKE_BITSET 10
#define F_PRIV 128

static long fx(volatile int *a, int op, int val, const struct timespec *ts, volatile int *a2, int val3)
{
    return syscall(SYS_futex, a, op, val, ts, a2, val3);
}

static long now_ms(void)
{
    struct timespec t;
    clock_gettime(CLOCK_MONOTONIC, &t);
    return t.tv_sec * 1000 + t.tv_nsec / 1000000;
}

static void ms_sleep(int ms) { usleep(ms * 1000); }

/* ---- wake counts + FIFO ---- */
static volatile int wa;
static volatile int order_n, order[8];
static volatile int started;
static void *waiter_fifo(void *arg)
{
    long id = (long)arg;
    started++;
    while (wa == 0) fx(&wa, F_WAIT | F_PRIV, 0, 0, 0, 0);
    int k = __sync_fetch_and_add(&order_n, 1);
    order[k] = (int)id;
    return 0;
}

static volatile long wret[8];
static volatile int wbits_word;
static volatile long bit_ret;
static void *bit_waiter(void *arg)
{
    long bits = (long)arg;
    started++;
    bit_ret = fx(&wbits_word, F_WAIT_BITSET | F_PRIV, 0, 0, 0, (int)bits);
    return 0;
}

static volatile int rq_a, rq_b;
static volatile int rq_woke;
static void *rq_waiter(void *arg)
{
    (void)arg;
    started++;
    long r = fx(&rq_a, F_WAIT | F_PRIV, 0, 0, 0, 0);
    (void)r;
    __sync_fetch_and_add(&rq_woke, 1);
    return 0;
}

/* ---- ping-pong ---- */
static volatile int ping, pong;
#define ROUNDS 100
static void *pp_thread(void *arg)
{
    (void)arg;
    for (int i = 1; i <= ROUNDS; i++) {
        while (ping < i) fx(&ping, F_WAIT | F_PRIV, ping, 0, 0, 0);
        pong = i;
        fx(&pong, F_WAKE | F_PRIV, 1, 0, 0, 0);
    }
    return 0;
}

/* ---- PI ---- */
static volatile int pi;
static volatile long pi_got, pi_t_wait;
static volatile int pi_tid_b;
static void *pi_b(void *arg)
{
    (void)arg;
    pi_tid_b = (int)syscall(SYS_gettid);
    long t0 = now_ms();
    pi_got = fx(&pi, F_LOCK_PI | F_PRIV, 0, 0, 0, 0);
    pi_t_wait = now_ms() - t0;
    return 0;
}

static volatile int sigs;
static void on_alarm(int s) { (void)s; sigs++; }

int main(void)
{
    pthread_t t[8];
    long r;

    /* WAIT with a wrong value: EAGAIN at once */
    wa = 1;
    errno = 0;
    r = fx(&wa, F_WAIT | F_PRIV, 0, 0, 0, 0);
    CHECK("wait_eagain", r == -1 && errno == EAGAIN, "ret %ld errno %d", r, errno);
    wa = 0;

    /* WAKE with nobody waiting returns 0 */
    r = fx(&wa, F_WAKE | F_PRIV, 5, 0, 0, 0);
    CHECK("wake_nobody_zero", r == 0, "ret %ld", r);

    /* timeout: relative, 50 ms */
    {
        struct timespec ts = {0, 50 * 1000 * 1000};
        long a = now_ms();
        errno = 0;
        r = fx(&wa, F_WAIT | F_PRIV, 0, &ts, 0, 0);
        long dt = now_ms() - a;
        CHECK("wait_timeout", r == -1 && errno == ETIMEDOUT && dt >= 40 && dt < 500, "ret %ld errno %d after %ld ms", r, errno, dt);
        /* absolute timeout through WAIT_BITSET on CLOCK_MONOTONIC */
        struct timespec ab;
        clock_gettime(CLOCK_MONOTONIC, &ab);
        ab.tv_nsec += 60 * 1000 * 1000;
        if (ab.tv_nsec >= 1000000000) { ab.tv_sec++; ab.tv_nsec -= 1000000000; }
        a = now_ms();
        errno = 0;
        r = fx(&wa, F_WAIT_BITSET | F_PRIV, 0, &ab, 0, -1);
        dt = now_ms() - a;
        CHECK("wait_bitset_abs_timeout", r == -1 && errno == ETIMEDOUT && dt >= 45 && dt < 500, "ret %ld errno %d after %ld ms", r, errno, dt);
    }

    /* three waiters, wake 2 -> 2, then 1 -> 1; FIFO order */
    started = 0;
    for (long i = 0; i < 3; i++) { pthread_create(&t[i], 0, waiter_fifo, (void *)i); ms_sleep(40); }
    wa = 1;
    r = fx(&wa, F_WAKE | F_PRIV, 2, 0, 0, 0);
    CHECK("wake_returns_count", r == 2, "wake(2) -> %ld", r);
    ms_sleep(50);
    CHECK("wake_only_requested", order_n == 2, "%d threads ran after wake(2), want 2", order_n);
    CHECK("wake_fifo", order[0] == 0 && order[1] == 1, "order %d %d (want 0 1)", order[0], order[1]);
    r = fx(&wa, F_WAKE | F_PRIV, 10, 0, 0, 0);
    CHECK("wake_rest", r == 1, "wake(10) -> %ld (one waiter left)", r);
    for (int i = 0; i < 3; i++) pthread_join(t[i], 0);

    /* bitset: wake with a non-matching mask wakes nobody */
    started = 0; bit_ret = 99; wbits_word = 0;
    pthread_create(&t[0], 0, bit_waiter, (void *)0x2L);
    ms_sleep(50);
    r = fx(&wbits_word, F_WAKE_BITSET | F_PRIV, 1, 0, 0, 0x1);
    CHECK("bitset_nomatch", r == 0, "wake_bitset(0x1) on waiter 0x2 -> %ld", r);
    r = fx(&wbits_word, F_WAKE_BITSET | F_PRIV, 1, 0, 0, 0x6);
    CHECK("bitset_match", r == 1, "wake_bitset(0x6) on waiter 0x2 -> %ld", r);
    pthread_join(t[0], 0);
    CHECK("bitset_zero_einval", (errno = 0, fx(&wbits_word, F_WAKE_BITSET | F_PRIV, 1, 0, 0, 0) == -1 && errno == EINVAL), "errno %d", errno);

    /* cmp_requeue: 3 waiters on A: wake 1, move 2 to B */
    rq_a = 0; rq_b = 0; rq_woke = 0; started = 0;
    for (int i = 0; i < 3; i++) { pthread_create(&t[i], 0, rq_waiter, 0); ms_sleep(30); }
    errno = 0;
    r = fx(&rq_a, F_CMP_REQUEUE | F_PRIV, 1, (const struct timespec *)(long)2, &rq_b, 7);
    CHECK("cmp_requeue_mismatch", r == -1 && errno == EAGAIN, "ret %ld errno %d", r, errno);
    r = fx(&rq_a, F_CMP_REQUEUE | F_PRIV, 1, (const struct timespec *)(long)2, &rq_b, 0);
    CHECK("cmp_requeue_count", r == 3, "ret %ld (woken 1 + requeued 2)", r);
    ms_sleep(50);
    CHECK("requeue_one_woke", rq_woke == 1, "%d woke after the requeue, want 1", rq_woke);
    r = fx(&rq_a, F_WAKE | F_PRIV, 10, 0, 0, 0);
    CHECK("requeue_left_a_empty", r == 0, "wake on A -> %ld (all moved to B)", r);
    r = fx(&rq_b, F_WAKE | F_PRIV, 10, 0, 0, 0);
    CHECK("requeue_woke_b", r == 2, "wake on B -> %ld", r);
    for (int i = 0; i < 3; i++) pthread_join(t[i], 0);

    /* wake_op: *uaddr2 = 5 (SET), compare old (0) NE 0 -> false: only uaddr is woken (nobody waits: 0) */
    {
        volatile int u1 = 0, u2 = 0;
        int enc = (0 << 28) | (1 << 24) | (5 << 12) | 0;
        r = fx(&u1, F_WAKE_OP | F_PRIV, 1, (const struct timespec *)(long)1, &u2, enc);
        CHECK("wake_op_set", r == 0 && u2 == 5, "ret %ld u2 %d", r, u2);
        int enc2 = (1 << 28) | (0 << 24) | (3 << 12) | 5; /* ADD 3, old == 5 */
        r = fx(&u1, F_WAKE_OP | F_PRIV, 1, (const struct timespec *)(long)1, &u2, enc2);
        CHECK("wake_op_add", r == 0 && u2 == 8, "ret %ld u2 %d", r, u2);
    }

    /* EINTR: an untimed wait is cut by a signal */
    wa = 0;
    {
        struct sigaction sa;
        memset(&sa, 0, sizeof sa);
        sa.sa_handler = on_alarm;
        sigaction(SIGALRM, &sa, 0);
        struct itimerval it = {{0, 0}, {0, 50 * 1000}};
        sigs = 0;
        setitimer(ITIMER_REAL, &it, 0);
        errno = 0;
        long a = now_ms();
        r = fx(&wa, F_WAIT | F_PRIV, 0, 0, 0, 0);
        long dt = now_ms() - a;
        CHECK("wait_signal_eintr", r == -1 && errno == EINTR && sigs == 1 && dt < 1500, "ret %ld errno %d sigs %d after %ld ms", r, errno, sigs, dt);
    }

    /* hand-over latency: 100 round trips between two threads (the old poll needed >= 10 ms per hop = >= 2 s) */
    ping = 0; pong = 0;
    pthread_create(&t[0], 0, pp_thread, 0);
    {
        long a = now_ms();
        for (int i = 1; i <= ROUNDS; i++) {
            ping = i;
            fx(&ping, F_WAKE | F_PRIV, 1, 0, 0, 0);
            while (pong < i) fx(&pong, F_WAIT | F_PRIV, pong, 0, 0, 0);
        }
        long dt = now_ms() - a;
        pthread_join(t[0], 0);
        CHECK("pingpong_latency", dt < 800, "%d round trips took %ld ms", ROUNDS, dt);
        CHECK("pingpong_complete", ping == ROUNDS && pong == ROUNDS, "ping %d pong %d", ping, pong);
    }

    /* PI: owner word protocol */
    {
        int me = (int)syscall(SYS_gettid);
        pi = 0;
        r = fx(&pi, F_LOCK_PI | F_PRIV, 0, 0, 0, 0);
        CHECK("pi_lock_free", r == 0 && pi == me, "ret %ld word %d tid %d", r, pi, me);
        errno = 0;
        r = fx(&pi, F_TRYLOCK_PI | F_PRIV, 0, 0, 0, 0);
        CHECK("pi_trylock_own_deadlk", r == -1 && errno == EDEADLK, "ret %ld errno %d", r, errno);
        pthread_create(&t[0], 0, pi_b, 0);
        ms_sleep(100);
        CHECK("pi_waiter_bit", (pi & 0x80000000) != 0 && (pi & 0x3FFFFFFF) == me, "word 0x%x", pi);
        r = fx(&pi, F_UNLOCK_PI | F_PRIV, 0, 0, 0, 0);
        CHECK("pi_unlock_ret", r == 0, "ret %ld", r);
        pthread_join(t[0], 0);
        CHECK("pi_handover", pi_got == 0 && (pi & 0x3FFFFFFF) == pi_tid_b && pi_t_wait >= 80, "ret %ld word 0x%x waited %ld ms", (long)pi_got, pi, (long)pi_t_wait);
        errno = 0;
        r = fx(&pi, F_UNLOCK_PI | F_PRIV, 0, 0, 0, 0);
        CHECK("pi_unlock_not_owner", r == -1 && errno == EPERM, "ret %ld errno %d", r, errno);
    }
    return 0;
}
