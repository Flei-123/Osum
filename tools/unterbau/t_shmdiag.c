/* SPDX-License-Identifier: GPL-2.0-only
 * Shared-memory failure diagnostics (kernel/diag/shmdiag.fi): every failing memfd_create / ftruncate(memfd) / mmap(MAP_SHARED) bumps a
 * counter in /proc/meminfo (ShmFail*) and writes a rate-limited klog line "shm fail <op> e<errno> shm <live>/<max> free <n> low <n>". */
#define TNAME "shmdiag"
#include "t.h"
#include <fcntl.h>
#include <stdlib.h>
#include <sys/mman.h>
#include <sys/syscall.h>

#define MAX_MEMFDS 1200
#define MAX_MAPS 100000

static char meminfo[8192];
static char klog[262144];

static long field(const char *name)
{
    int fd = open("/proc/meminfo", O_RDONLY);
    int n = fd < 0 ? 0 : read(fd, meminfo, sizeof meminfo - 1);
    if (fd >= 0) close(fd);
    meminfo[n > 0 ? n : 0] = 0;
    char *p = strstr(meminfo, name);
    return p ? strtol(p + strlen(name), 0, 10) : -1;
}

static int read_klog(void)
{
    int fd = open("/proc/klog", O_RDONLY);
    int n = 0, r;
    while (fd >= 0 && n < (int)sizeof klog - 1 && (r = read(fd, klog + n, sizeof klog - 1 - n)) > 0) n += r;
    if (fd >= 0) close(fd);
    klog[n] = 0;
    return n;
}

static int memfd(void) { return syscall(SYS_memfd_create, "shmdiag", 0); }

int main(void)
{
    long m0 = field("ShmFailMemfd:"), t0 = field("ShmFailTruncate:"), s0 = field("ShmFailMmap:");
    CHECK("counters_exposed", m0 >= 0 && t0 >= 0 && s0 >= 0 && field("ShmFailScm:") >= 0 && field("ShmFailErrno:") >= 0 && field("FramesFreeLow:") > 0,
        "memfd=%ld trunc=%ld mmap=%ld", m0, t0, s0);

    int ok = memfd();
    CHECK("success_not_counted", ok >= 0 && field("ShmFailMemfd:") == m0, "fd=%d", ok);

    long len = 1L << 40;
    errno = 0;
    int rc = ftruncate(ok, len);
    int trunc_errno = errno;
    CHECK("truncate_fails", rc < 0, "rc=%d", rc);
    CHECK("truncate_counted", field("ShmFailTruncate:") == t0 + 1 && field("ShmFailErrno:") == trunc_errno, "count=%ld want=%ld errno=%ld got=%d",
        field("ShmFailTruncate:"), t0 + 1, field("ShmFailErrno:"), trunc_errno);

    ftruncate(ok, 4096);
    void *maps[MAX_MAPS];
    int nm = 0, map_errno = 0;
    for (; nm < MAX_MAPS; nm++) {
        maps[nm] = mmap(0, 4096, PROT_READ | PROT_WRITE, MAP_SHARED, ok, 0);
        if (maps[nm] == MAP_FAILED) { map_errno = errno; break; }
    }
    long s1 = field("ShmFailMmap:");
    CHECK("mmap_flood_fails", nm < MAX_MAPS && map_errno == ENOMEM, "mapped=%d errno=%d", nm, map_errno);
    CHECK("mmap_counted", s1 == s0 + 1 && field("ShmFailErrno:") == map_errno, "count=%ld want=%ld errno=%ld got=%d", s1, s0 + 1, field("ShmFailErrno:"), map_errno);
    for (int i = 0; i < nm; i++) munmap(maps[i], 4096);

    int rf = open("/etc/passwd", O_RDONLY);
    long s2 = field("ShmFailMmap:"), fnm = 0, file_errno = 0;
    for (; fnm < MAX_MAPS; fnm++) {
        maps[fnm] = mmap(0, 4096, PROT_READ, MAP_SHARED, rf, 0);
        if (maps[fnm] == MAP_FAILED) { file_errno = errno; break; }
    }
    CHECK("file_map_flood_counted", file_errno == ENOMEM && field("ShmFailMmap:") == s2 + 1, "mapped=%ld errno=%ld count=%ld want=%ld", fnm, file_errno, field("ShmFailMmap:"), s2 + 1);
    for (long i = 0; i < fnm; i++) munmap(maps[i], 4096);
    close(rf);

    int fds[MAX_MEMFDS], n = 0, fail_errno = 0;
    for (; n < MAX_MEMFDS; n++) {
        fds[n] = memfd();
        if (fds[n] < 0) { fail_errno = errno; break; }
    }
    int flood_fds = n;
    for (int i = 0; i < n; i++) close(fds[i]);
    n = 0;
    long m1 = field("ShmFailMemfd:");
    CHECK("memfd_flood_fails", flood_fds < MAX_MEMFDS && fail_errno != 0, "created=%d errno=%d", flood_fds, fail_errno);
    CHECK("memfd_counted", m1 >= m0 + 1 && field("ShmFailErrno:") == fail_errno, "count=%ld base=%ld errno=%ld want=%d", m1, m0, field("ShmFailErrno:"), fail_errno);
    CHECK("free_low_reported", field("ShmFailFreeLow:") > 0, "low=%ld", field("ShmFailFreeLow:"));

    read_klog();
    char *line = strstr(klog, "shm fail memfd e");
    CHECK("klog_line_memfd", line != 0, "no 'shm fail memfd e' line in /proc/klog");
    CHECK("klog_line_fields", line && strstr(line, " shm ") && strstr(line, " free ") && strstr(line, " low "), "line=%.80s", line ? line : "(none)");
    CHECK("klog_line_truncate", strstr(klog, "shm fail ftruncate e27 len 1099511627776 shm") != 0, "no 'shm fail ftruncate e27 len 1099511627776' line");
    CHECK("klog_line_mmap", strstr(klog, "shm fail mmap e12 len 4096 shm") != 0, "no 'shm fail mmap e12 len 4096' line");

    close(ok);
    for (int i = 0; i < 200; i++) memfd();
    long m2 = field("ShmFailMemfd:");
    CHECK("ratelimit_counts_all", m2 >= m1, "m1=%ld m2=%ld", m1, m2);
    return 0;
}
