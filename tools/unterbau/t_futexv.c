#define TNAME "futexv"
#include "t.h"
#include <pthread.h>
#include <signal.h>
#include <stdint.h>
#include <stdlib.h>
#include <sys/syscall.h>
#include <sys/time.h>
#include <time.h>

#define NR_FUTEX_WAITV 449
#define NR_FUTEX_WAKE2 454
#define FUTEX2_U32 2
#define FUTEX2_PRIVATE 128
#define WAITV_MAX 128
#define LEAK_ROUNDS 300
#define LEAK_WIDTH 8
#define NS_PER_MS 1000000L
#define TIMEOUT_MS 60

struct waitv {
    uint64_t val;
    uint64_t uaddr;
    uint32_t flags;
    uint32_t reserved;
};

static volatile uint32_t words[WAITV_MAX + 1];
static struct waitv vec[WAITV_MAX + 1];

static void fill(int n, uint32_t flags)
{
    for (int i = 0; i < n; i++) {
        words[i] = 0;
        vec[i].val = 0;
        vec[i].uaddr = (uint64_t)(uintptr_t)&words[i];
        vec[i].flags = flags;
        vec[i].reserved = 0;
    }
}

static long waitv(struct waitv *w, unsigned n, unsigned flags, const struct timespec *ts, int clock)
{
    errno = 0;
    return syscall(NR_FUTEX_WAITV, w, n, flags, ts, clock);
}

static long wake_one(volatile uint32_t *addr)
{
    return syscall(SYS_futex, addr, 1 | 128, 1, 0, 0, 0);
}

static long now_ms(void)
{
    struct timespec t;
    clock_gettime(CLOCK_MONOTONIC, &t);
    return t.tv_sec * 1000 + t.tv_nsec / NS_PER_MS;
}

static struct timespec abs_after(int clock, long ms)
{
    struct timespec t;
    clock_gettime(clock, &t);
    t.tv_sec += ms / 1000;
    t.tv_nsec += (ms % 1000) * NS_PER_MS;
    if (t.tv_nsec >= 1000000000L) {
        t.tv_sec++;
        t.tv_nsec -= 1000000000L;
    }
    return t;
}

static volatile long thread_ret;
static volatile long thread_errno;
static volatile int thread_started;
static int thread_n;

static void *waiter(void *arg)
{
    (void)arg;
    thread_started = 1;
    thread_ret = waitv(vec, thread_n, 0, 0, 0);
    thread_errno = errno;
    return 0;
}

static long run_waiter(int n, int wake_index)
{
    pthread_t t;
    thread_n = n;
    thread_started = 0;
    thread_ret = 12345;
    pthread_create(&t, 0, waiter, 0);
    while (!thread_started)
        usleep(1000);
    usleep(60 * 1000);
    int stuck = thread_ret != 12345;
    words[wake_index] = 1;
    wake_one(&words[wake_index]);
    pthread_join(t, 0);
    return stuck ? -2 : thread_ret;
}

static void test_invalid(void)
{
    fill(2, FUTEX2_U32 | FUTEX2_PRIVATE);
    CHECK("nr_zero_einval", waitv(vec, 0, 0, 0, 0) == -1 && errno == EINVAL, "errno=%d", errno);
    CHECK("nr_too_big_einval", waitv(vec, WAITV_MAX + 1, 0, 0, 0) == -1 && errno == EINVAL, "errno=%d", errno);
    CHECK("flags_einval", waitv(vec, 2, 1, 0, 0) == -1 && errno == EINVAL, "errno=%d", errno);
    CHECK("null_efault", waitv(0, 2, 0, 0, 0) == -1 && errno == EFAULT, "errno=%d", errno);
    vec[1].flags = FUTEX2_PRIVATE;
    CHECK("bad_size_einval", waitv(vec, 2, 0, 0, 0) == -1 && errno == EINVAL, "errno=%d", errno);
    vec[1].flags = FUTEX2_U32 | 0x40;
    CHECK("unknown_flag_einval", waitv(vec, 2, 0, 0, 0) == -1 && errno == EINVAL, "errno=%d", errno);
    vec[1].flags = FUTEX2_U32;
    vec[1].reserved = 1;
    CHECK("reserved_einval", waitv(vec, 2, 0, 0, 0) == -1 && errno == EINVAL, "errno=%d", errno);
    vec[1].reserved = 0;
    vec[1].uaddr += 1;
    CHECK("misaligned_einval", waitv(vec, 2, 0, 0, 0) == -1 && errno == EINVAL, "errno=%d", errno);
    vec[1].uaddr = 0;
    CHECK("bad_uaddr_efault", waitv(vec, 2, 0, 0, 0) == -1 && errno == EFAULT, "errno=%d", errno);
    fill(2, FUTEX2_U32 | FUTEX2_PRIVATE);
    struct timespec ts = abs_after(CLOCK_MONOTONIC, 1000);
    CHECK("bad_clock_einval", waitv(vec, 2, 0, &ts, 7) == -1 && errno == EINVAL, "errno=%d", errno);
}

