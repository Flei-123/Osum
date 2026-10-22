/* File mapping cost: eager copy of mmap(MAP_PRIVATE, fd) against read() of the same bytes (LA-9 demand-paging baseline). Prints MiB/s in the detail field. */
#define TNAME "fmapbench"
#include "t.h"
#include <fcntl.h>
#include <unistd.h>
#include <stdlib.h>
#include <sys/mman.h>
#include <time.h>

#define MIB (1024 * 1024)
#define SIZE (8 * MIB)

static long long now_ms(void)
{
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return (long long)ts.tv_sec * 1000 + ts.tv_nsec / 1000000;
}

int main(void)
{
    int fd = open("/tmp/fmapbench.dat", O_RDWR | O_CREAT | O_TRUNC, 0600);
    CHECKC("create", fd >= 0);
    if (fd < 0) return 1;
    char *chunk = malloc(65536);
    memset(chunk, 0x5A, 65536);
    for (int i = 0; i < SIZE / 65536; i++) {
        if (write(fd, chunk, 65536) != 65536) { FAIL("fill", "short write at %d", i); return 1; }
    }
    PASS("fill");

    long long t0 = now_ms();
    long total = 0;
    lseek(fd, 0, SEEK_SET);
    ssize_t n;
    while ((n = read(fd, chunk, 65536)) > 0) total += n;
    long long t1 = now_ms();
    CHECK("read_all", total == SIZE, "read %ld of %d", total, SIZE);
    long long mbs = (t1 - t0) > 0 ? (long long)(SIZE / MIB) * 1000 / (t1 - t0) : 1000;
    CHECK("read_speed", mbs >= 12, "ms=%lld MiB_per_s=%lld (need >= 12)", t1 - t0, mbs);

    t0 = now_ms();
    char *m = mmap(0, SIZE, PROT_READ, MAP_PRIVATE, fd, 0);
    t1 = now_ms();
    CHECKC("mmap_private_ro", m != MAP_FAILED);
    if (m == MAP_FAILED) return 1;
    PASS("mmap_speed", "ms=%lld MiB_per_s=%lld", t1 - t0, (t1 - t0) > 0 ? (long long)(SIZE / MIB) * 1000 / (t1 - t0) : -1);
    CHECK("mmap_content", m[0] == 0x5A && m[SIZE - 1] == 0x5A && m[SIZE / 2] == 0x5A, "wrong bytes");

    t0 = now_ms();
    char *m2 = mmap(0, SIZE, PROT_READ | PROT_EXEC, MAP_PRIVATE, fd, 0);
    t1 = now_ms();
    CHECKC("mmap_private_rx", m2 != MAP_FAILED);
    if (m2 != MAP_FAILED) PASS("mmap_rx_speed", "ms=%lld", t1 - t0);
    close(fd);
    unlink("/tmp/fmapbench.dat");
    return 0;
}
