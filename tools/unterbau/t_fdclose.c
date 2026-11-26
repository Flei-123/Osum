#define TNAME "fdclose"
#include "t.h"
#include <fcntl.h>
#include <pthread.h>
#include <signal.h>
#include <stdint.h>
#include <stdlib.h>
#include <sys/ioctl.h>
#include <sys/mman.h>
#include <sys/socket.h>
#include <sys/stat.h>

#define BIG_BYTES (1024 * 1024)
#define SMALL_BYTES 5
#define SETTLE_USEC 100000
#define SCRATCH_BYTES 65536
#define PAGE_BYTES 4096
#define SIZE_A 4096
#define SIZE_B 8192
#define FIXED_FD 100
#define RACE_ROUNDS 30000
#define JITTER_MASK 63
#define OP_COUNT 5

enum { OP_PREAD, OP_FSTAT, OP_LSEEK, OP_MMAP, OP_IOCTL };

static volatile int started;
static volatile int done;
static volatile ssize_t result;
static volatile int stop;
static volatile long foreign;
static volatile long ok_ops;
static volatile int race_op;
static int blocked_fd;

static inline void relax(void)
{
    __builtin_ia32_pause();
}

static uint32_t next_random(uint32_t *s)
{
    uint32_t x = *s;
    x ^= x << 13;
    x ^= x >> 17;
    x ^= x << 5;
    return *s = x;
}

static void wait_for_start(void)
{
    while (!started)
        relax();
    usleep(SETTLE_USEC);
}

static void reset_flags(void)
{
    started = 0;
    done = 0;
    result = -2;
}

static void *big_writer(void *arg)
{
    static char big[BIG_BYTES];
    (void)arg;
    memset(big, 'B', sizeof big);
    started = 1;
    result = write(blocked_fd, big, sizeof big);
    done = 1;
    return NULL;
}

static void *small_reader(void *arg)
{
    char buf[16];
    (void)arg;
    started = 1;
    result = read(blocked_fd, buf, sizeof buf);
    done = 1;
    return NULL;
}

static void *small_receiver(void *arg)
{
    char buf[16];
    (void)arg;
    started = 1;
    result = recv(blocked_fd, buf, sizeof buf, 0);
    done = 1;
    return NULL;
}

static int drain_expect(int rfd, unsigned char tag, long want, long *got)
{
    static unsigned char buf[SCRATCH_BYTES];
    long total = 0;
    int clean = 1;
    for (;;) {
        ssize_t n = read(rfd, buf, sizeof buf);
        if (n <= 0)
            break;
        for (ssize_t i = 0; i < n; i++)
            if (buf[i] != tag)
                clean = 0;
        total += n;
    }
    *got = total;
    return clean && total == want;
}

static void pipe_write_survives_close(void)
{
    int p[2], q[2];
    pthread_t th;
    long got = 0;
    if (pipe(p) != 0 || pipe(q) != 0) {
        FAIL("pipe_write_survives_close", "pipe failed errno %d", errno);
        return;
    }
    reset_flags();
    blocked_fd = p[1];
    pthread_create(&th, NULL, big_writer, NULL);
    wait_for_start();
    close(p[1]);
    int fresh[2];
    int fresh_ok = pipe(fresh) == 0;
    int drained = drain_expect(p[0], 'B', BIG_BYTES, &got);
    pthread_join(th, NULL);
    CHECK("pipe_write_survives_close", drained && result == BIG_BYTES,
        "drained %ld of %d, writer returned %ld", got, BIG_BYTES, (long)result);
    int flags = fresh_ok ? fcntl(fresh[0], F_GETFL) : -1;
    char probe;
    if (fresh_ok && flags >= 0)
        fcntl(fresh[0], F_SETFL, flags | O_NONBLOCK);
    errno = 0;
    ssize_t n = fresh_ok ? read(fresh[0], &probe, 1) : -1;
    CHECK("pipe_write_reuse_gets_no_foreign_data", fresh_ok && n < 0 && errno == EAGAIN,
        "fresh pipe read returned %ld errno %d", (long)n, errno);
    close(p[0]);
    close(q[0]);
    close(q[1]);
    if (fresh_ok) {
        close(fresh[0]);
        close(fresh[1]);
    }
}

static void pipe_read_survives_close(void)
{
    int p[2];
    pthread_t th;
    if (pipe(p) != 0) {
        FAIL("pipe_read_survives_close", "pipe failed errno %d", errno);
        return;
    }
    reset_flags();
    blocked_fd = p[0];
    pthread_create(&th, NULL, small_reader, NULL);
    wait_for_start();
    close(p[0]);
    errno = 0;
    ssize_t w = write(p[1], "hello", SMALL_BYTES);
    int w_errno = errno;
    pthread_join(th, NULL);
    CHECK("pipe_read_survives_close", w == SMALL_BYTES && result == SMALL_BYTES,
        "write returned %ld errno %d, reader returned %ld", (long)w, w_errno, (long)result);
    errno = 0;
    w = write(p[1], "x", 1);
    CHECK("pipe_last_close_releases_reader", w < 0 && errno == EPIPE,
        "write after the last reader left returned %ld errno %d", (long)w, errno);
    close(p[1]);
}

