#include <dirent.h>

#define SBM_DIR "/tmp/sbmeta"
#define SBM_FILES 100
#define SBM_PATH_LEN 64
#define SBM_MMAP_BYTES (256 * PAGE)

static char sbm_paths[SBM_FILES][SBM_PATH_LEN];

static int sbm_prepare(void)
{
    mkdir(SBM_DIR, 0700);
    for (int i = 0; i < SBM_FILES; i++) {
        snprintf(sbm_paths[i], SBM_PATH_LEN, SBM_DIR "/e%d", i);
        int fd = open(sbm_paths[i], O_WRONLY | O_CREAT | O_TRUNC, 0600);
        if (fd < 0)
            return 0;
        close(fd);
    }
    return 1;
}

static void sbm_cleanup(void)
{
    for (int i = 0; i < SBM_FILES; i++)
        unlink(sbm_paths[i]);
    rmdir(SBM_DIR);
}

static void run_open_close(long n)
{
    for (long i = 0; i < n; i++) {
        int fd = open(sbm_paths[i % SBM_FILES], O_RDONLY);
        if (fd < 0)
            exit(11);
        close(fd);
    }
}

static void run_stat_path(long n)
{
    struct stat st;
    for (long i = 0; i < n; i++)
        stat(sbm_paths[i % SBM_FILES], &st);
}

static void run_stat_missing(long n)
{
    struct stat st;
    for (long i = 0; i < n; i++)
        stat(SBM_DIR "/nonexistent", &st);
}

static void run_readdir(long n)
{
    for (long i = 0; i < n; i++) {
        DIR *d = opendir(SBM_DIR);
        if (!d)
            exit(12);
        while (readdir(d))
            ;
        closedir(d);
    }
}

static void run_mmap_munmap(long n)
{
    for (long i = 0; i < n; i++) {
        char *m = mmap(0, SBM_MMAP_BYTES, PROT_READ | PROT_WRITE, MAP_PRIVATE | MAP_ANONYMOUS, -1, 0);
        if (m == MAP_FAILED)
            exit(13);
        munmap(m, SBM_MMAP_BYTES);
    }
}

static void sbm_run_all(void)
{
    if (!sbm_prepare()) {
        emit_fail("open_close");
        return;
    }
    measure("open_close", run_open_close, 1000, 1, 1);
    measure("stat_path", run_stat_path, 1000, 1, 1);
    measure("stat_missing", run_stat_missing, 1000, 1, 1);
    measure("readdir_100", run_readdir, 20, 1, 1);
    measure("mmap_munmap_1mib", run_mmap_munmap, 200, 1, 1);
    sbm_cleanup();
}
