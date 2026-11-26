#define TNAME "lostwrite"
#include "t.h"
#include <pthread.h>
#include <stdint.h>
#include <stdlib.h>
#include <sys/mman.h>
#include <sys/wait.h>
#include <time.h>

#define PG 4096
#define SLOT 16
#define SLOTS_PER_PAGE (PG / SLOT)
#define WORKERS 3
#define HOT_PAGES 32
#define HOT_REGIONS 2
#define COLD_PAGES 16384
#define SWEEP_PAGES 1200
#define SLOTS_PER_WORKER (SLOTS_PER_PAGE / WORKERS)
#define RUN_SECONDS 30
#define MIN_FORKS 100
#define CHILD_SPIN_NS 150000

struct hdr { uint64_t a, b; };

struct worker {
    int id;
    long epochs;
    long lost;
    char first[200];
};

static unsigned char *hot[HOT_REGIONS];
static unsigned char *cold;
static volatile int stop;
static volatile long forks;

static long now_ns(void)
{
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return ts.tv_sec * 1000000000L + ts.tv_nsec;
}

static struct hdr pattern(long gen, int worker, int page, int slot)
{
    uint64_t x = 0x9E3779B97F4A7C15ull * (uint64_t)(gen + 1) ^ ((uint64_t)worker << 56) ^ ((uint64_t)page << 32) ^ ((uint64_t)slot << 16) ^ 0xA5A5;
    struct hdr h = { x | 1, ~x };
    return h;
}

static volatile struct hdr *slot_at(int page_index, int slot)
{
    unsigned char *base = hot[page_index / HOT_PAGES] + (size_t)(page_index % HOT_PAGES) * PG;
    return (volatile struct hdr *)(base + (size_t)slot * SLOT);
}

static void write_epoch(struct worker *w, long epoch)
{
    long gen = epoch / SLOTS_PER_WORKER;
    int j = (int)(epoch % SLOTS_PER_WORKER);
    int s = w->id + WORKERS * j;
    for (int p = 0; p < HOT_PAGES * HOT_REGIONS; p++) {
        struct hdr h = pattern(gen, w->id, p, s);
        volatile struct hdr *dst = slot_at(p, s);
        dst->a = h.a;
        dst->b = h.b;
    }
}

static int verify_epoch(struct worker *w, long epoch)
{
    long gen = epoch / SLOTS_PER_WORKER;
    int k = (int)(epoch % SLOTS_PER_WORKER);
    int bad = 0;
    for (int p = 0; p < HOT_PAGES * HOT_REGIONS; p++) {
        for (int j = 0; j < SLOTS_PER_WORKER; j++) {
            int s = w->id + WORKERS * j;
            long g = j <= k ? gen : gen - 1;
            struct hdr want = { 0, 0 };
            if (g >= 0)
                want = pattern(g, w->id, p, s);
            volatile struct hdr *src = slot_at(p, s);
            uint64_t a = src->a, b = src->b;
            if (a != want.a || b != want.b) {
                if (!bad)
                    snprintf(w->first, sizeof w->first, "worker=%d page=%d slot=%d epoch=%ld got=%llx/%llx want=%llx/%llx",
                        w->id, p, s, epoch, (unsigned long long)a, (unsigned long long)b, (unsigned long long)want.a, (unsigned long long)want.b);
                bad++;
            }
        }
    }
    return bad;
}

static unsigned long sweep(unsigned long offset)
{
    unsigned long sum = 0;
    for (int i = 0; i < SWEEP_PAGES; i++)
        sum += ((volatile unsigned char *)cold)[(((offset + (unsigned long)i * 7) % COLD_PAGES)) * PG];
    return sum;
}

static void *worker_main(void *arg)
{
    struct worker *w = arg;
    unsigned long off = (unsigned long)w->id * 977;
    long epoch = 0;
    while (!stop) {
        write_epoch(w, epoch);
        if (w->id == 0)
            off += sweep(off) & 1023;
        int bad = verify_epoch(w, epoch);
        if (bad) {
            w->lost += bad;
            stop = 1;
            break;
        }
        epoch++;
        w->epochs = epoch;
    }
    return NULL;
}


#define FT_PAGES 2048
#define FT_ROUNDS 60
#define FT_OFFSET 3072

struct ft_arg {
    int id;
    unsigned char *base;
};

