#define TNAME "procbig"
#include "t.h"
#include <dirent.h>
#include <fcntl.h>
#include <pthread.h>
#include <stdlib.h>
#include <sys/mman.h>
#include <sys/stat.h>
#include <sys/syscall.h>

#define MAP_PAGES 800
#define BIG_BUF (1 << 20)
#define CHUNK 100
#define THREADS 3

static volatile int stop_threads;
static volatile long thread_tid[THREADS];

static int slurp(const char *path, char *b, int n, int chunk)
{
    int fd = open(path, O_RDONLY);
    if (fd < 0) return -1;
    int t = 0, r;
    while (t < n - 1 && (r = read(fd, b + t, chunk < n - 1 - t ? chunk : n - 1 - t)) > 0) t += r;
    close(fd);
    b[t] = 0;
    return t;
}

static void *thread_main(void *arg)
{
    long i = (long)arg;
    thread_tid[i] = syscall(SYS_gettid);
    while (!stop_threads) usleep(10000);
    return 0;
}

static int count_lines(const char *b)
{
    int n = 0;
    for (; *b; b++) if (*b == '\n') n++;
    return n;
}

static int count_substr(const char *b, const char *needle)
{
    int n = 0;
    size_t l = strlen(needle);
    for (; (b = strstr(b, needle)); b += l) n++;
    return n;
}

int main(void)
{
    static char whole[BIG_BUF], pieces[BIG_BUF];
    char *area = mmap(0, MAP_PAGES * 4096UL, PROT_READ | PROT_WRITE, MAP_PRIVATE | MAP_ANONYMOUS, -1, 0);
    errno = 0;
    CHECKC("maps_region", area != MAP_FAILED);
    if (area == MAP_FAILED) return 0;
    for (int i = 1; i < MAP_PAGES; i += 2) mprotect(area + i * 4096UL, 4096, PROT_READ);

    errno = 0;
    int n = slurp("/proc/self/maps", whole, sizeof whole, BIG_BUF);
    CHECKC("maps_open", n > 0);
    CHECK("maps_over_4096", n > 4096, "only %d bytes", n);
    CHECK("maps_over_one_line_per_split", count_lines(whole) >= MAP_PAGES, "lines=%d want >= %d", count_lines(whole), MAP_PAGES);
    char last[32];
    snprintf(last, sizeof last, "%lx-", (unsigned long)(area + (MAP_PAGES - 1) * 4096UL));
    CHECK("maps_last_split_listed", strstr(whole, last) != 0, "last page %s missing from %d bytes", last, n);
    CHECK("maps_tail_whole_line", n > 0 && whole[n - 1] == '\n', "ends with 0x%02x", n > 0 ? whole[n - 1] : 0);
    int m = slurp("/proc/self/maps", pieces, sizeof pieces, CHUNK);
    CHECK("maps_chunked_size", m == n, "chunked=%d whole=%d", m, n);
    struct stat st;
    errno = 0;
    CHECK("maps_fstat_size", stat("/proc/self/maps", &st) == 0 && st.st_size >= n - 256, "st_size=%ld n=%d", (long)st.st_size, n);

    errno = 0;
    n = slurp("/proc/cpuinfo", whole, sizeof whole, BIG_BUF);
    CHECKC("cpuinfo_open", n > 0);
    long cpus = sysconf(_SC_NPROCESSORS_ONLN);
    CHECK("cpuinfo_all_cpus", n > 0 && count_substr(whole, "processor") >= cpus, "processor lines=%d cpus=%ld", count_substr(whole, "processor"), cpus);
    CHECK("cpuinfo_chunked_same", slurp("/proc/cpuinfo", pieces, sizeof pieces, CHUNK) == n, "chunked read differs from %d", n);

    errno = 0;
    n = slurp("/proc/meminfo", whole, sizeof whole, BIG_BUF);
    CHECKC("meminfo_open", n > 0);
    CHECK("meminfo_keys", strstr(whole, "MemTotal:") && strstr(whole, "MemAvailable:"), "keys missing");
    CHECK("meminfo_chunked_same", slurp("/proc/meminfo", pieces, sizeof pieces, CHUNK) == n, "chunked read differs from %d", n);

    pthread_t th[THREADS];
    for (long i = 0; i < THREADS; i++) pthread_create(&th[i], 0, thread_main, (void *)i);
    usleep(100000);
    char path[96];
    snprintf(path, sizeof path, "/proc/%d/task", (int)getpid());
    DIR *d = opendir(path);
    errno = 0;
    CHECKC("task_dir_open", d != 0);
    int entries = 0, found[THREADS] = {0}, self_found = 0;
    struct dirent *e;
    while (d && (e = readdir(d))) {
        if (e->d_name[0] == '.') continue;
        entries++;
        long tid = atol(e->d_name);
        if (tid == getpid()) self_found = 1;
        for (int i = 0; i < THREADS; i++) if (tid == thread_tid[i]) found[i] = 1;
    }
    if (d) closedir(d);
    CHECK("task_dir_count", entries == THREADS + 1, "entries=%d want %d", entries, THREADS + 1);
    CHECK("task_dir_lists_all", self_found && found[0] && found[1] && found[2], "self=%d t0=%d t1=%d t2=%d", self_found, found[0], found[1], found[2]);
    int good_stat = 1, good_status = 1, good_comm = 1;
    for (int i = 0; i < THREADS; i++) {
        char b[2048];
        snprintf(path, sizeof path, "/proc/self/task/%ld/stat", thread_tid[i]);
        if (slurp(path, b, sizeof b, sizeof b) <= 0 || atol(b) != thread_tid[i] || !strchr(b, '(')) good_stat = 0;
        snprintf(path, sizeof path, "/proc/self/task/%ld/status", thread_tid[i]);
        if (slurp(path, b, sizeof b, sizeof b) <= 0 || !strstr(b, "Tgid:") || !strstr(b, "Pid:")) good_status = 0;
        snprintf(path, sizeof path, "/proc/self/task/%ld/comm", thread_tid[i]);
        if (slurp(path, b, sizeof b, sizeof b) <= 1) good_comm = 0;
    }
    CHECK("task_stat_per_thread", good_stat, "a thread stat is wrong");
    CHECK("task_status_per_thread", good_status, "a thread status lacks Tgid/Pid");
    CHECK("task_comm_per_thread", good_comm, "a thread comm is empty");
    snprintf(path, sizeof path, "/proc/self/task/%ld/stat", thread_tid[0] + 100000);
    errno = 0;
    CHECK("task_unknown_tid_enoent", open(path, O_RDONLY) < 0 && errno == ENOENT, "errno=%d", errno);
    stop_threads = 1;
    for (int i = 0; i < THREADS; i++) pthread_join(th[i], 0);
    return 0;
}
