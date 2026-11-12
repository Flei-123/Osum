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

static void measure_timed(const char *name, timed_fn fn, long batch)
{
    if (!selected(name) || (only_filter && !strstr(name, only_filter)))
        return;
    long total = 0;
    long long spent = 0;
    long long t0 = now_ns();
    do {
        spent += fn(batch);
        total += batch;
    } while (now_ns() - t0 < MIN_NS);
    emit(name, (double)spent / (double)total, total);
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
