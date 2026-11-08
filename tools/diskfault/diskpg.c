#define _GNU_SOURCE
#include <fcntl.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mman.h>
#include <time.h>
#include <unistd.h>

#define PAGE 4096UL
#define MAP_PAGES 4096UL
#define SAMPLE_PAGES 1024UL
#define LCG_MUL 6364136223846793005ULL
#define LCG_ADD 1442695040888963407ULL

static unsigned long long clock_ns(void)
{
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return (unsigned long long)ts.tv_sec * 1000000000ULL + (unsigned long long)ts.tv_nsec;
}

static unsigned long long rng_state = 88172645463325252ULL;

static unsigned long rng_page(unsigned long pages)
{
    rng_state = rng_state * LCG_MUL + LCG_ADD;
    return (unsigned long)((rng_state >> 33) % pages);
}

static void blk_counters(const char *tag)
{
    char buf[2048];
    int fd = open("/proc/bench", O_RDONLY);
    if (fd < 0) return;
    int n = read(fd, buf, sizeof buf - 1);
    close(fd);
    if (n <= 0) return;
    buf[n] = 0;
    for (char *line = strtok(buf, "\n"); line; line = strtok(0, "\n"))
        if (!strncmp(line, "blk.", 4)) printf("DPC %s %s\n", tag, line);
    fflush(stdout);
}

static void report(const char *phase, unsigned long pages, unsigned long long ns)
{
    printf("DP %s pages=%lu total_us=%llu ns_per_page=%llu\n", phase, pages, ns / 1000, pages ? ns / pages : 0);
    fflush(stdout);
}

static void phase_map(const char *path, int random, const char *name)
{
    int fd = open(path, O_RDONLY);
    if (fd < 0) { printf("DP %s open-failed\n", name); return; }
    volatile unsigned char *m = mmap(0, MAP_PAGES * PAGE, PROT_READ, MAP_PRIVATE, fd, 0);
    if (m == MAP_FAILED) { printf("DP %s mmap-failed\n", name); close(fd); return; }
    unsigned long count = random ? SAMPLE_PAGES : MAP_PAGES;
    blk_counters(name);
    unsigned long long t0 = clock_ns();
    unsigned long sum = 0;
    for (unsigned long i = 0; i < count; i++)
        sum += m[(random ? rng_page(MAP_PAGES) : i) * PAGE];
    unsigned long long t1 = clock_ns();
    report(name, count, t1 - t0);
    blk_counters(name);
    if (sum == 0xFFFFFFFFUL) printf("x");
    munmap((void *)m, MAP_PAGES * PAGE);
    close(fd);
}

static void phase_read(const char *path, int random, const char *name)
{
    int fd = open(path, O_RDONLY);
    char *buf = malloc(PAGE);
    if (fd < 0 || !buf) { printf("DP %s open-failed\n", name); return; }
    unsigned long count = random ? SAMPLE_PAGES : MAP_PAGES;
    blk_counters(name);
    unsigned long long t0 = clock_ns();
    for (unsigned long i = 0; i < count; i++) {
        unsigned long pg = random ? rng_page(MAP_PAGES) : i;
        if (pread(fd, buf, PAGE, pg * PAGE) != (long)PAGE) { printf("DP %s short-read\n", name); break; }
    }
    unsigned long long t1 = clock_ns();
    report(name, count, t1 - t0);
    blk_counters(name);
    free(buf);
    close(fd);
}

int main(void)
{
    printf("DP begin\n");
    blk_counters("start");
    phase_map("/d/seq.dat", 0, "map_seq");
    phase_map("/d/seq.dat", 0, "map_seq_warm");
    phase_map("/d/rnd.dat", 1, "map_rnd");
    phase_read("/d/rd.dat", 0, "read_seq");
    phase_read("/d/prd.dat", 1, "read_rnd");
    printf("DP end\n");
    return 0;
}