static void test_values(void)
{
    fill(3, FUTEX2_U32 | FUTEX2_PRIVATE);
    vec[2].val = 5;
    CHECK("mismatch_eagain", waitv(vec, 3, 0, 0, 0) == -1 && errno == EAGAIN, "errno=%d", errno);
    fill(1, FUTEX2_U32 | FUTEX2_PRIVATE);
    vec[0].val = 0x100000000ULL;
    CHECK("high_val_bits_eagain", waitv(vec, 1, 0, 0, 0) == -1 && errno == EAGAIN, "errno=%d", errno);
}

static void test_wake_index(void)
{
    fill(4, FUTEX2_U32 | FUTEX2_PRIVATE);
    long r = run_waiter(4, 2);
    CHECK("wake_middle_index", r == 2, "ret=%ld", r);
    fill(4, FUTEX2_U32 | FUTEX2_PRIVATE);
    r = run_waiter(4, 0);
    CHECK("wake_first_index", r == 0, "ret=%ld", r);
    fill(WAITV_MAX, FUTEX2_U32 | FUTEX2_PRIVATE);
    r = run_waiter(WAITV_MAX, WAITV_MAX - 1);
    CHECK("wake_last_of_max", r == WAITV_MAX - 1, "ret=%ld", r);
    fill(2, FUTEX2_U32);
    r = run_waiter(2, 1);
    CHECK("wake_shared_flag", r == 1, "ret=%ld", r);
}

static void test_timeout(void)
{
    int clocks[2] = {CLOCK_MONOTONIC, CLOCK_REALTIME};
    const char *names[2] = {"timeout_monotonic", "timeout_realtime"};
    for (int c = 0; c < 2; c++) {
        fill(3, FUTEX2_U32 | FUTEX2_PRIVATE);
        struct timespec ts = abs_after(clocks[c], TIMEOUT_MS);
        long a = now_ms();
        long r = waitv(vec, 3, 0, &ts, clocks[c]);
        long dt = now_ms() - a;
        CHECK(names[c], r == -1 && errno == ETIMEDOUT && dt >= TIMEOUT_MS / 2 && dt < 1500, "ret=%ld errno=%d dt=%ld", r, errno, dt);
    }
    fill(1, FUTEX2_U32 | FUTEX2_PRIVATE);
    struct timespec past = {1, 0};
    CHECK("past_deadline_etimedout", waitv(vec, 1, 0, &past, CLOCK_MONOTONIC) == -1 && errno == ETIMEDOUT, "errno=%d", errno);
}

static volatile int sigs;
static void on_alarm(int s) { (void)s; sigs++; }

static void test_signal(void)
{
    struct sigaction sa = {0};
    sa.sa_handler = on_alarm;
    sigaction(SIGALRM, &sa, 0);
    struct itimerval it = {{0, 0}, {0, 50 * 1000}};
    fill(3, FUTEX2_U32 | FUTEX2_PRIVATE);
    setitimer(ITIMER_REAL, &it, 0);
    long a = now_ms();
    long r = waitv(vec, 3, 0, 0, 0);
    long dt = now_ms() - a;
    CHECK("signal_eintr", r == -1 && errno == EINTR && sigs == 1 && dt < 1500, "ret=%ld errno=%d sigs=%d dt=%ld", r, errno, sigs, dt);
}

static void test_leak(void)
{
    int ok = 1;
    for (int i = 0; i < LEAK_ROUNDS && ok; i++) {
        fill(LEAK_WIDTH, FUTEX2_U32 | FUTEX2_PRIVATE);
        struct timespec ts = abs_after(CLOCK_MONOTONIC, 1);
        long r = waitv(vec, LEAK_WIDTH, 0, &ts, CLOCK_MONOTONIC);
        ok = r == -1 && errno == ETIMEDOUT;
    }
    CHECK("pool_does_not_leak", ok, "failed after timeouts");
    fill(LEAK_WIDTH, FUTEX2_U32 | FUTEX2_PRIVATE);
    vec[LEAK_WIDTH - 1].val = 9;
    ok = 1;
    for (int i = 0; i < LEAK_ROUNDS && ok; i++)
        ok = waitv(vec, LEAK_WIDTH, 0, 0, 0) == -1 && errno == EAGAIN;
    CHECK("pool_does_not_leak_eagain", ok, "failed");
}

static volatile int multi_got;
static void *multi_waiter(void *arg)
{
    struct waitv mine = {0, (uint64_t)(uintptr_t)arg, FUTEX2_U32 | FUTEX2_PRIVATE, 0};
    long r = waitv(&mine, 1, 0, 0, 0);
    if (r == 0)
        __sync_fetch_and_add(&multi_got, 1);
    return 0;
}

static void test_mixed_waiters(void)
{
    pthread_t t[3];
    fill(2, FUTEX2_U32 | FUTEX2_PRIVATE);
    multi_got = 0;
    for (int i = 0; i < 3; i++)
        pthread_create(&t[i], 0, multi_waiter, (void *)&words[0]);
    usleep(100 * 1000);
    long woken = syscall(SYS_futex, &words[0], 1 | 128, 3, 0, 0, 0);
    for (int i = 0; i < 3; i++)
        pthread_join(t[i], 0);
    CHECK("single_futex_waitv_wake3", woken == 3 && multi_got == 3, "woken=%ld got=%d", woken, multi_got);
}

int main(void)
{
    test_invalid();
    test_values();
    test_wake_index();
    test_timeout();
    test_signal();
    test_leak();
    test_mixed_waiters();
    return 0;
}
