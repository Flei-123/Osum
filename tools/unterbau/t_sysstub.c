#define TNAME "sysstub"
#include "t.h"
#include <signal.h>
#include <stdlib.h>
#include <sys/mman.h>
#include <sys/syscall.h>
#include <sys/wait.h>

#ifndef SYS_pkey_mprotect
#define SYS_pkey_mprotect 329
#define SYS_pkey_alloc 330
#define SYS_pkey_free 331
#endif

static long sc(long nr, long a, long b, long c, long d, long e)
{
    errno = 0;
    return syscall(nr, a, b, c, d, e, 0L);
}

static void test_syslog(void)
{
    long size = sc(103, 10, 0, 0, 0, 0);
    CHECK("syslog_size", size > 0, "size=%ld errno=%d", size, errno);
    char *buf = malloc(size > 0 ? size : 1);
    long n = sc(103, 3, (long)buf, size, 0, 0);
    CHECK("syslog_read_all", n > 0 && n <= size, "n=%ld errno=%d", n, errno);
    CHECK("syslog_ends_newline", n > 0 && buf[n - 1] == '\n', "last=%d", n > 0 ? buf[n - 1] : -1);
    char small[64];
    long m = sc(103, 3, (long)small, sizeof small, 0, 0);
    CHECK("syslog_tail_fits", m > 0 && m <= (long)sizeof small && (m == 0 || small[m - 1] == '\n'), "m=%ld", m);
    CHECK("syslog_bad_type", sc(103, 99, 0, 0, 0, 0) == -1 && errno == EINVAL, "errno=%d", errno);
    CHECK("syslog_null_buf", sc(103, 3, 0, 16, 0, 0) == -1 && errno == EINVAL, "errno=%d", errno);
    CHECK("syslog_fault", sc(103, 3, 1, 16, 0, 0) == -1 && errno == EFAULT, "errno=%d", errno);
    CHECK("syslog_level_range", sc(103, 8, 0, 9, 0, 0) == -1 && errno == EINVAL, "errno=%d", errno);
    CHECK("syslog_level_ok", sc(103, 8, 0, 4, 0, 0) == 0, "errno=%d", errno);
    free(buf);
}

static void test_mempolicy(void)
{
    int mode = -1;
    unsigned long mask[2] = {~0UL, ~0UL};
    long r = sc(239, (long)&mode, (long)mask, 64, 0, 0);
    CHECK("get_mempolicy", r == 0 && mode == 0 && mask[0] == 0, "r=%ld mode=%d mask=%lx errno=%d", r, mode, mask[0], errno);
    mask[0] = 0;
    r = sc(239, 0, (long)mask, 64, 0, 4);
    CHECK("get_mempolicy_allowed", r == 0 && mask[0] == 1, "r=%ld mask=%lx", r, mask[0]);
    CHECK("get_mempolicy_bad_flags", sc(239, 0, 0, 0, 0, 0x80) == -1 && errno == EINVAL, "errno=%d", errno);
    CHECK("set_mempolicy", sc(238, 0, 0, 0, 0, 0) == 0, "errno=%d", errno);
    CHECK("set_mempolicy_bad_mode", sc(238, 77, 0, 0, 0, 0) == -1 && errno == EINVAL, "errno=%d", errno);
    void *p = mmap(0, 8192, PROT_READ | PROT_WRITE, MAP_PRIVATE | MAP_ANONYMOUS, -1, 0);
    CHECK("mbind", p != MAP_FAILED && sc(237, (long)p, 8192, 0, 0, 0) == 0, "errno=%d", errno);
    CHECK("mbind_unaligned", sc(237, (long)p + 1, 4096, 0, 0, 0) == -1 && errno == EINVAL, "errno=%d", errno);
    munmap(p, 8192);
}

static void test_pkey(void)
{
    CHECK("pkey_alloc_nospc", sc(SYS_pkey_alloc, 0, 0, 0, 0, 0) == -1 && errno == ENOSPC, "errno=%d", errno);
    CHECK("pkey_alloc_flags", sc(SYS_pkey_alloc, 1, 0, 0, 0, 0) == -1 && errno == EINVAL, "errno=%d", errno);
    CHECK("pkey_free_invalid", sc(SYS_pkey_free, 3, 0, 0, 0, 0) == -1 && errno == EINVAL, "errno=%d", errno);
    char *p = mmap(0, 4096, PROT_READ | PROT_WRITE, MAP_PRIVATE | MAP_ANONYMOUS, -1, 0);
    p[0] = 1;
    long r = sc(SYS_pkey_mprotect, (long)p, 4096, PROT_READ, -1, 0);
    CHECK("pkey_mprotect_none", r == 0, "r=%ld errno=%d", r, errno);
    pid_t pid = fork();
    if (pid == 0) {
        signal(SIGSEGV, SIG_DFL);
        p[0] = 2;
        _exit(0);
    }
    int st = 0;
    waitpid(pid, &st, 0);
    CHECK("pkey_mprotect_applies", WIFSIGNALED(st) && WTERMSIG(st) == SIGSEGV, "st=%d", st);
    CHECK("pkey_mprotect_key3", sc(SYS_pkey_mprotect, (long)p, 4096, PROT_READ, 3, 0) == -1 && errno == EINVAL, "errno=%d", errno);
    munmap(p, 4096);
}

static void test_refusals(void)
{
    CHECK("perf_event_open_acces", sc(298, 0, 0, -1, -1, 0) == -1 && errno == EACCES, "errno=%d", errno);
    CHECK("fanotify_init_perm", sc(300, 0, 0, 0, 0, 0) == -1 && errno == EPERM, "errno=%d", errno);
    CHECK("name_to_handle_at_notsup", sc(303, -100, (long)"/", 0, 0, 0) == -1 && errno == EOPNOTSUPP, "errno=%d", errno);
    CHECK("process_madvise_flags", sc(440, -1, 0, 0, 0, 1) == -1 && errno == EINVAL, "errno=%d", errno);
}

int main(void)
{
    alarm(60);
    test_syslog();
    test_mempolicy();
    test_pkey();
    test_refusals();
    return 0;
}
