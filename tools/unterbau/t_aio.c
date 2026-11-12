#define TNAME "aio"
#include "t.h"
#include <fcntl.h>
#include <stdint.h>
#include <stdlib.h>
#include <sys/syscall.h>

#define SYS_IO_SETUP_NR 206
#define SYS_IO_DESTROY_NR 207
#define SYS_IO_GETEVENTS_NR 208
#define SYS_IO_SUBMIT_NR 209
#define OP_PREAD 0
#define OP_PWRITE 1
#define OP_FSYNC 2
#define OP_NOOP 6
#define BLOCK_BYTES 4096
#define QUEUE_EVENTS 128

struct iocb_raw {
    uint64_t data;
    uint32_t key;
    uint32_t rw_flags;
    uint16_t opcode;
    int16_t reqprio;
    uint32_t fildes;
    uint64_t buf;
    uint64_t nbytes;
    int64_t offset;
    uint64_t reserved2;
    uint32_t flags;
    uint32_t resfd;
};

struct event_raw {
    uint64_t data;
    uint64_t obj;
    int64_t res;
    int64_t res2;
};

static long io_setup(unsigned nr, uint64_t *ctx) { return syscall(SYS_IO_SETUP_NR, nr, ctx); }
static long io_destroy(uint64_t ctx) { return syscall(SYS_IO_DESTROY_NR, ctx); }
static long io_submit(uint64_t ctx, long n, struct iocb_raw **cbs) { return syscall(SYS_IO_SUBMIT_NR, ctx, n, cbs); }
static long io_getevents(uint64_t ctx, long min, long max, struct event_raw *ev, void *to) { return syscall(SYS_IO_GETEVENTS_NR, ctx, min, max, ev, to); }

static void prepare(struct iocb_raw *cb, int op, int fd, void *buf, size_t len, long off, uint64_t tag)
{
    memset(cb, 0, sizeof *cb);
    cb->opcode = (uint16_t)op;
    cb->fildes = (uint32_t)fd;
    cb->buf = (uint64_t)(uintptr_t)buf;
    cb->nbytes = len;
    cb->offset = off;
    cb->data = tag;
}

int main(void)
{
    uint64_t ctx = 0;
    static char out[BLOCK_BYTES], in[BLOCK_BYTES];
    struct iocb_raw cb[3], *cbs[3] = { &cb[0], &cb[1], &cb[2] };
    struct event_raw ev[QUEUE_EVENTS];
    char path[] = "/tmp/aio-XXXXXX";
    int fd = mkstemp(path);
    CHECK("mkstemp", fd >= 0, "errno=%d", errno);
    unlink(path);
    errno = 0;
    CHECK("setup_zero_rejected", io_setup(0, &ctx) == -1 && errno == EINVAL, "errno=%d", errno);
    errno = 0;
    CHECKC("setup", io_setup(QUEUE_EVENTS, &ctx) == 0 && ctx != 0, "ctx=%llu", (unsigned long long)ctx);
    memset(out, 'A', sizeof out);
    prepare(&cb[0], OP_PWRITE, fd, out, sizeof out, 0, 11);
    prepare(&cb[1], OP_FSYNC, fd, 0, 0, 0, 12);
    prepare(&cb[2], OP_NOOP, fd, 0, 0, 0, 13);
    errno = 0;
    long sub = io_submit(ctx, 3, cbs);
    CHECK("submit_three", sub == 3, "sub=%ld errno=%d", sub, errno);
    memset(ev, 0, sizeof ev);
    errno = 0;
    long got = io_getevents(ctx, 3, QUEUE_EVENTS, ev, 0);
    CHECK("getevents_three", got == 3, "got=%ld errno=%d", got, errno);
    CHECK("event_order_and_data", got == 3 && ev[0].data == 11 && ev[1].data == 12 && ev[2].data == 13, "d0=%llu d1=%llu", (unsigned long long)ev[0].data, (unsigned long long)ev[1].data);
    CHECK("write_result_bytes", got == 3 && ev[0].res == BLOCK_BYTES, "res=%lld", (long long)ev[0].res);
    CHECK("event_obj_is_iocb", got == 3 && ev[0].obj == (uint64_t)(uintptr_t)&cb[0], "obj=%llx", (unsigned long long)ev[0].obj);
    prepare(&cb[0], OP_PREAD, fd, in, sizeof in, 0, 21);
    sub = io_submit(ctx, 1, cbs);
    got = io_getevents(ctx, 1, 1, ev, 0);
    CHECK("read_roundtrip", sub == 1 && got == 1 && ev[0].res == BLOCK_BYTES && memcmp(in, out, sizeof in) == 0, "sub=%ld got=%ld res=%lld", sub, got, (long long)ev[0].res);
    got = io_getevents(ctx, 0, 1, ev, 0);
    CHECK("queue_drained", got == 0, "got=%ld", got);
    prepare(&cb[0], OP_PREAD, 999, in, sizeof in, 0, 31);
    sub = io_submit(ctx, 1, cbs);
    got = io_getevents(ctx, 1, 1, ev, 0);
    CHECK("bad_fd_reports_ebadf", sub == 1 && got == 1 && ev[0].res == -EBADF, "res=%lld", (long long)ev[0].res);
    CHECK("destroy", io_destroy(ctx) == 0, "errno=%d", errno);
    errno = 0;
    CHECK("destroy_twice_einval", io_destroy(ctx) == -1 && errno == EINVAL, "errno=%d", errno);
    errno = 0;
    CHECK("getevents_dead_ctx_einval", io_getevents(ctx, 0, 1, ev, 0) == -1 && errno == EINVAL, "errno=%d", errno);
    close(fd);
    return 0;
}
