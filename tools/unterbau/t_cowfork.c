#define TNAME "cowfork"
#include "t.h"
#include <stdlib.h>
#include <sys/mman.h>
#include <sys/wait.h>
#include <pthread.h>
#include <time.h>

#define PG 4096
#define PAGES 256
#define BIG_MB 64

static unsigned char *buf;

static long mem_free_kb(void)
{
    char line[128];
    long v = -1;
    FILE *f = fopen("/proc/meminfo", "r");
    if (!f) return -1;
    while (fgets(line, sizeof line, f))
        if (sscanf(line, "MemFree: %ld", &v) == 1) break;
    fclose(f);
    return v;
}

static int all_equal(unsigned char *p, long n, unsigned char v)
{
    for (long i = 0; i < n; i++) if (p[i] != v) return 0;
    return 1;
}

static int wait_rc(pid_t pid)
{
    int st = 0;
    if (waitpid(pid, &st, 0) != pid) return -1;
    return WIFEXITED(st) ? WEXITSTATUS(st) : 100 + WTERMSIG(st);
}

static void child_write_isolated(void)
{
    memset(buf, 0xA1, PAGES * PG);
    pid_t pid = fork();
    if (pid == 0) {
        if (!all_equal(buf, PAGES * PG, 0xA1)) _exit(2);
        memset(buf, 0xB2, PAGES * PG);
        _exit(all_equal(buf, PAGES * PG, 0xB2) ? 0 : 3);
    }
    int rc = wait_rc(pid);
    CHECK("child_write_isolated", rc == 0 && all_equal(buf, PAGES * PG, 0xA1), "rc=%d parent[0]=%x", rc, buf[0]);
}

static void parent_write_isolated(void)
{
    int go[2], done[2];
    if (pipe(go) || pipe(done)) { FAIL("parent_write_isolated", "pipe"); return; }
    memset(buf, 0x11, PAGES * PG);
    pid_t pid = fork();
    if (pid == 0) {
        char c;
        if (read(go[0], &c, 1) != 1) _exit(4);
        _exit(all_equal(buf, PAGES * PG, 0x11) ? 0 : 5);
    }
    memset(buf, 0x22, PAGES * PG);
    if (write(go[1], "x", 1) != 1) {}
    int rc = wait_rc(pid);
    CHECK("parent_write_isolated", rc == 0 && all_equal(buf, PAGES * PG, 0x22), "rc=%d", rc);
    close(go[0]); close(go[1]); close(done[0]); close(done[1]);
}

static void kernel_write_isolated(void)
{
    int p[2];
    if (pipe(p)) { FAIL("kernel_write_isolated", "pipe"); return; }
    memset(buf, 0x33, PAGES * PG);
    pid_t pid = fork();
    if (pid == 0) {
        long got = 0;
        while (got < 3 * PG) {
            long r = read(p[0], buf + PG / 2 + got, 3 * PG - got);
            if (r <= 0) _exit(6);
            got += r;
        }
        _exit(all_equal(buf + PG / 2, 3 * PG, 0x44) ? 0 : 7);
    }
    unsigned char tmp[3 * PG];
    memset(tmp, 0x44, sizeof tmp);
    if (write(p[1], tmp, sizeof tmp) != (long)sizeof tmp) {}
    int rc = wait_rc(pid);
    CHECK("kernel_write_isolated", rc == 0 && all_equal(buf, PAGES * PG, 0x33), "rc=%d", rc);
    close(p[0]); close(p[1]);
}

