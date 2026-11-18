#define TNAME "fshmrace"
#include "t.h"
#include <fcntl.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <sys/mman.h>
#include <sys/wait.h>
#include <time.h>

#define PG 4096
#define WORKERS 4
#define SECONDS 8
#define OWN_PAGES_MAX 40
#define SHARED_PAGES 64
#define SHARED_PATH "/tmp/fsr_shared"
#define PROBE_OFF 500
#define MINE_OFF 100

enum { E_OK, E_OPEN, E_MAP, E_DATA, E_WRITEBACK, E_SHARED_MAP, E_SHARED_DATA };

static unsigned char pattern(long page, long off)
{
    return (unsigned char)(page * 31 + off * 7 + 5);
}

static int elapsed(struct timespec *t0)
{
    struct timespec t1;
    clock_gettime(CLOCK_MONOTONIC, &t1);
    return t1.tv_sec - t0->tv_sec >= SECONDS;
}

static int fill_file(int fd, long pages)
{
    static unsigned char buf[PG];
    for (long p = 0; p < pages; p++) {
        for (long o = 0; o < PG; o++) buf[o] = pattern(p, o);
        if (write(fd, buf, PG) != PG) return -1;
    }
    return 0;
}

static int own_round(int w, unsigned *seed)
{
    char path[64];
    snprintf(path, sizeof path, "/tmp/fsr_w%d", w);
    long pages = 1 + rand_r(seed) % OWN_PAGES_MAX;
    int fd = open(path, O_RDWR | O_CREAT | O_TRUNC, 0644);
    if (fd < 0 || fill_file(fd, pages) != 0) return E_OPEN;
    unsigned char *m = mmap(0, pages * PG, PROT_READ | PROT_WRITE, MAP_SHARED, fd, 0);
    if (m == MAP_FAILED) { close(fd); unlink(path); return E_MAP; }
    int rc = E_OK;
    for (long p = 0; p < pages && rc == E_OK; p++)
        if (m[p * PG + PROBE_OFF] != pattern(p, PROBE_OFF)) rc = E_DATA;
    long last = pages - 1;
    m[last * PG + MINE_OFF] = (unsigned char)(w + 1);
    munmap(m, pages * PG);
    unsigned char c = 0;
    if (rc == E_OK && (pread(fd, &c, 1, last * PG + MINE_OFF) != 1 || c != (unsigned char)(w + 1))) rc = E_WRITEBACK;
    close(fd);
    unlink(path);
    return rc;
}

static int shared_round(int w, unsigned *seed)
{
    int fd = open(SHARED_PATH, O_RDWR);
    if (fd < 0) return E_OPEN;
    long pages = 1 + rand_r(seed) % SHARED_PAGES;
    unsigned char *m = mmap(0, pages * PG, PROT_READ | PROT_WRITE, MAP_SHARED, fd, 0);
    if (m == MAP_FAILED) { close(fd); return E_SHARED_MAP; }
    int rc = E_OK;
    for (long p = 0; p < pages && rc == E_OK; p++)
        if (m[p * PG + PROBE_OFF] != pattern(p, PROBE_OFF)) rc = E_SHARED_DATA;
    m[(pages - 1) * PG + MINE_OFF + w] = (unsigned char)(w + 1);
    munmap(m, pages * PG);
    close(fd);
    return rc;
}

static int worker(int w)
{
    unsigned seed = 1234u + (unsigned)w * 77u;
    struct timespec t0;
    clock_gettime(CLOCK_MONOTONIC, &t0);
    int rounds = 0;
    while (!elapsed(&t0)) {
        int rc = own_round(w, &seed);
        if (rc == E_OK) rc = shared_round(w, &seed);
        if (rc != E_OK) return rc;
        rounds++;
    }
    return rounds > 0 ? E_OK : E_OPEN;
}

int main(void)
{
    unlink(SHARED_PATH);
    int fd = open(SHARED_PATH, O_RDWR | O_CREAT | O_TRUNC, 0644);
    if (fd < 0 || fill_file(fd, SHARED_PAGES) != 0) { FAIL("setup", "errno=%d", errno); return 0; }
    close(fd);
    pid_t pids[WORKERS];
    for (int w = 0; w < WORKERS; w++) {
        pids[w] = fork();
        if (pids[w] == 0) _exit(worker(w));
    }
    int bad = 0, killed = 0;
    for (int w = 0; w < WORKERS; w++) {
        int st = 0;
        waitpid(pids[w], &st, 0);
        if (!WIFEXITED(st)) { killed++; continue; }
        if (WEXITSTATUS(st) != E_OK) { bad++; FAIL("worker", "worker %d status %d", w, WEXITSTATUS(st)); }
    }
    CHECK("no_crash", killed == 0, "%d workers killed by a signal", killed);
    CHECK("workers_ok", bad == 0 && killed == 0, "%d workers failed", bad);
    unlink(SHARED_PATH);
    return 0;
}
