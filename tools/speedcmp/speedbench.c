#define _GNU_SOURCE
#include <fcntl.h>
#include <pthread.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mman.h>
#include <sys/stat.h>
#include <sys/syscall.h>
#include <sys/wait.h>
#include <time.h>
#include <unistd.h>

#define SELF_PATH "/bin/speedbench"
#define DATA_PATH "/tmp/speedbench.dat"
#define MIN_NS 300000000LL
#define MAX_NS 8000000000LL
#define PAGE 4096
#define MIB (1024 * 1024)
#define IO_BYTES (4 * MIB)
#define IO_CHUNK 65536
#define SMALL_FILE_BYTES (512 * 1024)
#define ANON_PAGES 8192
#define FILE_PAGES 128
#define SMALL_BUF 64
#define PIPE_ROUNDS 2000

typedef void (*bench_fn)(long n);

static const char *only_filter;
static long long min_ns = MIN_NS;

static char *io_buf;
static int data_fd = -1;

static long long now_ns(void)
{
    struct timespec t;
    clock_gettime(CLOCK_MONOTONIC, &t);
    return (long long)t.tv_sec * 1000000000LL + t.tv_nsec;
}

static void emit(const char *name, double ns_per_op, long ops)
{
    char line[160];
    int n = snprintf(line, sizeof line, "\nS %s %.1f %ld\n", name, ns_per_op, ops);
    (void)!write(1, line, n);
}

static int selected(const char *name)
{
    static char only[256];
    static int loaded;
    if (!loaded) {
        int fd = open("/etc/speedonly", O_RDONLY);
        loaded = 1;
        if (fd >= 0) {
            ssize_t n = read(fd, only, sizeof(only) - 1);
            only[n > 0 ? n : 0] = 0;
            close(fd);
            char *nl = strchr(only, 10);
            if (nl) {
                long ms = atol(nl + 1);
                *nl = 0;
                if (ms > 0)
                    min_ns = ms * 1000000LL;
            }
        }
    }
    return !only[0] || strstr(only, name);
}

static void measure(const char *name, bench_fn fn, long batch, long min_batches, long ops_per_item)
{
    if (!selected(name) || (only_filter && !strstr(name, only_filter)))
        return;
    long total = 0;
    long long t0 = now_ns();
    long long elapsed;
    do {
        fn(batch);
        total += batch;
        elapsed = now_ns() - t0;
    } while ((elapsed < min_ns || total < batch * min_batches) && elapsed < MAX_NS);
    emit(name, (double)elapsed / (double)(total * ops_per_item), total * ops_per_item);
}

static void run_getpid(long n)
{
    for (long i = 0; i < n; i++)
        syscall(SYS_getpid);
}

static void run_lseek(long n)
{
    for (long i = 0; i < n; i++)
        lseek(data_fd, 0, SEEK_SET);
}

static void run_clock_gettime(long n)
{
    struct timespec t;
    for (long i = 0; i < n; i++)
        clock_gettime(CLOCK_MONOTONIC, &t);
}

static void run_fstat(long n)
{
    struct stat st;
    for (long i = 0; i < n; i++)
        fstat(data_fd, &st);
}

static void run_read_small(long n)
{
    int fd = open("/dev/zero", O_RDONLY);
    for (long i = 0; i < n; i++)
        (void)!read(fd, io_buf, SMALL_BUF);
    close(fd);
}

static void run_write_small(long n)
{
    int fd = open("/dev/null", O_WRONLY);
    for (long i = 0; i < n; i++)
        (void)!write(fd, io_buf, SMALL_BUF);
    close(fd);
}

static void run_anon_fault(long n)
{
    for (long r = 0; r < n; r++) {
        char *m = mmap(0, ANON_PAGES * PAGE, PROT_READ | PROT_WRITE, MAP_PRIVATE | MAP_ANONYMOUS, -1, 0);
        if (m == MAP_FAILED)
            exit(3);
        for (long p = 0; p < ANON_PAGES; p++)
            m[p * PAGE] = 1;
        munmap(m, ANON_PAGES * PAGE);
    }
}

static void fill_file(int fd, long bytes)
{
    lseek(fd, 0, SEEK_SET);
    for (long off = 0; off < bytes; off += IO_CHUNK)
        (void)!write(fd, io_buf, IO_CHUNK);
}

static void run_file_fault(long n)
{
    volatile char sink = 0;
    for (long r = 0; r < n; r++) {
        char *m = mmap(0, FILE_PAGES * PAGE, PROT_READ, MAP_PRIVATE, data_fd, 0);
        if (m == MAP_FAILED)
            exit(4);
        for (long p = 0; p < FILE_PAGES; p++)
            sink += m[p * PAGE];
        munmap(m, FILE_PAGES * PAGE);
    }
}

static void run_write_4m(long n)
{
    for (long i = 0; i < n; i++) {
        ftruncate(data_fd, 0);
        fill_file(data_fd, IO_BYTES);
    }
}

static void run_read_4m(long n)
{
    for (long i = 0; i < n; i++) {
        lseek(data_fd, 0, SEEK_SET);
        for (long off = 0; off < IO_BYTES; off += IO_CHUNK)
            (void)!read(data_fd, io_buf, IO_CHUNK);
    }
}

