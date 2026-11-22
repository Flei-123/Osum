#define TNAME "procsmaps"
#include "t.h"
#include <dirent.h>
#include <fcntl.h>
#include <stdlib.h>
#include <sys/mman.h>
#include <sys/stat.h>
#include <sys/wait.h>
#include <time.h>

#define BUF_BYTES (2 * 1024 * 1024)
#define PAGE_BYTES 4096
#define REGION_PAGES 16
#define TOUCHED_PAGES 3
#define MANY_VMAS 400
#define WINDOW_BYTES 131072
#define LAZY_BYTES (16 * 1024 * 1024)
#define CHUNK_BYTES 1000
#define INTERLEAVE_SLACK 3
#define INTERLEAVE_FLOOR_NS 20000000L

static char maps_buf[BUF_BYTES];
static char smaps_buf[BUF_BYTES];
static char other_buf[BUF_BYTES];
static char other2_buf[BUF_BYTES];

static long slurp(const char *path, char *buf)
{
    int fd = open(path, O_RDONLY);
    if (fd < 0)
        return -1;
    long total = 0;
    for (;;) {
        long n = read(fd, buf + total, BUF_BYTES - 1 - total);
        if (n <= 0)
            break;
        total += n;
    }
    close(fd);
    buf[total] = 0;
    return total;
}

static int is_header(const char *line)
{
    const char *p = line;
    int digits = 0;
    while ((*p >= '0' && *p <= '9') || (*p >= 'a' && *p <= 'f')) {
        p++;
        digits++;
    }
    return digits >= 8 && *p == '-';
}

static long count_headers(const char *buf)
{
    long n = 0;
    const char *p = buf;
    while (*p) {
        if (is_header(p))
            n++;
        const char *nl = strchr(p, '\n');
        if (!nl)
            break;
        p = nl + 1;
    }
    return n;
}

static long count_prefix(const char *buf, const char *prefix)
{
    long n = 0;
    size_t len = strlen(prefix);
    const char *p = buf;
    while (*p) {
        if (strncmp(p, prefix, len) == 0)
            n++;
        const char *nl = strchr(p, '\n');
        if (!nl)
            break;
        p = nl + 1;
    }
    return n;
}

static const char *find_block(const char *buf, unsigned long start)
{
    const char *p = buf;
    while (*p) {
        if (is_header(p) && strtoul(p, 0, 16) == start)
            return p;
        const char *nl = strchr(p, '\n');
        if (!nl)
            break;
        p = nl + 1;
    }
    return 0;
}

static long field_kb(const char *block, const char *name)
{
    char key[40];
    snprintf(key, sizeof key, "\n%s:", name);
    const char *end = block + 1;
    while (*end && !(end[-1] == '\n' && is_header(end)))
        end++;
    const char *p = strstr(block, key);
    if (!p || p >= end)
        return -1;
    return strtol(p + strlen(key), 0, 10);
}

static int block_has_flag(const char *block, const char *flag)
{
    const char *p = strstr(block, "\nVmFlags:");
    if (!p)
        return 0;
    const char *eol = strchr(p + 1, '\n');
    char needle[8];
    snprintf(needle, sizeof needle, " %s", flag);
    const char *hit = strstr(p, needle);
    return hit && (!eol || hit < eol);
}

