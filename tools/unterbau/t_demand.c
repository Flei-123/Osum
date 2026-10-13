/* demand paging for memfd / SHM objects (WP-DEMAND): a sparse ftruncate costs no RAM, a page gets its frame at the first touch. */
#define TNAME "demand"
#include "t.h"
#include <pthread.h>
#include <stdint.h>
#include <stdlib.h>
#include <sys/mman.h>
#include <sys/sysinfo.h>
#include <sys/syscall.h>

#define MIB (1024ul * 1024ul)
#define PG 4096ul

static long free_kib(void)
{
    struct sysinfo si;
    if (sysinfo(&si) != 0) return -1;
    return (long)(((unsigned long long)si.freeram * si.mem_unit) >> 10);
}

static int mfd(void) { return (int)syscall(SYS_memfd_create, "demand", 0); }

#define NTH 4
#define RACE_PAGES 2048
static volatile unsigned char *race_base;
static volatile int race_go;
static void *racer(void *arg)
{
    (void)arg;
    while (!race_go) { }
    for (unsigned long p = 0; p < RACE_PAGES; p++)
        __sync_fetch_and_add((volatile uint32_t *)(race_base + p * PG), 1);
    return 0;
}

int main(void)
{
    int fd = mfd();
    CHECKC("memfd_create", fd >= 0);
    if (fd < 0) return 0;
    long f0 = free_kib();
    int r = ftruncate(fd, 256 * MIB);
    CHECKC("ftruncate_256mib", r == 0);
    unsigned char *a = mmap(0, 256 * MIB, PROT_READ | PROT_WRITE, MAP_SHARED, fd, 0);
    CHECKC("mmap_256mib", a != MAP_FAILED);
    if (a == MAP_FAILED) return 0;
    long f1 = free_kib();
    CHECK("sparse_costs_no_ram", f0 - f1 < 4096, "free RAM fell by %ld KiB for a sparse 256 MiB memfd (>= 4096 KiB = eager frames)", f0 - f1);

    /* touch a few pages far apart */
    unsigned long offs[3] = { 100 * MIB, 200 * MIB + 5 * PG, 256 * MIB - PG };
    for (int i = 0; i < 3; i++) memset(a + offs[i], 0xA0 + i, PG);
    long f2 = free_kib();
    CHECK("touch_costs_three_pages", f1 - f2 >= 12 && f1 - f2 < 512, "3 touched pages cost %ld KiB (want 12..511)", f1 - f2);
    int okp = 1;
    for (int i = 0; i < 3; i++) for (unsigned long k = 0; k < PG; k += 511) if (a[offs[i] + k] != 0xA0 + i) okp = 0;
    CHECK("touched_data_reads_back", okp, "pattern wrong");

    /* an untouched page reads as zero */
    int z = 1;
    for (unsigned long k = 0; k < PG; k++) if (a[50 * MIB + k] != 0) z = 0;
    CHECK("untouched_reads_zero", z, "nonzero byte in an untouched page");

    /* second mapping shares the same pages */
    unsigned char *b = mmap(0, 256 * MIB, PROT_READ | PROT_WRITE, MAP_SHARED, fd, 0);
    CHECKC("second_mmap", b != MAP_FAILED);
    if (b != MAP_FAILED) {
        CHECK("second_sees_first", b[offs[1]] == 0xA1 && b[offs[2] + 77] == 0xA2, "second mapping does not see the data");
        b[150 * MIB] = 0x5C;
        CHECK("first_sees_second", a[150 * MIB] == 0x5C, "write through the second mapping is not visible");
        munmap(b, 256 * MIB);
        CHECK("survives_unmap_of_other", a[150 * MIB] == 0x5C && a[offs[0] + 9] == 0xA0, "data lost with the other mapping");
    }

    /* every page of 8 MiB, sequential */
    for (unsigned long p = 0; p < 2048; p++) { a[10 * MIB + p * PG] = (unsigned char)p; a[10 * MIB + p * PG + 4095] = (unsigned char)(p ^ 0x5A); }
    int seq = 1;
    for (unsigned long p = 0; p < 2048; p++) if (a[10 * MIB + p * PG] != (unsigned char)p || a[10 * MIB + p * PG + 4095] != (unsigned char)(p ^ 0x5A)) seq = 0;
    CHECK("sequential_8mib", seq, "data mismatch");

    /* threads race on the first touch of the same pages */
    race_base = a + 20 * MIB;
    pthread_t th[NTH];
    int started = 0;
    for (int i = 0; i < NTH; i++) if (pthread_create(&th[i], 0, racer, 0) == 0) started++;
    race_go = 1;
    for (int i = 0; i < started; i++) pthread_join(th[i], 0);
    int bad = 0;
    for (unsigned long p = 0; p < RACE_PAGES; p++) if (*(volatile uint32_t *)(race_base + p * PG) != (uint32_t)started) bad++;
    CHECK("threads_race_first_touch", started == NTH && bad == 0, "%d threads started, %d of %d pages lost an increment", started, bad, RACE_PAGES);

    /* a system call reads from a page nobody touched yet: Linux would fault it in */
    int pp[2];
    if (pipe(pp) == 0) {
        ssize_t w = write(pp[1], a + 70 * MIB, 64);
        CHECK("syscall_reads_untouched_page", w == 64, "write() from an untouched sparse page returned %zd errno %d", w, errno);
        close(pp[0]); close(pp[1]);
        char rb[64]; memset(rb, 7, sizeof rb);
        int p2[2]; (void)!pipe(p2); (void)!write(p2[1], rb, 64);
        ssize_t rr = read(p2[0], a + 71 * MIB, 64);
        CHECK("syscall_writes_untouched_page", rr == 64 && a[71 * MIB] == 7, "read() into an untouched sparse page returned %zd errno %d", rr, errno);
        close(p2[0]); close(p2[1]);
    }

    /* grow to 512 MiB (foot's default pool) and map it all */
    r = ftruncate(fd, 512 * MIB);
    CHECKC("grow_to_512mib", r == 0);
    munmap(a, 256 * MIB); /* the arena holds 640 MiB: one 512 MiB pool at a time, like foot */
    a = 0;
    unsigned char *c = mmap(0, 512 * MIB, PROT_READ | PROT_WRITE, MAP_SHARED, fd, 0);
    CHECKC("mmap_512mib", c != MAP_FAILED);
    if (c != MAP_FAILED) {
        c[400 * MIB + 3] = 0x77;
        CHECK("touch_in_grown_part", c[400 * MIB + 3] == 0x77 && c[offs[0] + 9] == 0xA0, "grown mapping broken");
        long f3 = free_kib();
        munmap(c, 512 * MIB);
        close(fd);
        long f4 = free_kib();
        CHECK("close_gives_frames_back", f4 - f3 > 1024, "free RAM rose by only %ld KiB after munmap+close (touched ~ 40 MiB)", f4 - f3);
        long f5 = free_kib();
        CHECK("no_leak_overall", f0 - f5 < 2048, "free RAM is %ld KiB below the start", f0 - f5);
    }
    return 0;
}
