#define TNAME "sharedanon"
#include "t.h"
#include <stdlib.h>
#include <sys/mman.h>
#include <sys/wait.h>

#define PG 4096
#define SMALL_PAGES 8
#define LAZY_PAGES 512

struct sync { int to_child[2]; int to_parent[2]; };

static void sync_open(struct sync *s)
{
    if (pipe(s->to_child) || pipe(s->to_parent)) _exit(90);
}

static void signal_to(int fd) { char c = 'x'; (void)!write(fd, &c, 1); }
static void wait_on(int fd) { char c; (void)!read(fd, &c, 1); }

static int reap(pid_t pid)
{
    int st = 0;
    waitpid(pid, &st, 0);
    return WIFEXITED(st) ? WEXITSTATUS(st) : 100;
}

static unsigned char *shared_anon(size_t len)
{
    return mmap(0, len, PROT_READ | PROT_WRITE, MAP_SHARED | MAP_ANONYMOUS, -1, 0);
}

static void child_writes_parent_reads(const char *name, size_t pages, int touch_first)
{
    size_t len = pages * PG;
    unsigned char *m = shared_anon(len);
    if (m == MAP_FAILED) { FAIL(name, "mmap failed errno=%d", errno); return; }
    if (touch_first) for (size_t p = 0; p < pages; p++) m[p * PG] = 1;
    pid_t c = fork();
    if (c == 0) {
        for (size_t p = 0; p < pages; p++) m[p * PG + 7] = (unsigned char)(p + 10);
        _exit(0);
    }
    int rc = reap(c);
    size_t wrong = 0;
    for (size_t p = 0; p < pages; p++) if (m[p * PG + 7] != (unsigned char)(p + 10)) wrong++;
    CHECK(name, rc == 0 && wrong == 0, "child rc=%d, parent lacks %zu of %zu pages", rc, wrong, pages);
    munmap(m, len);
}

static void parent_writes_child_reads(const char *name, size_t pages, int touch_first)
{
    size_t len = pages * PG;
    unsigned char *m = shared_anon(len);
    if (m == MAP_FAILED) { FAIL(name, "mmap failed errno=%d", errno); return; }
    if (touch_first) for (size_t p = 0; p < pages; p++) m[p * PG] = 1;
    struct sync s;
    sync_open(&s);
    pid_t c = fork();
    if (c == 0) {
        wait_on(s.to_child[0]);
        size_t wrong = 0;
        for (size_t p = 0; p < pages; p++) if (m[p * PG + 9] != (unsigned char)(p + 20)) wrong++;
        _exit(wrong ? 1 : 0);
    }
    for (size_t p = 0; p < pages; p++) m[p * PG + 9] = (unsigned char)(p + 20);
    signal_to(s.to_child[1]);
    int rc = reap(c);
    CHECK(name, rc == 0, "child rc=%d (1 = stale view of the parent's stores)", rc);
    munmap(m, len);
}

static void ping_pong(void)
{
    unsigned char *m = shared_anon(2 * PG);
    if (m == MAP_FAILED) { FAIL("ping_pong", "mmap errno=%d", errno); return; }
    m[0] = 0; m[PG] = 0;
    struct sync s;
    sync_open(&s);
    pid_t c = fork();
    if (c == 0) {
        int wrong = 0;
        for (int i = 1; i <= 50; i++) {
            wait_on(s.to_child[0]);
            if (m[0] != i) wrong++;
            m[PG] = (unsigned char)i;
            signal_to(s.to_parent[1]);
        }
        _exit(wrong ? 1 : 0);
    }
    int wrong = 0;
    for (int i = 1; i <= 50; i++) {
        m[0] = (unsigned char)i;
        signal_to(s.to_child[1]);
        wait_on(s.to_parent[0]);
        if (m[PG] != i) wrong++;
    }
    int rc = reap(c);
    CHECK("ping_pong", rc == 0 && wrong == 0, "child rc=%d, parent stale %d of 50", rc, wrong);
    munmap(m, 2 * PG);
}

static void grandchild(void)
{
    unsigned char *m = shared_anon(SMALL_PAGES * PG);
    if (m == MAP_FAILED) { FAIL("second_fork", "mmap errno=%d", errno); return; }
    m[0] = 1;
    pid_t c = fork();
    if (c == 0) {
        pid_t g = fork();
        if (g == 0) { m[3 * PG + 1] = 77; _exit(0); }
        int rc = reap(g);
        if (rc != 0) _exit(2);
        if (m[3 * PG + 1] != 77) _exit(3);
        m[4 * PG + 2] = 88;
        _exit(0);
    }
    int rc = reap(c);
    CHECK("second_fork", rc == 0 && m[3 * PG + 1] == 77 && m[4 * PG + 2] == 88,
          "child rc=%d (3 = middle misses the grandchild), got %d %d", rc, m[3 * PG + 1], m[4 * PG + 2]);
    munmap(m, SMALL_PAGES * PG);
}

static void after_mremap(void)
{
    size_t len = SMALL_PAGES * PG;
    unsigned char *m = shared_anon(len);
    if (m == MAP_FAILED) { FAIL("mremap_map", "mmap errno=%d", errno); return; }
    for (size_t p = 0; p < SMALL_PAGES; p++) m[p * PG] = (unsigned char)(p + 1);
    unsigned char *n = mremap(m, len, 2 * len, MREMAP_MAYMOVE);
    CHECKC("mremap_call", n != MAP_FAILED);
    if (n == MAP_FAILED) return;
    CHECK("mremap_keeps", n[0] == 1 && n[(SMALL_PAGES - 1) * PG] == SMALL_PAGES, "contents lost");
    pid_t c = fork();
    if (c == 0) {
        if (n[2 * PG] != 3) _exit(2);
        n[(SMALL_PAGES + 3) * PG + 5] = 99;
        n[5] = 55;
        _exit(0);
    }
    int rc = reap(c);
    CHECK("mremap_fork_parent_sees", rc == 0 && n[(SMALL_PAGES + 3) * PG + 5] == 99 && n[5] == 55,
          "child rc=%d, got %d %d", rc, n[(SMALL_PAGES + 3) * PG + 5], n[5]);
    munmap(n, 2 * len);
}

static void private_stays_private(void)
{
    unsigned char *m = mmap(0, PG, PROT_READ | PROT_WRITE, MAP_PRIVATE | MAP_ANONYMOUS, -1, 0);
    if (m == MAP_FAILED) { FAIL("private_control", "mmap errno=%d", errno); return; }
    m[0] = 5;
    pid_t c = fork();
    if (c == 0) { m[0] = 6; _exit(0); }
    int rc = reap(c);
    CHECK("private_control", rc == 0 && m[0] == 5, "private page changed by the child: %d", m[0]);
    munmap(m, PG);
}

int main(void)
{
    private_stays_private();
    child_writes_parent_reads("child_to_parent_touched", SMALL_PAGES, 1);
    child_writes_parent_reads("child_to_parent_untouched", SMALL_PAGES, 0);
    child_writes_parent_reads("child_to_parent_lazy", LAZY_PAGES, 0);
    parent_writes_child_reads("parent_to_child_touched", SMALL_PAGES, 1);
    parent_writes_child_reads("parent_to_child_untouched", SMALL_PAGES, 0);
    parent_writes_child_reads("parent_to_child_lazy", LAZY_PAGES, 0);
    ping_pong();
    grandchild();
    after_mremap();
    return 0;
}
