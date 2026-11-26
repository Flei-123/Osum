#define TNAME "execfilerace"
#include "t.h"
#include <fcntl.h>
#include <pthread.h>
#include <sched.h>
#include <signal.h>
#include <stdint.h>
#include <stdlib.h>
#include <sys/mman.h>
#include <time.h>

#define PG 4096
#define NP 24
#define NT 3
#define FILE_PAGES 64
#define NOISE_PAGES 4
#ifndef RUN_SECONDS
#define RUN_SECONDS 8
#endif
#define MIN_ROUNDS 50
#define PATH "/tmp/execfilerace.dat"
#define RET_OPCODE 0xC3

typedef void (*entry_fn)(void);

static volatile int stop;
static volatile unsigned long rounds;
static unsigned char *page_addr[NP];
static unsigned long arrivals[NP];
static pthread_barrier_t round_start;
static pthread_barrier_t round_end;

static void on_segv(int sig, siginfo_t *si, void *ctx)
{
    (void)sig;
    (void)ctx;
    t_emit("no_fetch_fault", "FAIL", "SIGSEGV addr=%p round=%lu", si->si_addr, rounds);
    _exit(3);
}

static int make_file(void)
{
    unsigned char page[PG];
    memset(page, RET_OPCODE, sizeof page);
    unlink(PATH);
    int fd = open(PATH, O_RDWR | O_CREAT | O_TRUNC, 0700);
    if (fd < 0) return -1;
    for (int p = 0; p < FILE_PAGES; p++) {
        if (write(fd, page, PG) != PG) { close(fd); return -1; }
    }
    return fd;
}

static int map_round(int fd)
{
    for (int v = 0; v < NP; v++) {
        long file_page = (v * 5 + 3) % FILE_PAGES;
        page_addr[v] = mmap(0, PG, PROT_READ | PROT_EXEC, MAP_PRIVATE, fd, file_page * PG);
        if (page_addr[v] == MAP_FAILED) return 0;
        arrivals[v] = 0;
    }
    return 1;
}

static void unmap_round(void)
{
    for (int v = 0; v < NP; v++) munmap(page_addr[v], PG);
}

static void *worker(void *arg)
{
    long id = (long)arg;
    while (1) {
        pthread_barrier_wait(&round_start);
        if (stop) return 0;
        for (int v = 0; v < NP; v++) {
            __atomic_add_fetch(&arrivals[v], 1, __ATOMIC_SEQ_CST);
            while (__atomic_load_n(&arrivals[v], __ATOMIC_SEQ_CST) < NT) __builtin_ia32_pause();
            ((entry_fn)(page_addr[v] + ((v * 37 + id * 11) & 0x7FF)))();
        }
        pthread_barrier_wait(&round_end);
    }
}

static void *noise(void *arg)
{
    (void)arg;
    unsigned char *r = mmap(0, NOISE_PAGES * PG, PROT_READ | PROT_WRITE, MAP_PRIVATE | MAP_ANONYMOUS, -1, 0);
    if (r == MAP_FAILED) return 0;
    r[0] = 1;
    while (!stop) {
        mprotect(r, PG, PROT_READ);
        mprotect(r, PG, PROT_READ | PROT_WRITE);
    }
    return 0;
}

int main(void)
{
    struct sigaction sa;
    memset(&sa, 0, sizeof sa);
    sa.sa_sigaction = on_segv;
    sa.sa_flags = SA_SIGINFO;
    sigaction(SIGSEGV, &sa, 0);
    int fd = make_file();
    CHECK("file_ready", fd >= 0, "errno=%d", errno);
    if (fd < 0) return 1;
    pthread_barrier_init(&round_start, 0, NT + 1);
    pthread_barrier_init(&round_end, 0, NT + 1);
    pthread_t th[NT];
    pthread_t noisy;
    int started = 0;
    for (long i = 0; i < NT; i++) if (pthread_create(&th[i], 0, worker, (void *)i) == 0) started++;
    int noise_ok = pthread_create(&noisy, 0, noise, 0) == 0;
    CHECK("threads_started", started == NT && noise_ok, "started=%d noise=%d", started, noise_ok);
    if (started != NT) return 1;
    struct timespec t0, t1;
    clock_gettime(CLOCK_MONOTONIC, &t0);
    int map_failed = 0;
    do {
        if (!map_round(fd)) { map_failed = 1; break; }
        pthread_barrier_wait(&round_start);
        pthread_barrier_wait(&round_end);
        unmap_round();
        rounds++;
        clock_gettime(CLOCK_MONOTONIC, &t1);
    } while (t1.tv_sec - t0.tv_sec < RUN_SECONDS);
    stop = 1;
    pthread_barrier_wait(&round_start);
    for (int i = 0; i < started; i++) pthread_join(th[i], 0);
    if (noise_ok) pthread_join(noisy, 0);
    unlink(PATH);
    CHECK("map_ok", !map_failed, "errno=%d", errno);
    if (rounds >= MIN_ROUNDS) PASS("rounds", "rounds=%lu", rounds); else FAIL("rounds", "rounds=%lu", rounds);
    PASS("no_fetch_fault", "rounds=%lu", rounds);
    return 0;
}