static void protect_and_dontneed(void)
{
    unsigned char *m = mmap(0, 8 * PG, PROT_READ | PROT_WRITE, MAP_PRIVATE | MAP_ANONYMOUS, -1, 0);
    if (m == MAP_FAILED) { FAIL("protect_and_dontneed", "mmap"); return; }
    memset(m, 0x55, 8 * PG);
    pid_t pid = fork();
    if (pid == 0) {
        if (mprotect(m, 4 * PG, PROT_READ)) _exit(8);
        if (mprotect(m, 4 * PG, PROT_READ | PROT_WRITE)) _exit(9);
        memset(m, 0x66, 4 * PG);
        if (madvise(m + 4 * PG, 4 * PG, MADV_DONTNEED)) _exit(10);
        if (!all_equal(m + 4 * PG, 4 * PG, 0)) _exit(11);
        _exit(all_equal(m, 4 * PG, 0x66) ? 0 : 12);
    }
    int rc = wait_rc(pid);
    CHECK("protect_and_dontneed", rc == 0 && all_equal(m, 8 * PG, 0x55), "rc=%d", rc);
    munmap(m, 8 * PG);
}

static void *spin_writer(void *arg)
{
    volatile unsigned long *cell = arg;
    for (long i = 0; i < 2000000; i++) cell[0] = i;
    return 0;
}

static void fork_with_thread(void)
{
    unsigned long *cell = (unsigned long *)(buf + 8 * PG);
    pthread_t th;
    int bad = 0;
    if (pthread_create(&th, 0, spin_writer, cell)) { FAIL("fork_with_thread", "pthread_create"); return; }
    for (int k = 0; k < 20; k++) {
        pid_t pid = fork();
        if (pid == 0) {
            unsigned long a = cell[0];
            for (volatile int d = 0; d < 200000; d++) {}
            _exit(cell[0] == a ? 0 : 13);
        }
        if (wait_rc(pid) != 0) bad++;
    }
    pthread_join(th, 0);
    CHECK("fork_with_thread", bad == 0, "bad=%d of 20", bad);
}

static void fork_shares_memory(void)
{
    long n = BIG_MB * 1024L * 1024L;
    unsigned char *m = mmap(0, n, PROT_READ | PROT_WRITE, MAP_PRIVATE | MAP_ANONYMOUS, -1, 0);
    if (m == MAP_FAILED) { FAIL("fork_shares_memory", "mmap"); return; }
    memset(m, 0x77, n);
    int p[2];
    if (pipe(p)) { FAIL("fork_shares_memory", "pipe"); return; }
    long before = mem_free_kb();
    pid_t pid = fork();
    if (pid == 0) {
        char c;
        if (read(p[0], &c, 1) != 1) _exit(14);
        _exit(m[n - 1] == 0x77 ? 0 : 15);
    }
    long after = mem_free_kb();
    if (write(p[1], "x", 1) != 1) {}
    int rc = wait_rc(pid);
    long used = before - after;
    CHECK("fork_shares_memory", rc == 0 && before > 0 && used < BIG_MB * 1024L / 4,
          "rc=%d fork used %ld kB for %d MiB", rc, used, BIG_MB);
    close(p[0]); close(p[1]);
    munmap(m, n);
}

static void no_frame_leak(void)
{
    long n = 16 * 1024L * 1024L;
    unsigned char *m = mmap(0, n, PROT_READ | PROT_WRITE, MAP_PRIVATE | MAP_ANONYMOUS, -1, 0);
    if (m == MAP_FAILED) { FAIL("no_frame_leak", "mmap"); return; }
    memset(m, 0x12, n);
    long before = mem_free_kb();
    for (int k = 0; k < 40; k++) {
        pid_t pid = fork();
        if (pid == 0) {
            if (k & 1) memset(m, 0x34, n / 2);
            _exit(0);
        }
        wait_rc(pid);
        if (k % 3 == 0) memset(m + (k % 8) * PG, 0x56, PG);
    }
    long after = mem_free_kb();
    CHECK("no_frame_leak", before > 0 && before - after < 4096, "lost %ld kB after 40 forks", before - after);
    munmap(m, n);
}

int main(void)
{
    buf = mmap(0, PAGES * PG, PROT_READ | PROT_WRITE, MAP_PRIVATE | MAP_ANONYMOUS, -1, 0);
    if (buf == MAP_FAILED) { FAIL("setup", "mmap"); return 0; }
    child_write_isolated();
    parent_write_isolated();
    kernel_write_isolated();
    protect_and_dontneed();
    fork_with_thread();
    fork_shares_memory();
    no_frame_leak();
    return 0;
}
