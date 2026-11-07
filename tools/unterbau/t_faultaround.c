#define TNAME "faultaround"
#include "t.h"
#include <fcntl.h>
#include <stdlib.h>
#include <sys/mman.h>
#include <sys/wait.h>

#define PG 4096
#define NP 512
#define SIZE (NP * PG)
#define PATH "/tmp/faultaround.dat"
#define TAIL_BYTES 123
#define MAX_COLD_CYCLES_PER_PAGE 140000ULL

static unsigned char pat(long page, long off, int seed)
{
    return (unsigned char)(page * 31 + off % 253 + seed);
}

static int fill(int fd, int seed, long pages, long tail)
{
    unsigned char *buf = malloc(PG);
    lseek(fd, 0, SEEK_SET);
    for (long p = 0; p < pages; p++) {
        long len = p == pages - 1 && tail ? tail : PG;
        for (long o = 0; o < len; o++) buf[o] = pat(p, o, seed);
        if (write(fd, buf, len) != len) { free(buf); return 0; }
    }
    free(buf);
    return 1;
}

static int page_ok(const unsigned char *m, long page, int seed)
{
    for (long o = 0; o < PG; o += 41) {
        if (m[page * PG + o] != pat(page, o, seed)) return 0;
    }
    return m[page * PG + PG - 1] == pat(page, PG - 1, seed);
}

static int all_ok(const unsigned char *m, long pages, int seed)
{
    for (long p = 0; p < pages; p++) {
        if (!page_ok(m, p, seed)) return 0;
    }
    return 1;
}

static unsigned long long touch_stride(volatile unsigned char *m, long stride)
{
    unsigned long long t0 = __builtin_ia32_rdtsc();
    for (long p = 0; p < NP; p += stride) (void)m[p * PG];
    return __builtin_ia32_rdtsc() - t0;
}

static int fresh_file(int seed, long pages, long tail)
{
    unlink(PATH);
    int fd = open(PATH, O_RDWR | O_CREAT | O_TRUNC, 0600);
    if (fd < 0) return -1;
    if (!fill(fd, seed, pages, tail)) { close(fd); return -1; }
    return fd;
}

int main(void)
{
    int fd = fresh_file(1, NP, 0);
    CHECKC("create", fd >= 0);
    if (fd < 0) return 1;

    unsigned char *a = mmap(0, SIZE, PROT_READ, MAP_PRIVATE, fd, 0);
    CHECKC("map_ro", a != MAP_FAILED);
    if (a == MAP_FAILED) return 1;
    unsigned long long cold = touch_stride(a, 1);
    PASS("cold_cycles_per_page", "%llu", cold / NP);
    CHECK("cold_batched", cold / NP <= MAX_COLD_CYCLES_PER_PAGE, "cold=%llu cycles per page, limit %llu", cold / NP, MAX_COLD_CYCLES_PER_PAGE);
    CHECK("ro_content", all_ok(a, NP, 1), "wrong bytes");
    munmap(a, SIZE);

    close(fd);
    fd = fresh_file(2, NP, 0);
    CHECKC("recreate_sparse", fd >= 0);
    if (fd < 0) return 1;
    unsigned char *s = mmap(0, SIZE, PROT_READ, MAP_PRIVATE, fd, 0);
    CHECKC("map_sparse", s != MAP_FAILED);
    if (s == MAP_FAILED) return 1;
    unsigned long long sparse = touch_stride(s, 5);
    PASS("sparse_cycles_per_touch", "%llu", sparse / ((NP + 4) / 5));
    CHECK("sparse_content", all_ok(s, NP, 2), "wrong bytes after sparse touches");
    munmap(s, SIZE);

    unsigned char *w = mmap(0, SIZE, PROT_READ | PROT_WRITE, MAP_PRIVATE, fd, 0);
    CHECKC("map_private_rw", w != MAP_FAILED);
    if (w != MAP_FAILED) {
        CHECK("private_rw_content", all_ok(w, NP, 2), "wrong bytes in private mapping");
        w[9 * PG] ^= 0x55;
        w[200 * PG + 7] ^= 0x55;
        unsigned char *o = mmap(0, SIZE, PROT_READ | PROT_WRITE, MAP_PRIVATE, fd, 0);
        CHECKC("map_private_other", o != MAP_FAILED);
        if (o != MAP_FAILED) {
            CHECK("private_write_isolated", page_ok(o, 9, 2) && page_ok(o, 200, 2), "private write leaked into another mapping");
            munmap(o, SIZE);
        }
        CHECK("private_write_kept", w[9 * PG] == (unsigned char)(pat(9, 0, 2) ^ 0x55), "private write lost");
        munmap(w, SIZE);
    }

    unsigned char *r = mmap(0, SIZE, PROT_READ, MAP_PRIVATE, fd, 0);
    CHECKC("map_after_private", r != MAP_FAILED);
    if (r != MAP_FAILED) {
        CHECK("file_untouched_by_private_write", page_ok(r, 9, 2) && page_ok(r, 200, 2), "private write reached the file");
        munmap(r, SIZE);
    }

    unsigned char *p0 = mmap(0, SIZE, PROT_READ, MAP_PRIVATE, fd, 0);
    CHECKC("map_window", p0 != MAP_FAILED);
    if (p0 != MAP_FAILED) {
        (void)((volatile unsigned char *)p0)[320 * PG];
        unsigned char patch[PG];
        for (long o = 0; o < PG; o++) patch[o] = pat(327, o, 77);
        CHECK("window_pwrite", pwrite(fd, patch, PG, 327 * PG) == PG, "short");
        unsigned char *p1 = mmap(0, SIZE, PROT_READ, MAP_PRIVATE, fd, 0);
        CHECKC("map_window_after_write", p1 != MAP_FAILED);
        if (p1 != MAP_FAILED) {
            CHECK("window_write_invalidates", page_ok(p1, 327, 77) && page_ok(p1, 326, 2) && page_ok(p1, 328, 2) && page_ok(p1, 320, 2), "stale page in the read-ahead window");
            munmap(p1, SIZE);
        }
        munmap(p0, SIZE);
    }

    pid_t pid = fork();
    if (pid == 0) {
        unsigned char *c = mmap(0, SIZE, PROT_READ, MAP_PRIVATE, fd, 0);
        _exit(c != MAP_FAILED && page_ok(c, 100, 2) && page_ok(c, 101, 2) && page_ok(c, 511, 2) ? 0 : 1);
    }
    int st = 0;
    waitpid(pid, &st, 0);
    CHECK("fork_child_reads", WIFEXITED(st) && WEXITSTATUS(st) == 0, "status=%d", st);
    close(fd);

    long tail_pages = 37;
    fd = fresh_file(3, tail_pages, TAIL_BYTES);
    CHECKC("create_tail", fd >= 0);
    if (fd >= 0) {
        unsigned char *t = mmap(0, tail_pages * PG, PROT_READ, MAP_PRIVATE, fd, 0);
        CHECKC("map_tail", t != MAP_FAILED);
        if (t != MAP_FAILED) {
            int ok = page_ok(t, 0, 3) && page_ok(t, 35, 3);
            for (long o = 0; o < TAIL_BYTES; o++) {
                if (t[(tail_pages - 1) * PG + o] != pat(tail_pages - 1, o, 3)) ok = 0;
            }
            for (long o = TAIL_BYTES; o < PG; o++) {
                if (t[(tail_pages - 1) * PG + o] != 0) ok = 0;
            }
            CHECK("tail_zero_filled", ok, "tail page content wrong");
            munmap(t, tail_pages * PG);
        }
        close(fd);
    }
    unlink(PATH);
    return 0;
}
