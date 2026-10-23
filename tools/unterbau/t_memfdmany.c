#define TNAME "memfdmany"
#include "t.h"
#include <fcntl.h>
#include <stdint.h>
#include <sys/mman.h>
#include <sys/syscall.h>
#include <sys/wait.h>

#define MANY 30
#define PAGE 4096

static int fds[MANY];

static int make(int i, size_t pages)
{
    int fd = (int)syscall(SYS_memfd_create, "many", 2);
    if (fd < 0) return -1;
    if (ftruncate(fd, (off_t)(pages * PAGE)) != 0) {
        close(fd);
        return -1;
    }
    unsigned char *p = mmap(0, pages * PAGE, PROT_READ | PROT_WRITE, MAP_SHARED, fd, 0);
    if (p == MAP_FAILED) {
        close(fd);
        return -1;
    }
    p[0] = (unsigned char)(0x40 + i);
    p[(pages - 1) * PAGE + 7] = (unsigned char)(0x80 + i);
    munmap(p, pages * PAGE);
    return fd;
}

static int check(int fd, int i, size_t pages)
{
    unsigned char *p = mmap(0, pages * PAGE, PROT_READ, MAP_SHARED, fd, 0);
    if (p == MAP_FAILED) return 0;
    int ok = p[0] == (unsigned char)(0x40 + i) && p[(pages - 1) * PAGE + 7] == (unsigned char)(0x80 + i);
    munmap(p, pages * PAGE);
    return ok;
}

int main(void)
{
    int created = 0, i;
    for (i = 0; i < MANY; i++) {
        fds[i] = make(i, 2);
        if (fds[i] < 0) break;
        created++;
    }
    CHECKC("create_many", created == MANY);
    int distinct = 1;
    for (i = 0; i < created; i++)
        if (!check(fds[i], i, 2)) distinct = 0;
    CHECK("contents_distinct", distinct, "created=%d", created);
    for (i = 0; i < created; i++) close(fds[i]);

    created = 0;
    for (i = 0; i < MANY; i++) {
        fds[i] = make(i, 2);
        if (fds[i] < 0) break;
        created++;
    }
    CHECKC("create_many_after_close", created == MANY);
    for (i = 0; i < created; i++) close(fds[i]);

    int big = make(5, 300);
    CHECKC("big_300_pages", big >= 0);
    if (big >= 0) {
        CHECK("big_content", check(big, 5, 300), "");
        char path[64];
        snprintf(path, sizeof path, "/proc/self/fd/%d", big);
        int ro = open(path, O_RDONLY);
        CHECKC("reopen_readonly", ro >= 0);
        if (ro >= 0) {
            CHECK("reopen_content", check(ro, 5, 300), "");
            errno = 0;
            void *w = mmap(0, PAGE, PROT_READ | PROT_WRITE, MAP_SHARED, ro, 0);
            CHECK("reopen_not_writable", w == MAP_FAILED, "errno=%d", errno);
            close(ro);
        }
        close(big);
    }

    int shared = make(9, 3);
    CHECKC("shared_create", shared >= 0);
    if (shared >= 0) {
        pid_t c = fork();
        if (c == 0) {
            unsigned char *p = mmap(0, 3 * PAGE, PROT_READ | PROT_WRITE, MAP_SHARED, shared, 0);
            if (p == MAP_FAILED) _exit(2);
            p[PAGE] = 0x77;
            _exit(0);
        }
        int st = 0;
        waitpid(c, &st, 0);
        unsigned char *p = mmap(0, 3 * PAGE, PROT_READ, MAP_SHARED, shared, 0);
        CHECK("shared_child_write_seen", c > 0 && WIFEXITED(st) && WEXITSTATUS(st) == 0 && p != MAP_FAILED && p[PAGE] == 0x77, "st=%d", st);
        close(shared);
    }

    int n = 0, total = 0;
    int *all = mmap(0, 256 * sizeof(int), PROT_READ | PROT_WRITE, MAP_PRIVATE | MAP_ANONYMOUS, -1, 0);
    int last_errno = 0;
    for (i = 0; i < 100; i++) {
        errno = 0;
        int fd = (int)syscall(SYS_memfd_create, "many", 2);
        if (fd < 0) {
            last_errno = errno;
            break;
        }
        all[n++] = fd;
        total++;
    }
    CHECK("exhaust_reports_enfile", total >= MANY && (total >= 100 || last_errno == ENFILE || last_errno == EMFILE), "total=%d errno=%d", total, last_errno);
    for (i = 0; i < n; i++) close(all[i]);
    int again = make(1, 1);
    CHECKC("create_after_exhaust", again >= 0);
    if (again >= 0) close(again);
    return 0;
}
