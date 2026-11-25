#define SBR_SMALL 16
#define SBR_LARGE 256

static void sbr_fill(long n, size_t len)
{
    unsigned char buf[SBR_LARGE];
    for (long i = 0; i < n; i++)
        syscall(SYS_getrandom, buf, len, 0);
}

static void run_getrandom_16(long n)
{
    sbr_fill(n, SBR_SMALL);
}

static void run_getrandom_256(long n)
{
    sbr_fill(n, SBR_LARGE);
}

static void sbr_run_all(void)
{
    measure("getrandom_16", run_getrandom_16, 2000, 1, 1);
    measure("getrandom_256", run_getrandom_256, 1000, 1, 1);
}