static void test_basic(void)
{
    char *region = mmap(0, REGION_PAGES * PAGE_BYTES, PROT_READ | PROT_WRITE, MAP_PRIVATE | MAP_ANONYMOUS, -1, 0);
    for (int i = 0; i < TOUCHED_PAGES; i++)
        region[i * PAGE_BYTES] = 1;
    long maps_len = slurp("/proc/self/maps", maps_buf);
    long smaps_len = slurp("/proc/self/smaps", smaps_buf);
    CHECK("smaps_readable", smaps_len > 0, "len=%ld errno=%d", smaps_len, errno);
    if (smaps_len <= 0)
        return;
    long mh = count_headers(maps_buf);
    long sh = count_headers(smaps_buf);
    CHECK("smaps_header_count_matches_maps", maps_len > 0 && mh == sh, "maps=%ld smaps=%ld", mh, sh);
    long sizes = count_prefix(smaps_buf, "Size:");
    long flags = count_prefix(smaps_buf, "VmFlags:");
    CHECK("smaps_every_block_complete", sizes == sh && flags == sh, "headers=%ld size=%ld vmflags=%ld", sh, sizes, flags);
    const char *block = find_block(smaps_buf, (unsigned long)region);
    CHECK("smaps_region_found", block != 0, "region=%p", (void *)region);
    if (!block)
        return;
    long size = field_kb(block, "Size");
    long rss = field_kb(block, "Rss");
    CHECK("smaps_size_kb", size == REGION_PAGES * 4, "size=%ld", size);
    CHECK("smaps_rss_covers_touched_pages", rss >= TOUCHED_PAGES * 4 && rss <= size, "rss=%ld", rss);
    CHECK("smaps_anon_private_dirty", field_kb(block, "Private_Dirty") == rss && field_kb(block, "Anonymous") == rss, "pd=%ld an=%ld", field_kb(block, "Private_Dirty"), field_kb(block, "Anonymous"));
    CHECK("smaps_fields_present", field_kb(block, "Pss") >= 0 && field_kb(block, "Swap") == 0 && field_kb(block, "Referenced") == rss
        && field_kb(block, "KernelPageSize") == 4 && field_kb(block, "MMUPageSize") == 4 && field_kb(block, "Shared_Clean") == 0, "pss=%ld", field_kb(block, "Pss"));
    CHECK("smaps_vmflags", block_has_flag(block, "rd") && block_has_flag(block, "wr") && !block_has_flag(block, "ex"), "flags missing");
    munmap(region, REGION_PAGES * PAGE_BYTES);
}

static void test_lazy(void)
{
    char *big = mmap(0, LAZY_BYTES, PROT_READ | PROT_WRITE, MAP_PRIVATE | MAP_ANONYMOUS, -1, 0);
    big[0] = 1;
    slurp("/proc/self/smaps", smaps_buf);
    const char *block = find_block(smaps_buf, (unsigned long)big);
    long size = block ? field_kb(block, "Size") : -1;
    long rss = block ? field_kb(block, "Rss") : -1;
    CHECK("smaps_rss_below_size_for_untouched", block && size == LAZY_BYTES / 1024 && rss >= 4 && rss < size, "size=%ld rss=%ld", size, rss);
    munmap(big, LAZY_BYTES);
}

static void test_many(void)
{
    char *base = mmap(0, MANY_VMAS * PAGE_BYTES, PROT_READ | PROT_WRITE, MAP_PRIVATE | MAP_ANONYMOUS, -1, 0);
    for (int i = 1; i < MANY_VMAS; i += 2)
        mprotect(base + i * PAGE_BYTES, PAGE_BYTES, PROT_READ);
    long maps_len = slurp("/proc/self/maps", maps_buf);
    long smaps_len = slurp("/proc/self/smaps", smaps_buf);
    long mh = count_headers(maps_buf);
    long sh = count_headers(smaps_buf);
    CHECK("smaps_larger_than_one_window", smaps_len > WINDOW_BYTES, "len=%ld", smaps_len);
    CHECK("smaps_windowed_headers_match", maps_len > 0 && mh == sh && sh >= MANY_VMAS, "maps=%ld smaps=%ld", mh, sh);
    CHECK("smaps_windowed_blocks_complete", count_prefix(smaps_buf, "VmFlags:") == sh, "vmflags=%ld headers=%ld", count_prefix(smaps_buf, "VmFlags:"), sh);
    munmap(base, MANY_VMAS * PAGE_BYTES);
}

static long slurp_chunked(const char *path, char *buf)
{
    int fd = open(path, O_RDONLY);
    if (fd < 0)
        return -1;
    long total = 0;
    for (;;) {
        long n = read(fd, buf + total, CHUNK_BYTES);
        if (n <= 0)
            break;
        total += n;
    }
    close(fd);
    buf[total] = 0;
    return total;
}

static void test_chunked(void)
{
    long whole_len = slurp("/proc/self/smaps", smaps_buf);
    long chunk_len = slurp_chunked("/proc/self/smaps", maps_buf);
    CHECK("smaps_chunked_same_length", whole_len > 0 && whole_len == chunk_len, "whole=%ld chunked=%ld", whole_len, chunk_len);
    CHECK("smaps_chunked_same_headers", count_headers(smaps_buf) == count_headers(maps_buf), "whole=%ld chunked=%ld", count_headers(smaps_buf), count_headers(maps_buf));
    CHECK("smaps_chunked_blocks_complete", count_prefix(maps_buf, "VmFlags:") == count_headers(maps_buf), "vmflags=%ld headers=%ld", count_prefix(maps_buf, "VmFlags:"), count_headers(maps_buf));
}

