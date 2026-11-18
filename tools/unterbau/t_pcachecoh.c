#define TNAME "pcachecoh"
#include "t.h"
#include <fcntl.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

#define PG 4096
#define PATH "/tmp/pcachecoh.dat"
#define BIG_SIZE (512 * 1024)
#define HUGE_SIZE (900 * 1024)
#define LOOPS 2000
#define WRITE_BUDGET_US 300

static unsigned char pat(long pos, int seed)
{
    return (unsigned char)(pos * 7 + pos / 251 + seed);
}

static int put(int fd, long from, long n, int seed)
{
    unsigned char *b = malloc(n);
    for (long i = 0; i < n; i++) b[i] = pat(from + i, seed);
    long w = pwrite(fd, b, n, from);
    free(b);
    return w == n;
}

static int zero_run(int fd, long from, long n)
{
    unsigned char *b = malloc(n);
    long r = pread(fd, b, n, from);
    int ok = r == n;
    for (long i = 0; ok && i < n; i++) ok = b[i] == 0;
    free(b);
    return ok;
}

static int same(int fd, long from, long n, int seed)
{
    unsigned char *b = malloc(n);
    long r = pread(fd, b, n, from);
    int ok = r == n;
    for (long i = 0; ok && i < n; i++) ok = b[i] == pat(from + i, seed);
    free(b);
    return ok;
}

static void drain(int fd, long size)
{
    unsigned char *b = malloc(size);
    long r = pread(fd, b, size, 0);
    (void)r;
    free(b);
}

static long stat_of(const char *key)
{
    char buf[4096];
    int fd = open("/proc/vfscache", O_RDONLY);
    if (fd < 0) return -1;
    long n = read(fd, buf, sizeof buf - 1);
    close(fd);
    if (n <= 0) return -1;
    buf[n] = 0;
    char *at = strstr(buf, key);
    return at ? atol(at + strlen(key)) : -1;
}

static long now_us(void)
{
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return ts.tv_sec * 1000000L + ts.tv_nsec / 1000;
}

static int reopen(int fd)
{
    close(fd);
    return open(PATH, O_RDWR | O_CREAT | O_TRUNC, 0600);
}

int main(void)
{
    int fd = open(PATH, O_RDWR | O_CREAT | O_TRUNC, 0600);
    CHECKC("create", fd >= 0);
    if (fd < 0) return 1;

    CHECK("sparse_fill", put(fd, 0, 5000, 1), "short write");
    drain(fd, 5000);
    CHECK("sparse_write", put(fd, 20000, 10, 2), "short write");
    CHECK("sparse_hole_zero", zero_run(fd, 5000, 3192), "partial cached page survived a write past the end");
    CHECK("sparse_old_data", same(fd, 0, 5000, 1), "old data changed");

    fd = reopen(fd);
    CHECK("mid_fill", put(fd, 0, 16 * PG, 1), "short write");
    for (int p = 0; p < 16; p++) drain(fd, (p + 1) * PG);
    CHECK("mid_write_page", put(fd, 5 * PG, PG, 3), "short write");
    CHECK("mid_write_part", put(fd, 2 * PG + 8, 100, 4), "short write");
    CHECK("mid_page_before", same(fd, 4 * PG, PG, 1), "untouched page changed");
    CHECK("mid_page_written", same(fd, 5 * PG, PG, 3), "written page stale");
    CHECK("mid_page_after", same(fd, 6 * PG, PG, 1), "untouched page changed");
    CHECK("mid_part_written", same(fd, 2 * PG + 8, 100, 4), "partial write stale");
    CHECK("mid_part_edges", same(fd, 2 * PG, 8, 1) && same(fd, 2 * PG + 108, PG - 108, 1), "bytes around the partial write changed");

    fd = reopen(fd);
    CHECK("big_fill", put(fd, 0, BIG_SIZE, 1), "short write");
    drain(fd, BIG_SIZE);
    CHECK("big_write", put(fd, 300000, 10, 5), "short write");
    CHECK("big_read_before", same(fd, 0, 300000, 1), "data before the write changed");
    CHECK("big_read_written", same(fd, 300000, 10, 5), "written bytes stale");
    CHECK("big_read_after", same(fd, 300010, BIG_SIZE - 300010, 1), "data after the write changed");

    fd = reopen(fd);
    CHECK("huge_fill", put(fd, 0, HUGE_SIZE, 1), "short write");
    drain(fd, HUGE_SIZE);
    CHECK("huge_write", put(fd, HUGE_SIZE - 30, 30, 6), "short write");
    CHECK("huge_read", same(fd, 0, HUGE_SIZE - 30, 1) && same(fd, HUGE_SIZE - 30, 30, 6), "bulk read returned stale bytes");

    CHECK("range_drops", stat_of("pcache.drop.range ") > 0, "range drops %ld", stat_of("pcache.drop.range "));

    fd = reopen(fd);
    CHECK("trunc_fill", put(fd, 0, 10000, 1), "short write");
    drain(fd, 10000);
    CHECK("trunc_extend", ftruncate(fd, 20000) == 0, "ftruncate failed");
    CHECK("trunc_zero", zero_run(fd, 10000, 10000), "partial cached page survived the extension");

    fd = reopen(fd);
    CHECK("cost_fill", put(fd, 0, 4 * PG, 1), "short write");
    drain(fd, 4 * PG);
    char tiny[16] = {0};
    long t0 = now_us();
    for (int i = 0; i < LOOPS; i++) {
        if (pwrite(fd, tiny, sizeof tiny, 0) != sizeof tiny || pread(fd, tiny, sizeof tiny, 0) != sizeof tiny) break;
    }
    long per_op = (now_us() - t0) / LOOPS;
    t_emit("cost_us", per_op < WRITE_BUDGET_US ? "PASS" : "FAIL", "%ld us per write+read of a cached file, budget %d", per_op, WRITE_BUDGET_US);
    close(fd);
    unlink(PATH);
    return 0;
}
