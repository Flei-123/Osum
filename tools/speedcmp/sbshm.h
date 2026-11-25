#define SBSHM_SMALL (64 * 1024)
#define SBSHM_LARGE (1024 * 1024)

static void sbshm_grow(long n, off_t len)
{
    for (long i = 0; i < n; i++) {
        int fd = syscall(SYS_memfd_create, "sb", 0);
        if (fd < 0)
            return;
        ftruncate(fd, len);
        close(fd);
    }
}

static void run_memfd_ftruncate_64k(long n)
{
    sbshm_grow(n, SBSHM_SMALL);
}

static void run_memfd_ftruncate_1m(long n)
{
    sbshm_grow(n, SBSHM_LARGE);
}

static void sbshm_run_all(void)
{
    measure("memfd_ftruncate_64k", run_memfd_ftruncate_64k, 500, 1, 1);
    measure("memfd_ftruncate_1m", run_memfd_ftruncate_1m, 100, 1, 1);
}
