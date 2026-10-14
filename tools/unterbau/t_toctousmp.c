/* SMP races of the user-space facing copy paths (r721; docs/SECURITY-TOCTOU-KERNEL.md). Meaningful at -smp 4 with `smpfrueh`
 * (tools/toctousmp/run.sh); at one core it only proves the paths still work.
 *  - scratch: four threads, each with its own socketpair, write a pattern and read it back. The kernel's bounce buffer for
 *    sockets (WL_SCRATCH) is one page for the machine: without the lock the octets of two cores mix.
 *  - mm: a reader thread read()s into a page that another thread unmaps, while a third keeps mapping, filling and checking fresh
 *    pages. Without the MM lock the kernel can copy into a frame that `munmap` already gave back (and somebody else owns). */
#define TNAME "toctousmp"
#include "t.h"
#include <fcntl.h>
#include <pthread.h>
#include <stdint.h>
#include <sys/mman.h>
#include <sys/socket.h>
#include <time.h>

#define NT 4
#define MSG 1900
static volatile int stop;
static volatile unsigned long bad_scratch, rounds_scratch, bad_mm, rounds_mm, faults_mm;
static double now(void);

static void *scratch_worker(void *arg)
{
    long id = (long)arg;
    int sv[2];
    if (socketpair(AF_UNIX, SOCK_STREAM, 0, sv) != 0) return (void *)1;
    unsigned char out[MSG], in[MSG];
    memset(out, (int)(0x31 + id), sizeof out);
    while (!stop) {
        if (write(sv[0], out, MSG) != MSG) { __sync_fetch_and_add(&bad_scratch, 1000); break; }
        int got = 0;
        while (got < MSG) {
            ssize_t n = read(sv[1], in + got, MSG - got);
            if (n <= 0) { __sync_fetch_and_add(&bad_scratch, 1000); return 0; }
            got += (int)n;
        }
        for (int k = 0; k < MSG; k++)
            if (in[k] != out[0]) { __sync_fetch_and_add(&bad_scratch, 1); break; }
        __sync_fetch_and_add(&rounds_scratch, 1);
    }
    close(sv[0]); close(sv[1]);
    return 0;
}

static int pfd[2];
static volatile unsigned char *volatile cur;

static void *producer(void *arg)
{
    (void)arg;
    unsigned char buf[4096];
    memset(buf, 0xAA, sizeof buf);
    while (!stop) { (void)write(pfd[1], buf, sizeof buf); } /* non-blocking: EAGAIN when full */
    return 0;
}
static void *reader(void *arg)
{
    (void)arg;
    while (!stop) {
        volatile unsigned char *q = cur;
        if (q) { if (read(pfd[0], (void *)q, 4096) < 0 && errno != EAGAIN) __sync_fetch_and_add(&faults_mm, 1); }
    }
    return 0;
}
/* ONE thread maps and unmaps (two threads racing in mmap/munmap is a different question): it hands page p to the reader, takes it
 * back after a short random delay (so the unmap lands inside the reader's copy) and maps a fresh page q, which usually gets
 * the frame just given back. A late copy of the reader into the old frame shows up as a changed octet in q. */
static void mm_cycle(double secs)
{
    unsigned rnd = 12345;
    double t0 = now();
    while (now() - t0 < secs) {
        for (int it = 0; it < 200; it++) {
            unsigned char *p = mmap(0, 4096, PROT_READ | PROT_WRITE, MAP_PRIVATE | MAP_ANONYMOUS, -1, 0);
            if (p == MAP_FAILED) continue;
            *(volatile unsigned char *)p = 1;
            cur = p;
            rnd = rnd * 1103515245u + 12345u;
            for (volatile unsigned d = 0; d < ((rnd >> 8) & 1023); d++) { }
            cur = 0;
            munmap(p, 4096);
            unsigned char *q = mmap(0, 4096, PROT_READ | PROT_WRITE, MAP_PRIVATE | MAP_ANONYMOUS, -1, 0);
            if (q == MAP_FAILED) continue;
            memset(q, 0x55, 4096);
            for (volatile int d = 0; d < 100; d++) { }
            for (int k = 0; k < 4096; k++)
                if (q[k] != 0x55) { __sync_fetch_and_add(&bad_mm, 1); break; }
            munmap(q, 4096);
            rounds_mm++;
        }
    }
}

static double now(void)
{
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return ts.tv_sec + ts.tv_nsec / 1e9;
}

int main(void)
{
    int secs = 6;
    pthread_t th[NT];
    int started = 0;

    /* phase 1: scratch */
    stop = 0;
    for (long i = 0; i < NT; i++) if (pthread_create(&th[i], 0, scratch_worker, (void *)i) == 0) started++;
    double t0 = now();
    while (now() - t0 < secs) { struct timespec ts = {0, 100 * 1000 * 1000}; nanosleep(&ts, 0); }
    stop = 1;
    for (int i = 0; i < started; i++) pthread_join(th[i], 0);
    CHECK("scratch_workers_started", started == NT, "started=%d", started);
    CHECK("scratch_rounds", rounds_scratch > 100, "rounds=%lu", rounds_scratch);
    CHECK("scratch_no_mixing", bad_scratch == 0, "bad=%lu of %lu rounds", bad_scratch, rounds_scratch);

    /* phase 2: translate vs munmap */
    if (pipe2(pfd, O_NONBLOCK) != 0) { FAIL("mm_pipe", "errno=%d", errno); return 0; }
    stop = 0;
    pthread_t a, b;
    int ok = pthread_create(&a, 0, producer, 0) == 0 && pthread_create(&b, 0, reader, 0) == 0;
    if (ok) mm_cycle(secs);
    stop = 1;
    if (ok) { pthread_join(b, 0); pthread_join(a, 0); }
    CHECK("mm_threads_started", ok, "ok=%d", ok);
    CHECK("mm_rounds", rounds_mm > 100, "rounds=%lu", rounds_mm);
    CHECK("mm_no_stale_write", bad_mm == 0, "bad=%lu of %lu rounds (reader faults %lu)", bad_mm, rounds_mm, faults_mm);
    return 0;
}
