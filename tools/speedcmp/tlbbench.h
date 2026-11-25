#define TB_SMALL_PAGES 64
#define TB_MID_PAGES 1024
#define TB_BIG_PAGES 16384
#define TB_CHASE_BATCH 2000000
#define TB_CTX_ROUNDS 3000
#define TB_CTX_TOUCH_PAGES 64
#define TB_LCG_MUL 6364136223846793005LL
#define TB_LCG_ADD 1442695040888963407LL

static void **tb_small;
static void **tb_mid;
static void **tb_big;

static long long tb_rand(long long *state)
{
    *state = *state * TB_LCG_MUL + TB_LCG_ADD;
    return (*state >> 33) & 0x7fffffff;
}

static void **tb_slot(char *base, long page)
{
    return (void **)(base + page * PAGE + ((page * 64) & (PAGE - 64)));
}

static void **tb_ring(long pages)
{
    char *base = mmap(0, (size_t)pages * PAGE, PROT_READ | PROT_WRITE, MAP_PRIVATE | MAP_ANONYMOUS, -1, 0);
    long *perm = malloc((size_t)pages * sizeof(long));
    long long seed = pages;
    if (base == MAP_FAILED || !perm)
        exit(9);
    for (long i = 0; i < pages; i++)
        perm[i] = i;
    for (long i = pages - 1; i > 0; i--) {
        long j = tb_rand(&seed) % (i + 1);
        long t = perm[i];
        perm[i] = perm[j];
        perm[j] = t;
    }
    for (long i = 0; i < pages; i++)
        *tb_slot(base, perm[i]) = tb_slot(base, perm[(i + 1) % pages]);
    void **start = tb_slot(base, perm[0]);
    free(perm);
    return start;
}

static void tb_chase(void **start, long n)
{
    void **p = start;
    for (long i = 0; i < n; i++)
        p = (void **)*p;
    __asm__ volatile("" : : "r"(p) : "memory");
}

static void run_tlb_chase_small(long n)
{
    tb_chase(tb_small, n);
}

static void run_tlb_chase_mid(long n)
{
    tb_chase(tb_mid, n);
}

static void run_tlb_chase_big(long n)
{
    tb_chase(tb_big, n);
}

static void tb_touch_pages(volatile char *m, long pages)
{
    long sum = 0;
    for (long p = 0; p < pages; p++)
        sum += m[p * PAGE];
    __asm__ volatile("" : : "r"(sum) : "memory");
}

static void tb_ctx(long n, long touch)
{
    int up[2], down[2];
    char b = 'x';
    char *mem = mmap(0, (size_t)TB_CTX_TOUCH_PAGES * PAGE, PROT_READ | PROT_WRITE, MAP_PRIVATE | MAP_ANONYMOUS, -1, 0);
    if (mem == MAP_FAILED || pipe(up) || pipe(down))
        exit(9);
    memset(mem, 1, (size_t)TB_CTX_TOUCH_PAGES * PAGE);
    pid_t pid = fork();
    if (pid == 0) {
        close(up[1]);
        close(down[0]);
        while (read(up[0], &b, 1) == 1) {
            tb_touch_pages(mem, touch);
            (void)!write(down[1], &b, 1);
        }
        _exit(0);
    }
    for (long i = 0; i < n; i++) {
        (void)!write(up[1], &b, 1);
        tb_touch_pages(mem, touch);
        (void)!read(down[0], &b, 1);
    }
    close(up[1]);
    waitpid(pid, 0, 0);
    close(up[0]);
    close(down[0]);
    close(down[1]);
    munmap(mem, (size_t)TB_CTX_TOUCH_PAGES * PAGE);
}

static void run_tlb_ctx_plain(long n)
{
    tb_ctx(n, 0);
}

static void run_tlb_ctx_touch(long n)
{
    tb_ctx(n, TB_CTX_TOUCH_PAGES);
}

static void tlb_bench(void)
{
    if (!selected("tlb_"))
        return;
    tb_small = tb_ring(TB_SMALL_PAGES);
    tb_mid = tb_ring(TB_MID_PAGES);
    tb_big = tb_ring(TB_BIG_PAGES);
    measure("tlb_chase_small", run_tlb_chase_small, TB_CHASE_BATCH, 1, 1);
    measure("tlb_chase_mid", run_tlb_chase_mid, TB_CHASE_BATCH, 1, 1);
    measure("tlb_chase_big", run_tlb_chase_big, TB_CHASE_BATCH, 1, 1);
    measure("tlb_ctx_plain", run_tlb_ctx_plain, TB_CTX_ROUNDS, 1, 1);
    measure("tlb_ctx_touch", run_tlb_ctx_touch, TB_CTX_ROUNDS, 1, 1);
}
