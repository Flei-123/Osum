#define SBIO_PATH "/tmp/speedbench.io"
#define SBIO_SPILL_PATH "/tmp/speedbench.spill"
#define SBIO_SPILL_BYTES (8 * MIB)
#define SBIO_BATCH_BYTES (4 * MIB)
#define SBIO_DROP_PATH "/proc/sys/vm/drop_caches"

static long sbio_bytes;
static int sbio_fd = -1;

static void emit_fail(const char *name)
{
    char line[160];
    int n = snprintf(line, sizeof line, "\nS %s FAIL 0\n", name);
    (void)!write(1, line, n);
}

static int sb_wanted(const char *name)
{
    return selected(name) && !(only_filter && !strstr(name, only_filter));
}

static long sbio_chunk(void)
{
    return sbio_bytes < IO_CHUNK ? sbio_bytes : IO_CHUNK;
}

static void sbio_fill(int fd, long bytes)
{
    lseek(fd, 0, SEEK_SET);
    for (long off = 0; off < bytes; off += sbio_chunk())
        (void)!write(fd, io_buf, sbio_chunk());
}

static void run_sbio_read(long n)
{
    long chunk = sbio_chunk();
    for (long i = 0; i < n; i++) {
        lseek(sbio_fd, 0, SEEK_SET);
        for (long off = 0; off < sbio_bytes; off += chunk)
            (void)!read(sbio_fd, io_buf, chunk);
    }
}

static void run_sbio_write(long n)
{
    for (long i = 0; i < n; i++) {
        lseek(sbio_fd, 0, SEEK_SET);
        for (long off = 0; off < sbio_bytes; off += sbio_chunk())
            (void)!write(sbio_fd, io_buf, sbio_chunk());
    }
}

static long sbio_batch(long bytes)
{
    long batch = SBIO_BATCH_BYTES / bytes;
    return batch < 1 ? 1 : batch;
}

static int sbio_open(long bytes)
{
    sbio_bytes = bytes;
    sbio_fd = open(SBIO_PATH, O_RDWR | O_CREAT | O_TRUNC, 0600);
    return sbio_fd >= 0;
}

static void sbio_close(void)
{
    close(sbio_fd);
    unlink(SBIO_PATH);
    sbio_fd = -1;
}

static void sbio_drop_caches(void)
{
    int fd;
    sync();
    fd = open(SBIO_DROP_PATH, O_WRONLY);
    if (fd >= 0) {
        (void)!write(fd, "3", 1);
        close(fd);
    }
    posix_fadvise(sbio_fd, 0, 0, POSIX_FADV_DONTNEED);
    fd = open(SBIO_SPILL_PATH, O_RDWR | O_CREAT | O_TRUNC, 0600);
    if (fd < 0)
        return;
    for (long off = 0; off < SBIO_SPILL_BYTES; off += IO_CHUNK)
        (void)!write(fd, io_buf, IO_CHUNK);
    fsync(fd);
    lseek(fd, 0, SEEK_SET);
    for (long off = 0; off < SBIO_SPILL_BYTES; off += IO_CHUNK)
        (void)!read(fd, io_buf, IO_CHUNK);
    close(fd);
    unlink(SBIO_SPILL_PATH);
}

static void sbio_read_warm(const char *name, long bytes)
{
    if (!sb_wanted(name))
        return;
    if (!sbio_open(bytes)) {
        emit_fail(name);
        return;
    }
    sbio_fill(sbio_fd, bytes);
    fsync(sbio_fd);
    run_sbio_read(1);
    measure(name, run_sbio_read, sbio_batch(bytes), 1, 1);
    sbio_close();
}

static long long timed_cold_read(long n)
{
    long long spent = 0;
    for (long i = 0; i < n; i++) {
        sbio_drop_caches();
        long long t0 = now_ns();
        run_sbio_read(1);
        spent += now_ns() - t0;
    }
    return spent;
}

static void sbio_read_cold(const char *name, long bytes)
{
    if (!sb_wanted(name))
        return;
    if (!sbio_open(bytes)) {
        emit_fail(name);
        return;
    }
    sbio_fill(sbio_fd, bytes);
    fsync(sbio_fd);
    measure_timed(name, timed_cold_read, 1);
    sbio_close();
}

static void sbio_write_sized(const char *name, long bytes)
{
    if (!sb_wanted(name))
        return;
    if (!sbio_open(bytes)) {
        emit_fail(name);
        return;
    }
    measure(name, run_sbio_write, sbio_batch(bytes), 1, 1);
    sbio_close();
}

static void run_devzero_4k(long n)
{
    int fd = open("/dev/zero", O_RDONLY);
    for (long i = 0; i < n; i++)
        (void)!read(fd, io_buf, PAGE);
    close(fd);
}

static void run_devnull_4k(long n)
{
    int fd = open("/dev/null", O_WRONLY);
    for (long i = 0; i < n; i++)
        (void)!write(fd, io_buf, PAGE);
    close(fd);
}

static void sbio_run_all(void)
{
    measure("read_4kib_devzero", run_devzero_4k, 5000, 1, 1);
    measure("write_4kib_devnull", run_devnull_4k, 5000, 1, 1);
    sbio_read_warm("file_read_4kib_warm", 4096);
    sbio_read_warm("file_read_64kib_warm", 65536);
    sbio_read_warm("file_read_1mib_warm", MIB);
    sbio_read_warm("file_read_16mib_warm", 16 * MIB);
    sbio_read_warm("file_read_64mib_warm", 64 * MIB);
    sbio_read_cold("file_read_4kib_cold", 4096);
    sbio_read_cold("file_read_1mib_cold", MIB);
    sbio_read_cold("file_read_16mib_cold", 16 * MIB);
    sbio_write_sized("file_write_64kib", 65536);
    sbio_write_sized("file_write_1mib", MIB);
    sbio_write_sized("file_write_16mib", 16 * MIB);
    sbio_write_sized("file_write_64mib", 64 * MIB);
}
