#define TNAME "sysmore"
#include "t.h"
#include <fcntl.h>
#include <pthread.h>
#include <stdint.h>
#include <sys/syscall.h>
#include <time.h>

#define NR_IO_SETUP 206
#define NR_IO_DESTROY 207
#define NR_IO_PGETEVENTS 333
#define NR_CACHESTAT 451
#define NR_FUTEX_WAKE 454
#define NR_FUTEX_WAIT 455
#define NR_FUTEX_REQUEUE 456
#define FUTEX2_SIZE_U32 0x02
#define FUTEX2_PRIVATE 0x80
#define FLAGS_PRIVATE_U32 (FUTEX2_SIZE_U32 | FUTEX2_PRIVATE)
#define MASK_ALL 0xffffffffUL
#define EVENT_BYTES 32
#define EVENT_SLOTS 4
#define CACHESTAT_WORDS 5
#define WAKE_WAIT_MS 200
#define SIGSET_BYTES 8
#define BAD_SIGSET_BYTES 3

struct waitv {
    uint64_t val;
    uint64_t uaddr;
    uint32_t flags;
    uint32_t reserved;
};

struct sigmask_arg {
    const void *mask;
    size_t size;
};

struct range {
    uint64_t off;
    uint64_t len;
};

static volatile unsigned word_a;
static volatile unsigned word_b;
static volatile int waiter_result = 1;

static long raw(long nr, long a, long b, long c, long d, long e, long f)
{
    errno = 0;
    return syscall(nr, a, b, c, d, e, f);
}

static void *waiter(void *arg)
{
    (void)arg;
    waiter_result = (int)raw(NR_FUTEX_WAIT, (long)&word_a, 0, MASK_ALL, FLAGS_PRIVATE_U32, 0, CLOCK_MONOTONIC);
    return NULL;
}

static void nap(void)
{
    struct timespec ts = {0, WAKE_WAIT_MS * 1000000L};
    nanosleep(&ts, NULL);
}

static void pgetevents_checks(void)
{
    unsigned long ctx = 0;
    char events[EVENT_BYTES * EVENT_SLOTS];
    struct timespec zero = {0, 0};
    struct timespec bad_ts = {0, 2000000000L};
    unsigned long mask = 0;
    struct sigmask_arg good = {&mask, SIGSET_BYTES};
    struct sigmask_arg bad = {&mask, BAD_SIGSET_BYTES};
    long r = raw(NR_IO_SETUP, EVENT_SLOTS, (long)&ctx, 0, 0, 0, 0);
    CHECKC("io_setup", r == 0);
    r = raw(NR_IO_PGETEVENTS, ctx, 0, EVENT_SLOTS, (long)events, (long)&zero, 0);
    CHECKC("pgetevents_empty", r == 0);
    r = raw(NR_IO_PGETEVENTS, ctx, 0, EVENT_SLOTS, (long)events, (long)&zero, (long)&good);
    CHECKC("pgetevents_sigmask", r == 0);
    r = raw(NR_IO_PGETEVENTS, ctx, 0, EVENT_SLOTS, (long)events, (long)&zero, (long)&bad);
    CHECK("pgetevents_bad_sigsetsize", r == -1 && errno == EINVAL, "r=%ld errno=%d", r, errno);
    r = raw(NR_IO_PGETEVENTS, ctx, 0, EVENT_SLOTS, (long)events, (long)&bad_ts, 0);
    CHECK("pgetevents_bad_timespec", r == -1 && errno == EINVAL, "r=%ld errno=%d", r, errno);
    r = raw(NR_IO_PGETEVENTS, ctx, 0, EVENT_SLOTS, (long)events, 1, 0);
    CHECK("pgetevents_fault_timeout", r == -1 && errno == EFAULT, "r=%ld errno=%d", r, errno);
    r = raw(NR_IO_PGETEVENTS, 0, 0, EVENT_SLOTS, (long)events, 0, 0);
    CHECK("pgetevents_bad_ctx", r == -1 && errno == EINVAL, "r=%ld errno=%d", r, errno);
    raw(NR_IO_DESTROY, ctx, 0, 0, 0, 0, 0);
}

