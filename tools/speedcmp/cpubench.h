#define CB_ALU_BATCH 1000000
#define CB_STREAM_BYTES (64L << 20)
#define CB_HUGE_PAGES 65536
#define CB_CHASE_BATCH 1000000

static char *cb_stream;
static void **cb_huge;

static void run_cpu_alu(long n)
{
    unsigned long long x = 88172645463325252ULL;
    unsigned long long acc = 0;
    for (long i = 0; i < n; i++) {
        x ^= x << 13;
        x ^= x >> 7;
        x ^= x << 17;
        acc += x * 0x9E3779B97F4A7C15ULL;
    }
    __asm__ volatile("" : : "r"(acc));
}

static void run_cpu_memset_64mib(long n)
{
    for (long i = 0; i < n; i++)
        memset(cb_stream, (int)i, CB_STREAM_BYTES);
    __asm__ volatile("" : : "r"(cb_stream) : "memory");
}

static void run_cpu_chase_256mib(long n)
{
    tb_chase(cb_huge, n);
}

static unsigned long long cb_xcr0(void)
{
    unsigned int a, b, c, d;
    __asm__ volatile("cpuid" : "=a"(a), "=b"(b), "=c"(c), "=d"(d) : "a"(1), "c"(0));
    if (!(c & (1u << 27)))
        return 0;
    __asm__ volatile("xgetbv" : "=a"(a), "=d"(d) : "c"(0));
    return ((unsigned long long)d << 32) | a;
}

static void cpu_bench(void)
{
    if (!selected("cpu_"))
        return;
    emit("cpu_xcr0", (double)cb_xcr0(), 1);
    measure("cpu_alu", run_cpu_alu, CB_ALU_BATCH, 1, 1);
    cb_stream = mmap(0, CB_STREAM_BYTES, PROT_READ | PROT_WRITE, MAP_PRIVATE | MAP_ANONYMOUS, -1, 0);
    if (cb_stream == MAP_FAILED)
        exit(9);
    memset(cb_stream, 1, CB_STREAM_BYTES);
    measure("cpu_memset_64mib", run_cpu_memset_64mib, 1, 3, 1);
    munmap(cb_stream, CB_STREAM_BYTES);
    cb_huge = tb_ring(CB_HUGE_PAGES);
    measure("cpu_chase_256mib", run_cpu_chase_256mib, CB_CHASE_BATCH, 1, 1);
}
