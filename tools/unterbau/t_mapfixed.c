#define TNAME "mapfixed"
#include "t.h"
#include <fcntl.h>
#include <stdint.h>
#include <sys/mman.h>
#include <sys/wait.h>

#ifndef MAP_FIXED_NOREPLACE
#define MAP_FIXED_NOREPLACE 0x100000
#endif

#define PG 4096UL
#define SHARED_DATA 0x7ffe0000UL
#define RESERVE_LOW 0x7f000000UL
#define RESERVE_LEN 0x00ff0000UL
#define PATH "/tmp/mapfixed.dat"

static void *reserve(unsigned long addr, unsigned long len)
{
    return mmap((void *)addr, len, PROT_NONE, MAP_PRIVATE | MAP_ANONYMOUS | MAP_NORESERVE | MAP_FIXED_NOREPLACE, -1, 0);
}

int main(void)
{
    void *r = reserve(RESERVE_LOW, RESERVE_LEN);
    CHECKC("reserve_range", r == (void *)RESERVE_LOW);
    errno = 0;
    void *again = reserve(RESERVE_LOW + 0x10000, PG);
    CHECK("noreplace_conflict", again == MAP_FAILED && errno == EEXIST, "errno=%d", errno);
    errno = 0;
    void *low = reserve(0x10000, 0x100000);
    CHECK("noreplace_unmappable_not_einval", low == MAP_FAILED && errno != EINVAL, "errno=%d", errno);

    int fd = open(PATH, O_RDWR | O_CREAT | O_TRUNC, 0600);
    CHECKC("create", fd >= 0);
    if (fd < 0) return 1;
    static char zero[PG];
    CHECK("size", write(fd, zero, PG) == (ssize_t)PG, "short write");

    volatile unsigned char *w = mmap((void *)SHARED_DATA, PG, PROT_READ | PROT_WRITE, MAP_SHARED | MAP_FIXED, fd, 0);
    CHECKC("fixed_shared_rw", w == (volatile unsigned char *)SHARED_DATA);
    if (w == MAP_FAILED) return 1;
    w[0] = 0x5a;
    w[PG - 1] = 0xa5;

    volatile unsigned char *ro = mmap(0, PG, PROT_READ, MAP_SHARED, fd, 0);
    CHECKC("shared_ro_attach", ro != MAP_FAILED);
    if (ro != MAP_FAILED) {
        CHECK("shared_ro_sees_write", ro[0] == 0x5a && ro[PG - 1] == 0xa5, "bytes %02x %02x", ro[0], ro[PG - 1]);
        w[1] = 0x33;
        CHECK("shared_ro_live", ro[1] == 0x33, "byte %02x", ro[1]);
    }

    int fd2 = open(PATH, O_RDONLY);
    volatile unsigned char *fx = mmap((void *)(SHARED_DATA - 0x10000), PG, PROT_READ, MAP_SHARED | MAP_FIXED, fd2, 0);
    CHECKC("fixed_shared_ro", fx == (volatile unsigned char *)(SHARED_DATA - 0x10000));
    if (fx != MAP_FAILED) CHECK("fixed_shared_ro_content", fx[0] == 0x5a, "byte %02x", fx[0]);

    pid_t pid = fork();
    if (pid == 0) _exit(w[0] == 0x5a ? 0 : 1);
    int st = 0;
    waitpid(pid, &st, 0);
    CHECK("fork_child_reads_fixed", WIFEXITED(st) && WEXITSTATUS(st) == 0, "status=%d", st);

    unsigned long commit = RESERVE_LOW + 0x100000;
    CHECK("commit_mprotect", mprotect((void *)commit, 4 * PG, PROT_READ | PROT_WRITE) == 0, "errno=%d", errno);
    volatile unsigned char *c = (volatile unsigned char *)commit;
    c[0] = 1;
    c[4 * PG - 1] = 2;
    CHECK("commit_usable", c[0] == 1 && c[4 * PG - 1] == 2, "bytes");

    void *fixed = mmap((void *)(RESERVE_LOW + 0x200000), 8 * PG, PROT_READ | PROT_WRITE, MAP_PRIVATE | MAP_ANONYMOUS | MAP_FIXED, -1, 0);
    CHECKC("fixed_anon_over_reserve", fixed == (void *)(RESERVE_LOW + 0x200000));
    if (fixed != MAP_FAILED) {
        ((volatile unsigned char *)fixed)[8 * PG - 1] = 7;
        CHECK("fixed_anon_zeroed_usable", ((volatile unsigned char *)fixed)[0] == 0 && ((volatile unsigned char *)fixed)[8 * PG - 1] == 7, "bytes");
    }

    CHECK("unmap_fixed", munmap((void *)SHARED_DATA, PG) == 0, "errno=%d", errno);
    void *redo = mmap((void *)SHARED_DATA, PG, PROT_READ | PROT_WRITE, MAP_PRIVATE | MAP_ANONYMOUS | MAP_FIXED_NOREPLACE, -1, 0);
    CHECKC("remap_after_unmap", redo == (void *)SHARED_DATA);
    unlink(PATH);
    return 0;
}
