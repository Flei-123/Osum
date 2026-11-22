/* SPDX-License-Identifier: GPL-2.0-only */
#define TNAME "tlbshoot"
#include "t.h"
#include <pthread.h>
#include <setjmp.h>
#include <signal.h>
#include <stdint.h>
#include <sys/mman.h>
#include <sys/syscall.h>
#include <time.h>

#define PG 4096ul
#define ROUNDS 20
#define WAIT_NS 200000000l

enum { OP_DONTNEED, OP_REMAP, OP_PROTECT };

static volatile uint64_t *page;
static volatile uint64_t seen;
static volatile int phase;
static volatile int faulted;
static volatile int reader_cpu = -1;
static sigjmp_buf jb;

static long now_ns(void)
{
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return ts.tv_sec * 1000000000l + ts.tv_nsec;
}

static int cur_cpu(void)
{
    unsigned cpu = 0;
    if (syscall(SYS_getcpu, &cpu, 0, 0) != 0) return -1;
    return (int)cpu;
}

static void on_segv(int sig)
{
    (void)sig;
    faulted = 1;
    siglongjmp(jb, 1);
}

static void *reader(void *arg)
{
    static volatile int op;
    op = (int)(intptr_t)arg;
    reader_cpu = cur_cpu();
    sigsetjmp(jb, 1);
    if (op == OP_PROTECT) {
        if (faulted) return 0;
        uint64_t n = 1;
        while (phase < 2) {
            page[1] = n++;
            seen = page[0];
            phase = phase < 1 ? 1 : phase;
        }
        return 0;
    }
    while (phase < 2) {
        seen = page[0];
        if (seen == 7 && phase == 0) phase = 1;
    }
    return 0;
}

static int wait_for(volatile uint64_t *v, uint64_t want)
{
    long end = now_ns() + WAIT_NS;
    while (now_ns() < end)
        if (*v == want) return 1;
    return 0;
}

static int wait_flag(volatile int *v)
{
    long end = now_ns() + WAIT_NS;
    while (now_ns() < end)
        if (*v) return 1;
    return 0;
}

static void apply(int op, void *p)
{
    if (op == OP_DONTNEED) {
        madvise(p, PG, MADV_DONTNEED);
    } else if (op == OP_REMAP) {
        munmap(p, PG);
        mmap(p, PG, PROT_READ | PROT_WRITE, MAP_PRIVATE | MAP_ANONYMOUS | MAP_FIXED, -1, 0);
    } else {
        mprotect(p, PG, PROT_READ);
    }
}

static int one_round(int op, int *cross)
{
    void *p = mmap(0, PG, PROT_READ | PROT_WRITE, MAP_PRIVATE | MAP_ANONYMOUS, -1, 0);
    if (p == MAP_FAILED) return -1;
    page = p;
    page[0] = 7;
    seen = 0;
    phase = 0;
    faulted = 0;
    reader_cpu = -1;
    pthread_t th;
    if (pthread_create(&th, 0, reader, (void *)(intptr_t)op) != 0) {
        munmap(p, PG);
        return -1;
    }
    long end = now_ns() + 5 * WAIT_NS;
    while (phase == 0 && now_ns() < end) { }
    int ok = 1;
    if (phase == 0) ok = 0;
    if (reader_cpu >= 0 && reader_cpu != cur_cpu()) (*cross)++;
    apply(op, p);
    if (op == OP_PROTECT) {
        ok = ok && wait_flag(&faulted);
    } else {
        if (page[0] != 0) ok = 0;
        page[0] = 42;
        ok = ok && wait_for(&seen, 42);
    }
    phase = 2;
    pthread_join(th, 0);
    munmap(p, PG);
    return ok;
}

static void run_op(const char *name, int op)
{
    int stale = 0, cross = 0, err = 0;
    for (int r = 0; r < ROUNDS; r++) {
        int v = one_round(op, &cross);
        if (v < 0) err++;
        else if (v == 0) stale++;
    }
    CHECK(name, stale == 0 && err == 0, "stale %d of %d rounds, errors %d, cross-cpu rounds %d", stale, ROUNDS, err, cross);
}

int main(void)
{
    struct sigaction sa = { 0 };
    sa.sa_handler = on_segv;
    sigaction(SIGSEGV, &sa, 0);
    run_op("dontneed_seen_by_other_cpu", OP_DONTNEED);
    run_op("remap_seen_by_other_cpu", OP_REMAP);
    run_op("protect_seen_by_other_cpu", OP_PROTECT);
    long n = sysconf(_SC_NPROCESSORS_ONLN);
    CHECK("cpus_online", n > 1, "only %ld cpu online", n);
    return 0;
}
