#define TNAME "sockfree"
#include "t.h"
#include <fcntl.h>
#include <pthread.h>
#include <signal.h>
#include <stdint.h>
#include <stdlib.h>
#include <sys/socket.h>
#include <sys/uio.h>

#define MSG_BYTES 36
#define ROUNDS 6000
#define JITTER_MASK 63
#define BAD_POINTERS 7

static int sv[2];
static volatile int armed;
static volatile int finished;
static volatile int stop;
static volatile long sent_ok;
static volatile long sent_pipe;
static volatile long sent_other;

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

static void *sender(void *arg)
{
    char buf[MSG_BYTES];
    (void)arg;
    memset(buf, 'w', sizeof buf);
    while (!stop) {
        while (armed != 1 && !stop)
            relax();
        if (stop)
            break;
        int fd = sv[0];
        armed = 2;
        errno = 0;
        ssize_t w = write(fd, buf, sizeof buf);
        if (w == (ssize_t)sizeof buf)
            sent_ok++;
        else if (w < 0 && errno == EPIPE)
            sent_pipe++;
        else
            sent_other++;
        finished = 1;
    }
    return NULL;
}

static void close_race(void)
{
    uint32_t seed = 0x9e3779b9;
    pthread_t th;
    signal(SIGPIPE, SIG_IGN);
    if (pthread_create(&th, NULL, sender, NULL) != 0) {
        FAIL("close_race_survived", "pthread_create failed");
        return;
    }
    for (int i = 0; i < ROUNDS; i++) {
        if (socketpair(AF_UNIX, SOCK_STREAM, 0, sv) != 0) {
            FAIL("close_race_survived", "socketpair failed round %d errno %d", i, errno);
            stop = 1;
            armed = 1;
            pthread_join(th, NULL);
            return;
        }
        finished = 0;
        armed = 1;
        while (armed != 2)
            relax();
        for (uint32_t j = next_random(&seed) & JITTER_MASK; j > 0; j--)
            relax();
        close(sv[1]);
        while (!finished)
            relax();
        armed = 0;
        close(sv[0]);
    }
    stop = 1;
    armed = 1;
    pthread_join(th, NULL);
    CHECK("close_race_no_unexpected_result", sent_other == 0, "other results %ld (ok %ld, epipe %ld)", sent_other, sent_ok, sent_pipe);
    PASS("close_race_survived");
}

static int expect_fault(ssize_t r)
{
    return r == -1 && errno == EFAULT;
}

static void bad_pointers(void)
{
    static char alias_target[64];
    unsigned long bad[BAD_POINTERS] = {
        0xf000ff53f000ff53UL,
        0xffff800000000000UL,
        0xffff80004787141cUL,
        0x0000800000000000UL,
        0xffffffffffffffffUL,
        (unsigned long)alias_target | (1UL << 48),
        (unsigned long)alias_target | 0xf000000000000000UL,
    };
    int pipefd[2];
    int pair[2];
    int fails_pipe_write = 0, fails_pipe_read = 0, fails_send = 0, fails_recv = 0, fails_sendmsg = 0, fails_recvmsg = 0;
    if (pipe(pipefd) != 0 || socketpair(AF_UNIX, SOCK_STREAM, 0, pair) != 0) {
        FAIL("bad_pointers_setup", "errno %d", errno);
        return;
    }
    for (int i = 0; i < BAD_POINTERS; i++) {
        void *p = (void *)bad[i];
        struct iovec iov = { p, MSG_BYTES };
        struct msghdr mh;
        memset(&mh, 0, sizeof mh);
        mh.msg_iov = &iov;
        mh.msg_iovlen = 1;
        errno = 0;
        if (!expect_fault(write(pipefd[1], p, MSG_BYTES)))
            fails_pipe_write++;
        (void)!write(pipefd[1], "0123456789012345678901234567890123456", MSG_BYTES);
        errno = 0;
        if (!expect_fault(read(pipefd[0], p, MSG_BYTES)))
            fails_pipe_read++;
        char drain[MSG_BYTES];
        (void)!read(pipefd[0], drain, sizeof drain);
        errno = 0;
        if (!expect_fault(send(pair[0], p, MSG_BYTES, MSG_DONTWAIT)))
            fails_send++;
        errno = 0;
        if (!expect_fault(sendmsg(pair[0], &mh, MSG_DONTWAIT)))
            fails_sendmsg++;
        (void)!send(pair[0], "0123456789012345678901234567890123456", MSG_BYTES, 0);
        errno = 0;
        if (!expect_fault(recvmsg(pair[1], &mh, MSG_DONTWAIT)))
            fails_recvmsg++;
        (void)!recv(pair[1], drain, sizeof drain, MSG_DONTWAIT);
        (void)!send(pair[0], "0123456789012345678901234567890123456", MSG_BYTES, 0);
        errno = 0;
        if (!expect_fault(recv(pair[1], p, MSG_BYTES, MSG_DONTWAIT)))
            fails_recv++;
        (void)!recv(pair[1], drain, sizeof drain, MSG_DONTWAIT);
    }
    CHECK("bad_pointer_pipe_write", fails_pipe_write == 0, "%d of %d not EFAULT", fails_pipe_write, BAD_POINTERS);
    CHECK("bad_pointer_pipe_read", fails_pipe_read == 0, "%d of %d not EFAULT", fails_pipe_read, BAD_POINTERS);
    CHECK("bad_pointer_send", fails_send == 0, "%d of %d not EFAULT", fails_send, BAD_POINTERS);
    CHECK("bad_pointer_sendmsg", fails_sendmsg == 0, "%d of %d not EFAULT", fails_sendmsg, BAD_POINTERS);
    CHECK("bad_pointer_recv", fails_recv == 0, "%d of %d not EFAULT", fails_recv, BAD_POINTERS);
    CHECK("bad_pointer_recvmsg", fails_recvmsg == 0, "%d of %d not EFAULT", fails_recvmsg, BAD_POINTERS);
    close(pipefd[0]);
    close(pipefd[1]);
    close(pair[0]);
    close(pair[1]);
}

int main(void)
{
    bad_pointers();
    close_race();
    return 0;
}