static void socket_recv_survives_close(void)
{
    int sv[2];
    pthread_t th;
    if (socketpair(AF_UNIX, SOCK_STREAM, 0, sv) != 0) {
        FAIL("socket_recv_survives_close", "socketpair failed errno %d", errno);
        return;
    }
    reset_flags();
    blocked_fd = sv[0];
    pthread_create(&th, NULL, small_receiver, NULL);
    wait_for_start();
    close(sv[0]);
    errno = 0;
    ssize_t w = send(sv[1], "hello", SMALL_BYTES, MSG_NOSIGNAL);
    int w_errno = errno;
    pthread_join(th, NULL);
    CHECK("socket_recv_survives_close", w == SMALL_BYTES && result == SMALL_BYTES,
        "send returned %ld errno %d, recv returned %ld", (long)w, w_errno, (long)result);
    errno = 0;
    w = send(sv[1], "x", 1, MSG_NOSIGNAL);
    CHECK("socket_last_close_releases_peer", w < 0 && (errno == EPIPE || errno == ECONNRESET),
        "send after the last holder left returned %ld errno %d", (long)w, errno);
    close(sv[1]);
}

static int make_file(const char *path, unsigned char tag, size_t size)
{
    unsigned char page[PAGE_BYTES];
    memset(page, tag, sizeof page);
    int fd = open(path, O_RDWR | O_CREAT | O_TRUNC, 0600);
    if (fd < 0)
        return -1;
    for (size_t off = 0; off < size; off += sizeof page)
        if (write(fd, page, sizeof page) != (ssize_t)sizeof page)
            return -1;
    close(fd);
    return 0;
}

static void note_foreign(int hit)
{
    if (hit)
        foreign++;
    else
        ok_ops++;
}

static void op_pread(void)
{
    unsigned char buf[PAGE_BYTES];
    ssize_t n = pread(FIXED_FD, buf, sizeof buf, 0);
    if (n <= 0)
        return;
    int hit = 0;
    for (ssize_t i = 0; i < n; i++)
        if (buf[i] == 'B')
            hit = 1;
    note_foreign(hit);
}

static void op_fstat(void)
{
    struct stat st;
    if (fstat(FIXED_FD, &st) == 0)
        note_foreign(st.st_size == SIZE_B);
}

static void op_lseek(void)
{
    off_t end = lseek(FIXED_FD, 0, SEEK_END);
    if (end >= 0)
        note_foreign(end == SIZE_B);
}

static void op_mmap(void)
{
    unsigned char *p = mmap(NULL, PAGE_BYTES, PROT_READ, MAP_SHARED, FIXED_FD, 0);
    if (p == MAP_FAILED)
        return;
    int hit = p[0] == 'B';
    munmap(p, PAGE_BYTES);
    note_foreign(hit);
}

static void op_ioctl(void)
{
    int pending = -1;
    if (ioctl(FIXED_FD, FIONREAD, &pending) == 0)
        note_foreign(pending == SIZE_B);
}

static void *race_worker(void *arg)
{
    (void)arg;
    while (!stop) {
        switch (race_op) {
        case OP_PREAD: op_pread(); break;
        case OP_FSTAT: op_fstat(); break;
        case OP_LSEEK: op_lseek(); break;
        case OP_MMAP: op_mmap(); break;
        default: op_ioctl(); break;
        }
    }
    return NULL;
}

static void race_one(int op, const char *name)
{
    uint32_t seed = 0x9e3779b9 + op;
    pthread_t th;
    foreign = 0;
    ok_ops = 0;
    stop = 0;
    race_op = op;
    pthread_create(&th, NULL, race_worker, NULL);
    for (int i = 0; i < RACE_ROUNDS; i++) {
        int a = open("/tmp/fdclose_a", O_RDONLY);
        if (a < 0)
            break;
        dup2(a, FIXED_FD);
        close(a);
        for (uint32_t j = next_random(&seed) & JITTER_MASK; j > 0; j--)
            relax();
        close(FIXED_FD);
        int b = open("/tmp/fdclose_b", O_RDONLY);
        for (uint32_t j = next_random(&seed) & JITTER_MASK; j > 0; j--)
            relax();
        if (b >= 0)
            close(b);
    }
    stop = 1;
    pthread_join(th, NULL);
    CHECK(name, foreign == 0, "%ld foreign results, %ld clean (op %d)", (long)foreign, (long)ok_ops, op);
}

static void reuse_races(void)
{
    if (make_file("/tmp/fdclose_a", 'A', SIZE_A) != 0 || make_file("/tmp/fdclose_b", 'B', SIZE_B) != 0) {
        FAIL("reuse_race_setup", "cannot create the two files errno %d", errno);
        return;
    }
    race_one(OP_PREAD, "reuse_race_pread_no_foreign");
    race_one(OP_FSTAT, "reuse_race_fstat_no_foreign");
    race_one(OP_LSEEK, "reuse_race_lseek_no_foreign");
    race_one(OP_MMAP, "reuse_race_mmap_no_foreign");
    race_one(OP_IOCTL, "reuse_race_ioctl_no_foreign");
    unlink("/tmp/fdclose_a");
    unlink("/tmp/fdclose_b");
    PASS("reuse_race_survived");
}

int main(void)
{
    signal(SIGPIPE, SIG_IGN);
    pipe_write_survives_close();
    pipe_read_survives_close();
    socket_recv_survives_close();
    reuse_races();
    return 0;
}
