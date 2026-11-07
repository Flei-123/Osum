#define TNAME "fshare"
#include "t.h"
#include <fcntl.h>
#include <stdlib.h>
#include <sys/mman.h>
#include <sys/wait.h>

#define PG 4096
#define NP 256
#define SIZE (NP * PG)
#define PATH "/tmp/fshare.dat"
#define MIN_SPEEDUP 3

static unsigned char pat(long page, long off, int seed)
{
    return (unsigned char)(page * 13 + off % 251 + seed);
}

static int fill(int fd, int seed, long odd_page, int odd_seed)
{
    unsigned char *buf = malloc(PG);
    lseek(fd, 0, SEEK_SET);
    for (long p = 0; p < NP; p++) {
        int s = p == odd_page ? odd_seed : seed;
        for (long o = 0; o < PG; o++) buf[o] = pat(p, o, s);
        if (write(fd, buf, PG) != PG) { free(buf); return 0; }
    }
    free(buf);
    return 1;
}

static int page_ok(const unsigned char *m, long page, int seed)
{
    for (long o = 0; o < PG; o += 37) {
        if (m[page * PG + o] != pat(page, o, seed)) return 0;
    }
    return m[page * PG + PG - 1] == pat(page, PG - 1, seed);
}

static int all_ok(const unsigned char *m, int seed)
{
    for (long p = 0; p < NP; p++) {
        if (!page_ok(m, p, seed)) return 0;
    }
    return 1;
}

static unsigned long long touch_all(volatile unsigned char *m)
{
    unsigned long long t0 = __builtin_ia32_rdtsc();
    for (long p = 0; p < NP; p++) (void)m[p * PG];
    unsigned long long t1 = __builtin_ia32_rdtsc();
    return t1 - t0;
}

int main(void)
{
    int fd = open(PATH, O_RDWR | O_CREAT | O_TRUNC, 0600);
    CHECKC("create", fd >= 0);
    if (fd < 0) return 1;
    CHECK("fill", fill(fd, 1, -1, 0), "short write");

    unsigned char *a = mmap(0, SIZE, PROT_READ, MAP_PRIVATE, fd, 0);
    CHECKC("map_cold", a != MAP_FAILED);
    if (a == MAP_FAILED) return 1;
    unsigned long long cold = touch_all(a);
    CHECK("cold_content", all_ok(a, 1), "wrong bytes");
    munmap(a, SIZE);

    unsigned char *b = mmap(0, SIZE, PROT_READ, MAP_PRIVATE, fd, 0);
    CHECKC("map_warm", b != MAP_FAILED);
    if (b == MAP_FAILED) return 1;
    unsigned long long warm = touch_all(b);
    CHECK("warm_content", all_ok(b, 1), "wrong bytes");
    CHECK("warm_pass_faster", cold >= MIN_SPEEDUP * warm, "cold=%llu warm=%llu need cold >= %dx warm", cold, warm, MIN_SPEEDUP);
    PASS("speedup_x100", "%llu", warm ? cold * 100 / warm : 0);

    unsigned char *x = mmap(0, SIZE, PROT_READ | PROT_EXEC, MAP_PRIVATE, fd, 0);
    CHECKC("map_exec", x != MAP_FAILED);
    if (x != MAP_FAILED) {
        CHECK("exec_content", all_ok(x, 1), "wrong bytes");
        munmap(x, SIZE);
    }

    pid_t pid = fork();
    if (pid == 0) {
        unsigned char *c = mmap(0, SIZE, PROT_READ, MAP_PRIVATE, fd, 0);
        int ok = c != MAP_FAILED && all_ok(c, 1) && all_ok(b, 1);
        _exit(ok ? 0 : 1);
    }
    int st = 0;
    waitpid(pid, &st, 0);
    CHECK("fork_child_reads", WIFEXITED(st) && WEXITSTATUS(st) == 0, "status=%d", st);
    CHECK("fork_parent_intact", all_ok(b, 1), "wrong bytes after fork");

    unsigned char *d = mmap(0, SIZE, PROT_READ, MAP_PRIVATE, fd, 0);
    CHECKC("map_prot", d != MAP_FAILED);
    unsigned char *e = mmap(0, SIZE, PROT_READ, MAP_PRIVATE, fd, 0);
    CHECKC("map_prot_other", e != MAP_FAILED);
    if (d != MAP_FAILED && e != MAP_FAILED) {
        unsigned char before = d[5 * PG];
        int rc = mprotect(d + 5 * PG, PG, PROT_READ | PROT_WRITE);
        CHECKC("mprotect_cached_page_rw", rc == 0);
        if (rc == 0) {
            d[5 * PG] = (unsigned char)(before + 1);
            CHECK("private_write_visible", d[5 * PG] == (unsigned char)(before + 1), "write lost");
            CHECK("private_write_not_shared", e[5 * PG] == before, "other mapping saw the write");
            unsigned char *f = mmap(0, SIZE, PROT_READ, MAP_PRIVATE, fd, 0);
            unsigned char fv = f != MAP_FAILED ? f[5 * PG] : 0;
            CHECK("private_write_not_cached", f != MAP_FAILED && fv == before, "new mapping saw the write");
            if (f != MAP_FAILED) munmap(f, SIZE);
        }
        munmap(d, SIZE);
        munmap(e, SIZE);
    }

    unsigned char patch[PG];
    for (long o = 0; o < PG; o++) patch[o] = pat(3, o, 77);
    CHECK("pwrite", pwrite(fd, patch, PG, 3 * PG) == PG, "short");
    unsigned char *g = mmap(0, SIZE, PROT_READ, MAP_PRIVATE, fd, 0);
    CHECKC("map_after_write", g != MAP_FAILED);
    if (g != MAP_FAILED) {
        CHECK("write_invalidates", page_ok(g, 3, 77) && page_ok(g, 2, 1) && page_ok(g, 4, 1), "stale page after write");
        munmap(g, SIZE);
    }

    int shrunk = ftruncate(fd, 10 * PG) == 0;
    unsigned char *h = shrunk ? mmap(0, 10 * PG, PROT_READ, MAP_PRIVATE, fd, 0) : MAP_FAILED;
    if (shrunk) CHECKC("map_after_shrink", h != MAP_FAILED);
    if (h != MAP_FAILED) {
        CHECK("shrink_content", page_ok(h, 9, 1) && page_ok(h, 3, 77), "wrong bytes");
        munmap(h, 10 * PG);
    }

    close(fd);
    unlink(PATH);
    int fd2 = open(PATH, O_RDWR | O_CREAT | O_TRUNC, 0600);
    CHECKC("recreate", fd2 >= 0);
    if (fd2 >= 0) {
        CHECK("refill", fill(fd2, 9, -1, 0), "short write");
        unsigned char *k = mmap(0, SIZE, PROT_READ, MAP_PRIVATE, fd2, 0);
        CHECKC("map_recreated", k != MAP_FAILED);
        if (k != MAP_FAILED) {
            CHECK("recreate_content", all_ok(k, 9), "stale pages of the old file");
            munmap(k, SIZE);
        }
        close(fd2);
        unlink(PATH);
    }
    munmap(b, SIZE);
    return 0;
}
