#define WB_FILE "/tmp/speedbench.w"
#define WB_DIR "/tmp/sbm"
#define WB_WINDOW_PAGES 256
#define WB_BATCH 64
#define WB_NAME_LEN 48
#define WB_FSYNC_BATCH 16

typedef long long (*timed_fn)(long n);

static int wb_fd = -1;
static char wb_names[WB_BATCH][WB_NAME_LEN];
static char wb_alt_name[WB_NAME_LEN];

#define PROF_N 14

static const char *prof_keys[PROF_N] = {
    "blk.run_cmds", "blk.run_sectors", "blk.ahci_cmds", "blk.ahci_wait_cy",
    "blk.ahci_polls", "blk.ahci_irqs", "blk.ahci_sleeps", "tsc.khz",
    "blk.ahci_read_cmds", "blk.ahci_write_cmds", "blk.ahci_flush_cmds",
    "blk.ahci_read_cy", "blk.ahci_write_cy", "blk.ahci_flush_cy"
};

static void prof_read(long long out[PROF_N])
{
    static char buf[8192];
    int fd = open("/proc/bench", O_RDONLY);
    ssize_t n = fd >= 0 ? read(fd, buf, sizeof buf - 1) : 0;
    if (fd >= 0)
        close(fd);
    buf[n > 0 ? n : 0] = 0;
    for (int i = 0; i < PROF_N; i++) {
        char *p = strstr(buf, prof_keys[i]);
        out[i] = p ? atoll(p + strlen(prof_keys[i]) + 1) : -1;
    }
}

static void prof_emit(const char *name, const long long a[PROF_N], const long long b[PROF_N], long ops)
{
    char line[256];
    double per = (double)ops;
    int n = snprintf(line, sizeof line,
        "\nP %s cmds=%.2f sectors=%.2f wait_kcy=%.1f polls=%.1f irqs=%.2f sleeps=%.2f"
        " rd=%.2f wr=%.2f fl=%.2f rd_kcy=%.1f wr_kcy=%.1f fl_kcy=%.1f\n", name,
        (double)(b[2] - a[2]) / per, (double)(b[1] - a[1]) / per, (double)(b[3] - a[3]) / per / 1000.0,
        (double)(b[4] - a[4]) / per, (double)(b[5] - a[5]) / per, (double)(b[6] - a[6]) / per,
        (double)(b[8] - a[8]) / per, (double)(b[9] - a[9]) / per, (double)(b[10] - a[10]) / per,
        (double)(b[11] - a[11]) / per / 1000.0, (double)(b[12] - a[12]) / per / 1000.0,
        (double)(b[13] - a[13]) / per / 1000.0);
    (void)!write(1, line, n);
}

static void measure_timed(const char *name, timed_fn fn, long batch)
{
    if (!selected(name) || (only_filter && !strstr(name, only_filter)))
        return;
    long total = 0;
    long long spent = 0;
    long long pa[PROF_N], pb[PROF_N];
    prof_read(pa);
    long long t0 = now_ns();
    do {
        spent += fn(batch);
        total += batch;
    } while (now_ns() - t0 < MIN_NS);
    prof_read(pb);
    emit(name, (double)spent / (double)total, total);
    prof_emit(name, pa, pb, total);
}

static void wb_prepare(void)
{
    mkdir(WB_DIR, 0700);
    for (long i = 0; i < WB_BATCH; i++)
        snprintf(wb_names[i], WB_NAME_LEN, WB_DIR "/f%ld", i);
    snprintf(wb_alt_name, WB_NAME_LEN, WB_DIR "/alt");
    wb_fd = open(WB_FILE, O_RDWR | O_CREAT | O_TRUNC, 0600);
    if (wb_fd < 0)
        exit(8);
}

static void wb_cleanup(void)
{
    close(wb_fd);
    unlink(WB_FILE);
    rmdir(WB_DIR);
}

static void wb_make_files(long n, int with_data)
{
    for (long i = 0; i < n; i++) {
        int fd = open(wb_names[i], O_WRONLY | O_CREAT | O_TRUNC, 0600);
        if (fd < 0)
            exit(9);
        if (with_data)
            (void)!write(fd, io_buf, PAGE);
        close(fd);
    }
}

static void wb_drop_files(long n)
{
    for (long i = 0; i < n; i++)
        unlink(wb_names[i]);
}

static void run_write_seq(long n)
{
    for (long i = 0; i < n; i++) {
        if (i % WB_WINDOW_PAGES == 0)
            lseek(wb_fd, 0, SEEK_SET);
        (void)!write(wb_fd, io_buf, PAGE);
    }
}

static void run_pwrite(long n)
{
    for (long i = 0; i < n; i++)
        (void)!pwrite(wb_fd, io_buf, PAGE, (i % WB_WINDOW_PAGES) * PAGE);
}

static void run_write_fsync_small(long n)
{
    for (long i = 0; i < n; i++) {
        (void)!pwrite(wb_fd, io_buf, PAGE, (i % WB_WINDOW_PAGES) * PAGE);
        fsync(wb_fd);
    }
}

static long long timed_create(long n)
{
    long long t0 = now_ns();
    wb_make_files(n, 1);
    long long spent = now_ns() - t0;
    wb_drop_files(n);
    return spent;
}

static long long timed_rename(long n)
{
    wb_make_files(1, 1);
    long long t0 = now_ns();
    for (long i = 0; i < n; i++) {
        if (i % 2 == 0)
            rename(wb_names[0], wb_alt_name);
        else
            rename(wb_alt_name, wb_names[0]);
    }
    long long spent = now_ns() - t0;
    unlink(n % 2 ? wb_alt_name : wb_names[0]);
    return spent;
}

static long long timed_unlink(long n)
{
    wb_make_files(n, 1);
    long long t0 = now_ns();
    wb_drop_files(n);
    return now_ns() - t0;
}

static long long timed_mkdir(long n)
{
    long long t0 = now_ns();
    for (long i = 0; i < n; i++)
        mkdir(wb_names[i], 0700);
    long long spent = now_ns() - t0;
    for (long i = 0; i < n; i++)
        rmdir(wb_names[i]);
    return spent;
}

static void wb_run_all(void)
{
    wb_prepare();
    measure("write_4kib_seq", run_write_seq, 256, 1, 1);
    measure("pwrite_4kib", run_pwrite, 256, 1, 1);
    measure("write_4kib_fsync", run_write_fsync_small, WB_FSYNC_BATCH, 1, 1);
    measure_timed("create_write_close", timed_create, WB_BATCH);
    measure_timed("rename_file", timed_rename, WB_BATCH);
    measure_timed("unlink_file", timed_unlink, WB_BATCH);
    measure_timed("mkdir_dir", timed_mkdir, WB_BATCH);
    wb_cleanup();
}