static void run_read_4k_calls(long n)
{
    for (long i = 0; i < n; i++) {
        lseek(data_fd, 0, SEEK_SET);
        for (long off = 0; off < IO_BYTES; off += PAGE)
            (void)!read(data_fd, io_buf, PAGE);
    }
}

static void run_pread_4k_calls(long n)
{
    for (long i = 0; i < n; i++)
        for (long off = 0; off < IO_BYTES; off += PAGE)
            (void)!pread(data_fd, io_buf, PAGE, off);
}

static void run_read_512k(long n)
{
    for (long i = 0; i < n; i++) {
        lseek(data_fd, 0, SEEK_SET);
        for (long off = 0; off < SMALL_FILE_BYTES; off += IO_CHUNK)
            (void)!read(data_fd, io_buf, IO_CHUNK);
    }
}

static void run_write_fsync(long n)
{
    for (long i = 0; i < n; i++) {
        ftruncate(data_fd, 0);
        fill_file(data_fd, IO_BYTES);
        fsync(data_fd);
    }
}

static void run_fork(long n)
{
    for (long i = 0; i < n; i++) {
        pid_t pid = fork();
        if (pid == 0)
            _exit(0);
        waitpid(pid, 0, 0);
    }
}

static void run_exec(long n)
{
    char *argv[] = {"speedbench", "--noop", 0};
    for (long i = 0; i < n; i++) {
        pid_t pid = fork();
        if (pid == 0) {
            execv(SELF_PATH, argv);
            _exit(127);
        }
        int st = 0;
        waitpid(pid, &st, 0);
        if (!WIFEXITED(st) || WEXITSTATUS(st) != 0)
            exit(5);
    }
}

static void run_pipe(long n)
{
    int up[2], down[2];
    char b = 'x';
    if (pipe(up) || pipe(down))
        exit(6);
    pid_t pid = fork();
    if (pid == 0) {
        close(up[1]);
        close(down[0]);
        while (read(up[0], &b, 1) == 1)
            (void)!write(down[1], &b, 1);
        _exit(0);
    }
    for (long i = 0; i < n; i++) {
        (void)!write(up[1], &b, 1);
        (void)!read(down[0], &b, 1);
    }
    close(up[1]);
    waitpid(pid, 0, 0);
    close(up[0]);
    close(down[0]);
    close(down[1]);
}

static void *thread_main(void *arg)
{
    return arg;
}

static void run_thread(long n)
{
    for (long i = 0; i < n; i++) {
        pthread_t th;
        if (pthread_create(&th, 0, thread_main, 0))
            exit(7);
        pthread_join(th, 0);
    }
}

#include "wbench.h"
#include "membench.h"
#include "sbio.h"
#include "sbmeta.h"
#include "sbproc.h"

int main(int argc, char **argv)
{
    if (argc > 1 && !strcmp(argv[1], "--noop"))
        return 0;
    if (argc > 1)
        only_filter = argv[1];
    io_buf = malloc(IO_CHUNK);
    memset(io_buf, 0x5A, IO_CHUNK);
    data_fd = open(DATA_PATH, O_RDWR | O_CREAT | O_TRUNC, 0600);
    if (data_fd < 0)
        return 2;
    measure("syscall_getpid", run_getpid, 20000, 1, 1);
    measure("syscall_lseek", run_lseek, 20000, 1, 1);
    measure("clock_gettime", run_clock_gettime, 20000, 1, 1);
    measure("fstat", run_fstat, 20000, 1, 1);
    measure("syscall_getpid_late", run_getpid, 20000, 1, 1);
    measure("clock_gettime_late", run_clock_gettime, 20000, 1, 1);
    measure("read_64b_devzero", run_read_small, 5000, 1, 1);
    measure("write_64b_devnull", run_write_small, 5000, 1, 1);
    measure("pagefault_anon_page", run_anon_fault, 1, 1, ANON_PAGES);
    fill_file(data_fd, FILE_PAGES * PAGE);
    measure("pagefault_filemap_page", run_file_fault, 1, 1, FILE_PAGES);
    measure("file_write_4mib", run_write_4m, 1, 3, 1);
    if (selected("file_read")) {
        ftruncate(data_fd, 0);
        fill_file(data_fd, IO_BYTES);
        fsync(data_fd);
        run_read_4m(1);
    }
    measure("file_read_4mib_warm", run_read_4m, 1, 3, 1);
    measure("file_read_4mib_page_calls", run_read_4k_calls, 1, 3, 1);
    measure("file_pread_4mib_page_calls", run_pread_4k_calls, 1, 3, 1);
    ftruncate(data_fd, SMALL_FILE_BYTES);
    measure("file_read_512kib_warm", run_read_512k, 1, 3, 1);
    measure("file_write_4mib_fsync", run_write_fsync, 1, 3, 1);
    measure("fork_exit_wait", run_fork, 50, 1, 1);
    measure("fork_exec_exit_wait", run_exec, 20, 1, 1);
    measure("pipe_roundtrip", run_pipe, PIPE_ROUNDS, 1, 1);
    measure("thread_create_join", run_thread, 100, 1, 1);
    wb_run_all();
    mb_run_all();
    sbio_run_all();
    sbm_run_all();
    sbp_run_all();
    close(data_fd);
    unlink(DATA_PATH);
    (void)!write(1, "\nS END 0 0\n", 11);
    return 0;
}