static void *ft_worker(void *arg)
{
    struct ft_arg *a = arg;
    for (int p = 0; p < FT_PAGES; p++) {
        struct hdr h = pattern(1, a->id, p, a->id);
        volatile struct hdr *dst = (volatile struct hdr *)(a->base + (size_t)p * PG + FT_OFFSET + (size_t)a->id * SLOT);
        dst->a = h.a;
        dst->b = h.b;
    }
    return NULL;
}

static long first_touch_race(char *first, size_t first_len)
{
    long lost = 0;
    for (int round = 0; round < FT_ROUNDS && !lost; round++) {
        unsigned char *base = mmap(NULL, (size_t)FT_PAGES * PG, PROT_READ | PROT_WRITE, MAP_PRIVATE | MAP_ANONYMOUS, -1, 0);
        if (base == MAP_FAILED)
            return -1;
        pthread_t th[WORKERS];
        struct ft_arg args[WORKERS];
        for (int i = 0; i < WORKERS; i++) {
            args[i] = (struct ft_arg){ .id = i, .base = base };
            pthread_create(&th[i], NULL, ft_worker, &args[i]);
        }
        for (int i = 0; i < WORKERS; i++)
            pthread_join(th[i], NULL);
        for (int p = 0; p < FT_PAGES; p++) {
            for (int id = 0; id < WORKERS; id++) {
                struct hdr want = pattern(1, id, p, id);
                volatile struct hdr *src = (volatile struct hdr *)(base + (size_t)p * PG + FT_OFFSET + (size_t)id * SLOT);
                if (src->a != want.a || src->b != want.b) {
                    if (!lost)
                        snprintf(first, first_len, "round=%d page=%d worker=%d got=%llx want=%llx", round, p, id, (unsigned long long)src->a, (unsigned long long)want.a);
                    lost++;
                }
            }
        }
        munmap(base, (size_t)FT_PAGES * PG);
    }
    return lost;
}

static void child_work(void)
{
    for (int r = 0; r < HOT_REGIONS; r++)
        hot[r][0] ^= 1;
    long t0 = now_ns();
    while (now_ns() - t0 < CHILD_SPIN_NS)
        ;
    _exit(0);
}

static int setup(void)
{
    cold = mmap(NULL, (size_t)COLD_PAGES * PG, PROT_READ | PROT_WRITE, MAP_PRIVATE | MAP_ANONYMOUS, -1, 0);
    if (cold == MAP_FAILED)
        return 0;
    for (long i = 0; i < COLD_PAGES; i++)
        cold[i * PG] = 1;
    for (int r = 0; r < HOT_REGIONS; r++) {
        hot[r] = mmap(NULL, (size_t)HOT_PAGES * PG, PROT_READ | PROT_WRITE, MAP_PRIVATE | MAP_ANONYMOUS, -1, 0);
        if (hot[r] == MAP_FAILED)
            return 0;
        for (int p = 0; p < HOT_PAGES; p++)
            hot[r][(size_t)p * PG + 8] = 0;
    }
    return 1;
}

int main(void)
{
    struct worker workers[WORKERS];
    pthread_t threads[WORKERS];
    char ft_first[160] = "";
    long ft_lost = first_touch_race(ft_first, sizeof ft_first);
    CHECK("first_touch", ft_lost == 0, "lost=%ld %s", ft_lost, ft_first);
    if (!setup()) {
        FAIL("setup", "mmap failed");
        return 0;
    }
    for (int i = 0; i < WORKERS; i++) {
        workers[i] = (struct worker){ .id = i };
        pthread_create(&threads[i], NULL, worker_main, &workers[i]);
    }
    long t0 = now_ns();
    while (!stop && now_ns() - t0 < (long)RUN_SECONDS * 1000000000L) {
        pid_t pid = fork();
        if (pid == 0)
            child_work();
        if (pid < 0)
            break;
        int st = 0;
        waitpid(pid, &st, 0);
        forks++;
    }
    stop = 1;
    long epochs = 0, lost = 0;
    const char *first = "";
    for (int i = 0; i < WORKERS; i++) {
        pthread_join(threads[i], NULL);
        epochs += workers[i].epochs;
        lost += workers[i].lost;
        if (workers[i].lost && !*first)
            first = workers[i].first;
    }
    CHECK("fork_threads", lost == 0 && forks >= MIN_FORKS, "lost=%ld forks=%ld epochs=%ld %s", lost, (long)forks, epochs, first);
    return 0;
}
