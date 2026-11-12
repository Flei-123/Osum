#include <dirent.h>

#define PB_ROOT "/tmp/pb"
#define PB_DEEP PB_ROOT "/a/b/c/d/e"
#define PB_DEEP_FILE PB_DEEP "/f"
#define PB_FLAT_FILE PB_ROOT "/f"
#define PB_MISSING PB_ROOT "/missing"
#define PB_BIG PB_ROOT "/big"
#define PB_BIG_COUNT 1000
#define PB_BIG_NAME_LEN 64

static void pb_touch(const char *path)
{
    int fd = open(path, O_WRONLY | O_CREAT | O_TRUNC, 0600);
    if (fd < 0)
        exit(11);
    close(fd);
}

static void pb_prepare(void)
{
    static const char *dirs[] = {PB_ROOT, PB_ROOT "/a", PB_ROOT "/a/b", PB_ROOT "/a/b/c", PB_ROOT "/a/b/c/d", PB_DEEP, PB_BIG};
    for (unsigned i = 0; i < sizeof dirs / sizeof dirs[0]; i++)
        mkdir(dirs[i], 0700);
    pb_touch(PB_FLAT_FILE);
    pb_touch(PB_DEEP_FILE);
    char name[PB_BIG_NAME_LEN];
    for (int i = 0; i < PB_BIG_COUNT; i++) {
        snprintf(name, sizeof name, PB_BIG "/file_%04d", i);
        pb_touch(name);
    }
}

static void pb_cleanup(void)
{
    char name[PB_BIG_NAME_LEN];
    for (int i = 0; i < PB_BIG_COUNT; i++) {
        snprintf(name, sizeof name, PB_BIG "/file_%04d", i);
        unlink(name);
    }
    unlink(PB_DEEP_FILE);
    unlink(PB_FLAT_FILE);
    rmdir(PB_BIG);
    rmdir(PB_DEEP);
    rmdir(PB_ROOT "/a/b/c/d");
    rmdir(PB_ROOT "/a/b/c");
    rmdir(PB_ROOT "/a/b");
    rmdir(PB_ROOT "/a");
    rmdir(PB_ROOT);
}

static void run_open_close(long n)
{
    for (long i = 0; i < n; i++)
        close(open(PB_FLAT_FILE, O_RDONLY));
}

static void run_open_close_deep(long n)
{
    for (long i = 0; i < n; i++)
        close(open(PB_DEEP_FILE, O_RDONLY));
}

static void run_stat_flat(long n)
{
    struct stat st;
    for (long i = 0; i < n; i++)
        stat(PB_FLAT_FILE, &st);
}

static void run_stat_deep(long n)
{
    struct stat st;
    for (long i = 0; i < n; i++)
        stat(PB_DEEP_FILE, &st);
}

static void run_stat_missing(long n)
{
    struct stat st;
    for (long i = 0; i < n; i++)
        stat(PB_MISSING, &st);
}

static void run_access_flat(long n)
{
    for (long i = 0; i < n; i++)
        access(PB_FLAT_FILE, R_OK);
}

static void run_readdir_big(long n)
{
    for (long i = 0; i < n; i++) {
        DIR *d = opendir(PB_BIG);
        while (readdir(d))
            ;
        closedir(d);
    }
}

static void run_stat_big_entry(long n)
{
    struct stat st;
    char name[PB_BIG_NAME_LEN];
    for (long i = 0; i < n; i++) {
        snprintf(name, sizeof name, PB_BIG "/file_%04ld", (i * 397) % PB_BIG_COUNT);
        stat(name, &st);
    }
}

static void pb_measure(const char *name, bench_fn fn, long batch, long ops_per_item)
{
    if (!selected(name) || (only_filter && !strstr(name, only_filter)))
        return;
    long total = 0;
    long long pa[PROF_N], pb[PROF_N];
    prof_read(pa);
    long long t0 = now_ns();
    long long elapsed;
    do {
        fn(batch);
        total += batch;
        elapsed = now_ns() - t0;
    } while (elapsed < min_ns && elapsed < MAX_NS);
    prof_read(pb);
    emit(name, (double)elapsed / (double)(total * ops_per_item), total * ops_per_item);
    prof_emit(name, pa, pb, total * ops_per_item);
}

static void pb_run_all(void)
{
    pb_prepare();
    pb_measure("open_close", run_open_close, 2000, 1);
    pb_measure("open_close_deep", run_open_close_deep, 2000, 1);
    pb_measure("stat_flat", run_stat_flat, 2000, 1);
    pb_measure("stat_deep", run_stat_deep, 2000, 1);
    pb_measure("stat_missing", run_stat_missing, 2000, 1);
    pb_measure("access_flat", run_access_flat, 2000, 1);
    pb_measure("readdir_1000_entry", run_readdir_big, 10, PB_BIG_COUNT);
    pb_measure("stat_big_dir_entry", run_stat_big_entry, 2000, 1);
    pb_cleanup();
}
