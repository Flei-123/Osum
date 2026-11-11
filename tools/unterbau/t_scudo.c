/* allocator-style address space use (scudo primary/secondary): NORESERVE PROT_NONE reservation, MAP_FIXED commit, MADV_DONTNEED release, guard pages, several threads, fork. */
#define TNAME "scudo"
#include "t.h"
#include <pthread.h>
#include <sched.h>
#include <stdint.h>
#include <stdlib.h>
#include <sys/mman.h>
#include <sys/wait.h>
#include <time.h>

#define PG 4096UL
#define MIB (1024UL * 1024UL)
#define RESERVE (256UL * MIB)
#define SLOT (64UL * PG)
#define NT 4
#define ROUNDS 300

static unsigned char *region;
static volatile int stop, bad_pattern, bad_zero, bad_other;

static int fill_ok(unsigned char *p, size_t n, unsigned char v)
{
    for (size_t i = 0; i < n; i += 61) if (p[i] != v) return 0;
    return p[n - 1] == v;
}

static int zero_ok(unsigned char *p, size_t n)
{
    for (size_t i = 0; i < n; i += 61) if (p[i]) return 0;
    return p[n - 1] == 0;
}

static void *slot_worker(void *arg)
{
    unsigned long id = (unsigned long)arg;
    unsigned char *s = region + id * SLOT;
    for (int r = 0; r < ROUNDS && !stop; r++) {
        unsigned char v = (unsigned char)(id * 16 + (r % 13) + 1);
        if (mmap(s, SLOT, PROT_READ | PROT_WRITE, MAP_FIXED | MAP_PRIVATE | MAP_ANONYMOUS, -1, 0) == MAP_FAILED) { bad_other++; continue; }
        memset(s, v, SLOT);
        if (!fill_ok(s, SLOT, v)) bad_pattern++;
        sched_yield();
        if (madvise(s, SLOT, MADV_DONTNEED)) bad_other++;
        if (!zero_ok(s, SLOT)) bad_zero++;
        memset(s, v, SLOT / 2);
        if (!fill_ok(s, SLOT / 2, v)) bad_pattern++;
        if (r % 7 == 0 && mprotect(s, PG, PROT_NONE)) bad_other++;
        if (r % 7 == 0 && mprotect(s, PG, PROT_READ | PROT_WRITE)) bad_other++;
    }
    return 0;
}

static void *churn_worker(void *arg)
{
    (void)arg;
    while (!stop) {
        unsigned char *p = mmap(0, 8 * PG, PROT_READ | PROT_WRITE, MAP_PRIVATE | MAP_ANONYMOUS, -1, 0);
        if (p == MAP_FAILED) { bad_other++; continue; }
        for (int k = 0; k < 8; k++) p[k * PG] = 0x5a;
        madvise(p, 8 * PG, MADV_DONTNEED);
        if (p[3 * PG]) bad_zero++;
        munmap(p, 8 * PG);
    }
    return 0;
}

int main(void)
{
    region = mmap(0, RESERVE, PROT_NONE, MAP_PRIVATE | MAP_ANONYMOUS | MAP_NORESERVE, -1, 0);
    CHECKC("reserve_noreserve", region != MAP_FAILED);
    if (region == MAP_FAILED) return 0;

    unsigned char *c = region + 100 * SLOT;
    int r = mprotect(c, 4 * PG, PROT_READ | PROT_WRITE);
    CHECKC("commit_by_mprotect", r == 0);
    if (r == 0) {
        memset(c, 0x33, 4 * PG);
        r = madvise(c, 4 * PG, MADV_DONTNEED);
        CHECK("mprotect_commit_release_zero", r == 0 && zero_ok(c, 4 * PG), "pages not zero after DONTNEED on mprotect-committed span");
        CHECKC("guard_prot_none", mprotect(c + 4 * PG, PG, PROT_NONE) == 0);
    }

    void *m = mmap(c, 2 * PG, PROT_READ | PROT_WRITE, MAP_FIXED | MAP_PRIVATE | MAP_ANONYMOUS, -1, 0);
    CHECK("fixed_over_committed", m == c && zero_ok(c, 2 * PG), "MAP_FIXED over committed pages did not give a zero span");
    c[0] = 9;
    void *m2 = mmap(c + 4 * PG, PG, PROT_READ | PROT_WRITE, MAP_FIXED | MAP_PRIVATE | MAP_ANONYMOUS, -1, 0);
    CHECK("fixed_over_guard", m2 == c + 4 * PG && c[0] == 9 && zero_ok(c + 4 * PG, PG), "MAP_FIXED over a PROT_NONE guard broke the neighbour");

    pthread_t th[NT + 1];
    for (long i = 0; i < NT; i++) pthread_create(&th[i], 0, slot_worker, (void *)i);
    pthread_create(&th[NT], 0, churn_worker, 0);
    for (int i = 0; i < NT; i++) pthread_join(th[i], 0);
    stop = 1;
    pthread_join(th[NT], 0);
    CHECK("threads_pattern", bad_pattern == 0, "%d slots lost their pattern", bad_pattern);
    CHECK("threads_zero_after_release", bad_zero == 0, "%d spans not zero after MADV_DONTNEED", bad_zero);
    CHECK("threads_calls", bad_other == 0, "%d mmap/madvise/mprotect calls failed", bad_other);

    unsigned char *f = region + 120 * SLOT;
    mmap(f, SLOT, PROT_READ | PROT_WRITE, MAP_FIXED | MAP_PRIVATE | MAP_ANONYMOUS, -1, 0);
    memset(f, 0x77, SLOT);
    int bad_child = 0;
    for (int i = 0; i < 20; i++) {
        pid_t pid = fork();
        if (pid == 0) {
            f[PG * (i % 8)] = 0x11;
            madvise(f, SLOT, MADV_DONTNEED);
            _exit(zero_ok(f, SLOT) ? 0 : 1);
        }
        int st = 0;
        waitpid(pid, &st, 0);
        if (!WIFEXITED(st) || WEXITSTATUS(st)) bad_child++;
        madvise(f + 32 * PG, 4 * PG, MADV_DONTNEED);
        memset(f + 32 * PG, 0x77, 4 * PG);
    }
    CHECK("fork_release_child", bad_child == 0, "%d children saw non-zero pages after DONTNEED", bad_child);
    CHECK("fork_parent_intact", fill_ok(f, 32 * PG, 0x77), "parent lost data after children released their copy");
    CHECKC("release_all", munmap(region, RESERVE) == 0);
    return 0;
}
