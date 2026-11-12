#define MB_REGION_PAGES 16384
#define MB_BRK_PAGES 2048
#define MB_MPROT_ROUNDS 32
#define MB_SMALL_MAPS 256
#define MB_WAIT_CHILDREN 32

static int mb_quiet;

static double mb_now_per(long long t0, long ops)
{
    return (double)(now_ns() - t0) / (double)(ops > 0 ? ops : 1);
}

static void mb_emit(const char *name, double ns, long ops)
{
    if (!mb_quiet)
        emit(name, ns, ops);
}

static long long mb_traps(void)
{
    static char buf[4096];
    int fd = open("/proc/stat", O_RDONLY);
    ssize_t n = fd >= 0 ? read(fd, buf, sizeof buf - 1) : 0;
    if (fd >= 0)
        close(fd);
    buf[n > 0 ? n : 0] = 0;
    char *p = strstr(buf, "traps ");
    return p ? atoll(p + 6) : 0;
}

static void mb_touch(char *m, long pages)
{
    for (long p = 0; p < pages; p++)
        m[p * PAGE] = 1;
}

static void mb_mmap_phases(void)
{
    if (!selected("mem"))
        return;
    long long t0 = now_ns();
    char *m = mmap(0, MB_REGION_PAGES * PAGE, PROT_READ | PROT_WRITE, MAP_PRIVATE | MAP_ANONYMOUS, -1, 0);
    long long map_ns = now_ns() - t0;
    if (m == MAP_FAILED)
        exit(8);
    long long traps0 = mb_traps();
    t0 = now_ns();
    mb_touch(m, MB_REGION_PAGES);
    double touch_ns = mb_now_per(t0, MB_REGION_PAGES);
    mb_emit("mem_touch_traps_x1000_per_page", (double)(mb_traps() - traps0) * 1000.0 / MB_REGION_PAGES, 1);
    mb_emit("mem_touch_64mib_page", touch_ns, MB_REGION_PAGES);
    t0 = now_ns();
    mb_touch(m, MB_REGION_PAGES);
    mb_emit("mem_retouch_64mib_page", mb_now_per(t0, MB_REGION_PAGES), MB_REGION_PAGES);
    t0 = now_ns();
    for (long r = 0; r < MB_MPROT_ROUNDS; r++) {
        mprotect(m, MB_REGION_PAGES * PAGE, PROT_READ);
        mprotect(m, MB_REGION_PAGES * PAGE, PROT_READ | PROT_WRITE);
    }
    mb_emit("mem_mprotect_64mib_page", mb_now_per(t0, (long)MB_MPROT_ROUNDS * 2 * MB_REGION_PAGES), (long)MB_MPROT_ROUNDS * 2 * MB_REGION_PAGES);
    t0 = now_ns();
    for (long r = 0; r < MB_SMALL_MAPS; r++)
        mprotect(m + r * PAGE, PAGE, PROT_READ);
    mb_emit("mem_mprotect_1page_call", mb_now_per(t0, MB_SMALL_MAPS), MB_SMALL_MAPS);
    mprotect(m, MB_REGION_PAGES * PAGE, PROT_READ | PROT_WRITE);
    t0 = now_ns();
    munmap(m, MB_REGION_PAGES * PAGE);
    mb_emit("mem_munmap_64mib_page", mb_now_per(t0, MB_REGION_PAGES), MB_REGION_PAGES);
    mb_emit("mem_mmap_64mib_call", (double)map_ns, 1);
}

static void mb_small_maps(void)
{
    if (!selected("mem"))
        return;
    long long t0 = now_ns();
    for (long r = 0; r < MB_SMALL_MAPS; r++) {
        char *m = mmap(0, PAGE, PROT_READ | PROT_WRITE, MAP_PRIVATE | MAP_ANONYMOUS, -1, 0);
        if (m == MAP_FAILED)
            exit(9);
        m[0] = 1;
        munmap(m, PAGE);
    }
    mb_emit("mem_small_map_touch_unmap", mb_now_per(t0, MB_SMALL_MAPS), MB_SMALL_MAPS);
}

static void mb_brk(void)
{
    if (!selected("mem"))
        return;
    char *base = (char *)syscall(SYS_brk, 0);
    long long t0 = now_ns();
    long grown = 0;
    for (long p = 1; p <= MB_BRK_PAGES; p++) {
        char *end = (char *)syscall(SYS_brk, base + p * PAGE);
        if ((long)end < (long)(base + p * PAGE))
            break;
        end[-1] = 1;
        grown = p;
    }
    mb_emit("mem_brk_grow_page", mb_now_per(t0, grown), grown);
    mb_emit("mem_brk_pages_grown", (double)grown, 1);
    syscall(SYS_brk, base);
}

static void mb_fork_big(void)
{
    if (!selected("mem"))
        return;
    char *m = mmap(0, MB_REGION_PAGES * PAGE, PROT_READ | PROT_WRITE, MAP_PRIVATE | MAP_ANONYMOUS, -1, 0);
    if (m == MAP_FAILED)
        exit(10);
    mb_touch(m, MB_REGION_PAGES);
    long long t0 = now_ns();
    for (long i = 0; i < 8; i++) {
        pid_t pid = fork();
        if (pid == 0)
            _exit(0);
        waitpid(pid, 0, 0);
    }
    mb_emit("mem_fork_64mib_exit_wait", mb_now_per(t0, 8), 8);
    t0 = now_ns();
    for (long i = 0; i < 4; i++) {
        pid_t pid = fork();
        if (pid == 0) {
            mb_touch(m, MB_REGION_PAGES / 4);
            _exit(0);
        }
        waitpid(pid, 0, 0);
    }
    mb_emit("mem_fork_64mib_cow_quarter", mb_now_per(t0, 4), 4);
    munmap(m, MB_REGION_PAGES * PAGE);
}

static void mb_exit_wait(void)
{
    if (!selected("mem"))
        return;
    long long t0 = now_ns();
    for (long i = 0; i < MB_WAIT_CHILDREN; i++) {
        pid_t pid = fork();
        if (pid == 0) {
            char *m = mmap(0, 1024 * PAGE, PROT_READ | PROT_WRITE, MAP_PRIVATE | MAP_ANONYMOUS, -1, 0);
            if (m != MAP_FAILED)
                mb_touch(m, 1024);
            _exit(0);
        }
        waitpid(pid, 0, 0);
    }
    mb_emit("mem_exit_4mib_child", mb_now_per(t0, MB_WAIT_CHILDREN), MB_WAIT_CHILDREN);
}

static void mb_run_all(void)
{
    long long t0 = now_ns();
    do {
        mb_mmap_phases();
        mb_small_maps();
        mb_brk();
        mb_fork_big();
        mb_exit_wait();
        mb_quiet = 1;
    } while (selected("mem") && now_ns() - t0 < min_ns);
}
