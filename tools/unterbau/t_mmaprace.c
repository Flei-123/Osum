/* mmap/munmap from several threads of ONE process at the same time (r721 follow-up). Meaningful at -smp 4 with `smpfrueh`.
 * Each thread maps a few pages, writes a tag of its own into every page, gives other threads time to run, checks the tags and unmaps.
 * Without a lock around the address allocator two threads read the same bump mark: they get the SAME pages (tags overwritten ->
 * `bad`), or one unmaps what the other still uses (user fault -> the process dies, the check is then missing). */
#define TNAME "mmaprace"
#include "t.h"
#include <pthread.h>
#include <sched.h>
#include <stdint.h>
#include <sys/mman.h>
#include <time.h>

#define NT 4
#define PAGES 3
static volatile int stop;
static volatile unsigned long rounds, bad, failed_maps;

static void *worker(void *arg)
{
    unsigned long id = (unsigned long)arg + 1;
    while (!stop) {
        unsigned char *p = mmap(0, PAGES * 4096, PROT_READ | PROT_WRITE, MAP_PRIVATE | MAP_ANONYMOUS, -1, 0);
        if (p == MAP_FAILED) { __sync_fetch_and_add(&failed_maps, 1); sched_yield(); continue; }
        for (int k = 0; k < PAGES; k++) p[k * 4096] = (unsigned char)(0x10 * id + k);
        for (int spin = 0; spin < 200; spin++) __asm__ volatile("pause");
        int wrong = 0;
        for (int k = 0; k < PAGES; k++) if (p[k * 4096] != (unsigned char)(0x10 * id + k)) wrong = 1;
        if (wrong) __sync_fetch_and_add(&bad, 1);
        munmap(p, PAGES * 4096);
        __sync_fetch_and_add(&rounds, 1);
    }
    return 0;
}

int main(void)
{
    pthread_t th[NT];
    int started = 0;
    for (long i = 0; i < NT; i++) if (pthread_create(&th[i], 0, worker, (void *)i) == 0) started++;
    struct timespec t0, t1;
    clock_gettime(CLOCK_MONOTONIC, &t0);
    do {
        struct timespec ts = {0, 100 * 1000 * 1000};
        nanosleep(&ts, 0);
        clock_gettime(CLOCK_MONOTONIC, &t1);
    } while (t1.tv_sec - t0.tv_sec < 6);
    stop = 1;
    for (int i = 0; i < started; i++) pthread_join(th[i], 0);
    CHECK("threads_started", started == NT, "started=%d", started);
    CHECK("rounds", rounds > 100, "rounds=%lu", rounds);
    CHECK("no_shared_pages", bad == 0, "bad=%lu of %lu rounds", bad, rounds);
    CHECK("no_failed_maps", failed_maps == 0, "failed=%lu", failed_maps);
    return 0;
}
