/* Demand-paged private file mappings (LA-9 step 2): content, EOF tail, private writes, fork, munmap, mprotect, mremap, MAP_FIXED over a reservation, read() into a mapped page. */
#define TNAME "flazy"
#include "t.h"
#include <fcntl.h>
#include <stdlib.h>
#include <sys/mman.h>
#include <sys/wait.h>
#include <time.h>

#define PG 4096
#define NP 64
#define FSIZE (NP * PG - 1000)
#define PATH "/tmp/flazy.dat"

static unsigned char pat(long off)
{
    return (unsigned char)((off / PG) * 7 + (off % PG) % 251 + 1);
}

static int page_ok(const unsigned char *m, long page, long limit)
{
    for (long o = 0; o < PG; o += 61) {
        long off = page * PG + o;
        unsigned char want = off < limit ? pat(off) : 0;
        if (m[off] != want) return 0;
    }
    return 1;
}

static long long now_ms(void)
{
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return (long long)ts.tv_sec * 1000 + ts.tv_nsec / 1000000;
}

int main(void)
{
    int fd = open(PATH, O_RDWR | O_CREAT | O_TRUNC, 0600);
    CHECKC("create", fd >= 0);
    if (fd < 0) return 1;
    unsigned char *buf = malloc(FSIZE);
    for (long o = 0; o < FSIZE; o++) buf[o] = pat(o);
    CHECK("fill", write(fd, buf, FSIZE) == FSIZE, "short write");

    long long t0 = now_ms();
    unsigned char *m = mmap(0, NP * PG, PROT_READ | PROT_WRITE, MAP_PRIVATE, fd, 0);
    long long t1 = now_ms();
    CHECKC("mmap", m != MAP_FAILED);
    if (m == MAP_FAILED) return 1;
    PASS("mmap_time", "ms=%lld", t1 - t0);

    CHECK("first_page", page_ok(m, 0, FSIZE), "page 0 wrong");
    CHECK("middle_page", page_ok(m, 31, FSIZE), "page 31 wrong");
    CHECK("last_page_tail_zero", page_ok(m, NP - 1, FSIZE) && m[NP * PG - 1] == 0, "tail not zero");

    m[5 * PG + 10] = 0xEE;
    unsigned char probe = 0;
    CHECK("private_write_seen", m[5 * PG + 10] == 0xEE, "write lost");
    CHECK("private_write_not_in_file", pread(fd, &probe, 1, 5 * PG + 10) == 1 && probe == pat(5 * PG + 10), "file changed: %d", probe);
    m[40 * PG + 3] = 0xDD;

    pid_t pid = fork();
    if (pid == 0) {
        int bad = 0;
        if (!page_ok(m, 20, FSIZE)) bad |= 1;
        if (m[5 * PG + 10] != 0xEE) bad |= 2;
        if (m[40 * PG + 3] != 0xDD) bad |= 4;
        m[20 * PG + 1] = 0x77;
        m[6 * PG + 2] = 0x66;
        _exit(bad);
    }
    int st = 0;
    waitpid(pid, &st, 0);
    CHECK("fork_child_content", WIFEXITED(st) && WEXITSTATUS(st) == 0, "status %d", st);
    CHECK("fork_child_write_private", m[20 * PG + 1] == pat(20 * PG + 1) && page_ok(m, 6, FSIZE), "child write leaked");

    unsigned char *r = mmap(0, NP * PG, PROT_READ, MAP_PRIVATE, fd, 0);
    CHECKC("mmap_ro", r != MAP_FAILED);
    if (r != MAP_FAILED) {
        CHECK("mprotect_rw", mprotect(r, NP * PG, PROT_READ | PROT_WRITE) == 0, "mprotect failed");
        r[9 * PG + 4] = 0x42;
        CHECK("mprotect_write", r[9 * PG + 4] == 0x42 && page_ok(r, 30, FSIZE), "content after mprotect");
        CHECK("mprotect_none", mprotect(r + 50 * PG, 4 * PG, PROT_NONE) == 0, "mprotect none failed");
        CHECK("mprotect_back", mprotect(r + 50 * PG, 4 * PG, PROT_READ) == 0 && page_ok(r, 52, FSIZE), "content after none/back");
        CHECK("munmap_part", munmap(r + 10 * PG, 20 * PG) == 0, "munmap failed");
        CHECK("munmap_rest_ok", page_ok(r, 9, FSIZE) && page_ok(r, 40, FSIZE), "rest changed");
        munmap(r, 10 * PG);
        munmap(r + 30 * PG, 34 * PG);
    }

    unsigned char *g = mmap(0, 20 * PG, PROT_READ | PROT_WRITE, MAP_PRIVATE, fd, 0);
    CHECKC("mmap_small", g != MAP_FAILED);
    if (g != MAP_FAILED) {
        g[PG + 1] = 0x31;
        unsigned char *g2 = mremap(g, 20 * PG, 40 * PG, MREMAP_MAYMOVE);
        CHECKC("mremap_grow", g2 != MAP_FAILED);
        if (g2 != MAP_FAILED) {
            CHECK("mremap_touched", g2[PG + 1] == 0x31, "touched page lost");
            CHECK("mremap_untouched", page_ok(g2, 7, FSIZE) && page_ok(g2, 19, FSIZE), "untouched page wrong");
            CHECK("mremap_new_zero", g2[30 * PG] == 0, "grown part not zero");
        }
    }

    unsigned char *res = mmap(0, 128 * PG, PROT_NONE, MAP_PRIVATE | MAP_ANONYMOUS | MAP_NORESERVE, -1, 0);
    CHECKC("reserve", res != MAP_FAILED);
    if (res != MAP_FAILED) {
        unsigned char *f = mmap(res + 8 * PG, 32 * PG, PROT_READ, MAP_PRIVATE | MAP_FIXED, fd, 16 * PG);
        CHECKC("fixed_over_reserve", f == res + 8 * PG);
        if (f == res + 8 * PG) {
            CHECK("fixed_offset", f[0] == pat(16 * PG) && f[31 * PG + 5] == pat(47 * PG + 5), "file offset wrong");
        }
    }

    unsigned char *rd = mmap(0, 20 * PG, PROT_READ | PROT_WRITE, MAP_PRIVATE, fd, 0);
    if (rd != MAP_FAILED) {
        long got = pread(fd, rd + 3 * PG + 100, 500, 50 * PG);
        CHECK("pread_into_mapping", got == 500 && rd[3 * PG + 100] == pat(50 * PG) && rd[3 * PG + 599] == pat(50 * PG + 499), "got %ld", got);
    }

    long long t2 = now_ms();
    unsigned char *big = mmap(0, 32 * 1024 * 1024, PROT_READ, MAP_PRIVATE, fd, 0);
    long long t3 = now_ms();
    CHECKC("mmap_beyond_eof", big != MAP_FAILED);
    if (big != MAP_FAILED) PASS("mmap_beyond_eof_time", "ms=%lld", t3 - t2);

    close(fd);
    unlink(PATH);
    return 0;
}