static void requeue_pair(struct waitv *pair, unsigned expected)
{
    pair[0].val = expected;
    pair[0].uaddr = (uintptr_t)&word_a;
    pair[0].flags = FLAGS_PRIVATE_U32;
    pair[0].reserved = 0;
    pair[1].val = 0;
    pair[1].uaddr = (uintptr_t)&word_b;
    pair[1].flags = FLAGS_PRIVATE_U32;
    pair[1].reserved = 0;
}

static void requeue_checks(void)
{
    struct waitv pair[2];
    word_a = 0;
    word_b = 0;
    requeue_pair(pair, 7);
    long r = raw(NR_FUTEX_REQUEUE, (long)pair, 0, 1, 1, 0, 0);
    CHECKC("requeue_value_mismatch", r == -1 && errno == EAGAIN);
    requeue_pair(pair, 0);
    r = raw(NR_FUTEX_REQUEUE, (long)pair, 0, 1, 1, 0, 0);
    CHECKC("requeue_nobody", r == 0);
    r = raw(NR_FUTEX_REQUEUE, (long)pair, 1, 1, 1, 0, 0);
    CHECK("requeue_bad_flags", r == -1 && errno == EINVAL, "r=%ld errno=%d", r, errno);
    pair[1].flags = FUTEX2_SIZE_U32;
    r = raw(NR_FUTEX_REQUEUE, (long)pair, 0, 1, 1, 0, 0);
    CHECK("requeue_private_mismatch", r == -1 && errno == EINVAL, "r=%ld errno=%d", r, errno);
    requeue_pair(pair, 0);
    pthread_t th;
    pthread_create(&th, NULL, waiter, NULL);
    nap();
    r = raw(NR_FUTEX_REQUEUE, (long)pair, 0, 0, 1, 0, 0);
    CHECK("requeue_moves_waiter", r == 1, "r=%ld errno=%d", r, errno);
    long woken_a = raw(NR_FUTEX_WAKE, (long)&word_a, MASK_ALL, 1, FLAGS_PRIVATE_U32, 0, 0);
    long woken_b = raw(NR_FUTEX_WAKE, (long)&word_b, MASK_ALL, 1, FLAGS_PRIVATE_U32, 0, 0);
    pthread_join(th, NULL);
    CHECK("requeue_wake_on_target", woken_a == 0 && woken_b == 1 && waiter_result == 0,
          "a=%ld b=%ld waiter=%d", woken_a, woken_b, waiter_result);
}

static void cachestat_checks(void)
{
    struct range range = {0, 0};
    uint64_t out[CACHESTAT_WORDS];
    int fd = open("/tmp/sysmore.cachestat", O_RDWR | O_CREAT | O_TRUNC, 0600);
    long r = raw(NR_CACHESTAT, fd, (long)&range, (long)out, 0, 0, 0);
    CHECKC("cachestat_regular", r == 0);
    r = raw(NR_CACHESTAT, fd, (long)&range, (long)out, 1, 0, 0);
    CHECK("cachestat_bad_flags", r == -1 && errno == EINVAL, "r=%ld errno=%d", r, errno);
    r = raw(NR_CACHESTAT, 9999, (long)&range, (long)out, 0, 0, 0);
    CHECK("cachestat_bad_fd", r == -1 && errno == EBADF, "r=%ld errno=%d", r, errno);
    r = raw(NR_CACHESTAT, fd, 0, (long)out, 0, 0, 0);
    CHECK("cachestat_fault_range", r == -1 && errno == EFAULT, "r=%ld errno=%d", r, errno);
    close(fd);
    unlink("/tmp/sysmore.cachestat");
}

int main(void)
{
    alarm(60);
    pgetevents_checks();
    requeue_checks();
    cachestat_checks();
    return 0;
}