static long elapsed_ns(const struct timespec *a)
{
    struct timespec b;
    clock_gettime(CLOCK_MONOTONIC, &b);
    return (b.tv_sec - a->tv_sec) * 1000000000L + (b.tv_nsec - a->tv_nsec);
}

static long read_step(int fd, char *buf, long *total)
{
    if (fd < 0)
        return 0;
    long n = read(fd, buf + *total, CHUNK_BYTES);
    if (n > 0)
        *total += n;
    return n;
}

static long slurp_interleaved(const char *a, const char *b, long *len_b)
{
    int fa = open(a, O_RDONLY);
    int fb = open(b, O_RDONLY);
    long ta = 0, tb = 0;
    int more_a = fa >= 0, more_b = fb >= 0;
    while (more_a || more_b) {
        if (more_a && read_step(fa, maps_buf, &ta) <= 0)
            more_a = 0;
        if (more_b && read_step(fb, other_buf, &tb) <= 0)
            more_b = 0;
    }
    if (fa >= 0)
        close(fa);
    if (fb >= 0)
        close(fb);
    *len_b = tb;
    return ta;
}

static void test_interleaved(void)
{
    char *base = mmap(0, MANY_VMAS * PAGE_BYTES, PROT_READ | PROT_WRITE, MAP_PRIVATE | MAP_ANONYMOUS, -1, 0);
    for (int i = 1; i < MANY_VMAS; i += 2)
        mprotect(base + i * PAGE_BYTES, PAGE_BYTES, PROT_READ);
    int fd[2];
    if (pipe(fd) != 0)
        return;
    pid_t pid = fork();
    if (pid == 0) {
        char c;
        close(fd[1]);
        (void)!read(fd[0], &c, 1);
        _exit(0);
    }
    close(fd[0]);
    char path[48];
    snprintf(path, sizeof path, "/proc/%d/smaps", (int)pid);
    struct timespec t0;
    clock_gettime(CLOCK_MONOTONIC, &t0);
    long seq_a = slurp_chunked("/proc/self/smaps", smaps_buf);
    long seq_b = slurp_chunked(path, other2_buf);
    long seq_ns = elapsed_ns(&t0);
    clock_gettime(CLOCK_MONOTONIC, &t0);
    long mix_b = 0;
    long mix_a = slurp_interleaved("/proc/self/smaps", path, &mix_b);
    long mix_ns = elapsed_ns(&t0);
    CHECK("smaps_interleaved_same_length", seq_a > WINDOW_BYTES && seq_a == mix_a && seq_b == mix_b, "seq=%ld/%ld mix=%ld/%ld", seq_a, seq_b, mix_a, mix_b);
    CHECK("smaps_interleaved_not_quadratic", mix_ns <= INTERLEAVE_SLACK * seq_ns + INTERLEAVE_FLOOR_NS, "seq_us=%ld mix_us=%ld", seq_ns / 1000, mix_ns / 1000);
    write(fd[1], "x", 1);
    close(fd[1]);
    waitpid(pid, 0, 0);
    munmap(base, MANY_VMAS * PAGE_BYTES);
}

static void test_other_process(void)
{
    int fd[2];
    if (pipe(fd) != 0)
        return;
    pid_t pid = fork();
    if (pid == 0) {
        char c;
        close(fd[1]);
        (void)!read(fd[0], &c, 1);
        _exit(0);
    }
    close(fd[0]);
    char path[48];
    snprintf(path, sizeof path, "/proc/%d/smaps", (int)pid);
    long len = slurp(path, smaps_buf);
    CHECK("smaps_other_pid", len > 0 && count_headers(smaps_buf) > 0 && count_prefix(smaps_buf, "Rss:") > 0, "len=%ld", len);
    write(fd[1], "x", 1);
    close(fd[1]);
    waitpid(pid, 0, 0);
    errno = 0;
    CHECK("smaps_gone_pid_fails", open(path, O_RDONLY) < 0, "still opens");
}

static void test_listing(void)
{
    DIR *d = opendir("/proc/self");
    int found = 0;
    struct dirent *e;
    while (d && (e = readdir(d)))
        if (strcmp(e->d_name, "smaps") == 0)
            found = 1;
    if (d)
        closedir(d);
    CHECK("smaps_in_pid_dir_listing", found, "missing");
    struct stat st;
    CHECK("smaps_stat_regular", stat("/proc/self/smaps", &st) == 0 && S_ISREG(st.st_mode), "errno=%d", errno);
}

int main(void)
{
    test_basic();
    test_lazy();
    test_many();
    test_chunked();
    test_interleaved();
    test_other_process();
    test_listing();
    return 0;
}
