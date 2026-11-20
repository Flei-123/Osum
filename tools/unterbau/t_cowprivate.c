#define TNAME "cowprivate"
#include "t.h"
#include <fcntl.h>
#include <stdlib.h>
#include <sys/mman.h>
#include <signal.h>
#include <sys/wait.h>

#define PG 4096
#define PATH "/tmp/cowp.dat"

static unsigned char at(long off)
{
    unsigned char c = 0xEE;
    int fd = open(PATH, O_RDONLY);
    if (fd >= 0) { if (pread(fd, &c, 1, off) != 1) c = 0xEF; close(fd); }
    return c;
}

static int child_private_write(int fd)
{
    unsigned char *p = mmap(0, 2 * PG, PROT_READ | PROT_WRITE, MAP_PRIVATE, fd, 0);
    if (p == MAP_FAILED) return 2;
    p[0] = 9;
    return p[0] == 9 ? 0 : 3;
}

int main(void)
{
    unlink(PATH);
    int fd = open(PATH, O_RDWR | O_CREAT | O_TRUNC, 0644);
    if (fd < 0) { FAIL("setup", "open errno=%d", errno); return 0; }
    static unsigned char pat[3 * PG];
    for (int i = 0; i < (int)sizeof pat; i++) pat[i] = (unsigned char)(i * 7 + 3);
    if (write(fd, pat, sizeof pat) != (ssize_t)sizeof pat) { FAIL("setup", "write errno=%d", errno); return 0; }

    unsigned char *m = mmap(0, 3 * PG, PROT_READ | PROT_WRITE, MAP_SHARED, fd, 0);
    CHECKC("shared_map", m != MAP_FAILED);
    if (m == MAP_FAILED) return 0;
    unsigned char *p = mmap(0, 3 * PG, PROT_READ, MAP_PRIVATE, fd, 0);
    CHECKC("private_map", p != MAP_FAILED);
    if (p == MAP_FAILED) return 0;
    m[10] = 55;
    CHECK("private_sees_shared_store", p[10] == 55, "got %d", p[10]);

    CHECK("mprotect_write", mprotect(p, PG, PROT_READ | PROT_WRITE) == 0, "errno=%d", errno);
    unsigned char orig11 = p[11];
    p[10] = 1;
    CHECK("private_store_visible", p[10] == 1, "got %d", p[10]);
    CHECK("shared_unchanged_by_private_store", m[10] == 55, "shared mapping shows %d", m[10]);
    m[11] = 77;
    CHECK("private_page_detached", p[11] == orig11, "private copy shows %d, expected %d", p[11], orig11);
    m[PG + 5] = 88;
    CHECK("untouched_page_still_follows", p[PG + 5] == 88, "got %d", p[PG + 5]);

    pid_t c = fork();
    if (c == 0) {
        if (p[10] != 1) _exit(2);
        p[10] = 2;
        _exit(m[10] == 55 ? 0 : 3);
    }
    int st = 0;
    waitpid(c, &st, 0);
    CHECK("fork_child_sees_private_copy", WIFEXITED(st) && WEXITSTATUS(st) == 0, "child status %d (2 = wrong copy, 3 = shared changed)", WIFEXITED(st) ? WEXITSTATUS(st) : -1);
    CHECK("fork_child_store_isolated", p[10] == 1, "parent shows %d", p[10]);

    c = fork();
    if (c == 0) _exit(child_private_write(fd));
    waitpid(c, &st, 0);
    CHECK("private_writable_map_store", WIFEXITED(st) && WEXITSTATUS(st) == 0, "child status %d (2 = map, 3 = store lost, signal = fault)", WIFEXITED(st) ? WEXITSTATUS(st) : -1);
    CHECK("private_writable_map_isolated", m[0] == pat[0], "shared mapping shows %d", m[0]);

    c = fork();
    if (c == 0) {
        volatile unsigned char *ro = mmap(0, PG, PROT_READ, MAP_PRIVATE, fd, 0);
        if (ro == MAP_FAILED) _exit(2);
        ro[0] = 1;
        _exit(0);
    }
    waitpid(c, &st, 0);
    CHECK("readonly_private_store_faults", WIFSIGNALED(st) && WTERMSIG(st) == SIGSEGV, "child status %x", st);

    CHECK("munmap_private", munmap(p, 3 * PG) == 0, "errno=%d", errno);
    CHECK("shared_alive_after_private_unmap", m[10] == 55 && m[PG + 5] == 88, "shared mapping broken");
    CHECK("munmap_shared", munmap(m, 3 * PG) == 0, "errno=%d", errno);
    CHECK("file_has_shared_store_only", at(10) == 55 && at(0) == pat[0] && at(11) == 77, "file has %d %d %d", at(10), at(0), at(11));
    close(fd);
    unlink(PATH);
    return 0;
}
