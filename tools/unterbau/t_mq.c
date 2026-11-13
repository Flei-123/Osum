#define TNAME "mq"
#include "t.h"
#include <fcntl.h>
#include <poll.h>
#include <signal.h>
#include <stdint.h>
#include <sys/epoll.h>
#include <sys/syscall.h>
#include <sys/wait.h>
#include <time.h>

#define NR_MQ_OPEN 240
#define NR_MQ_UNLINK 241
#define NR_MQ_TIMEDSEND 242
#define NR_MQ_TIMEDRECEIVE 243
#define NR_MQ_NOTIFY 244
#define NR_MQ_GETSETATTR 245
#define MSG_MAX 4
#define MSG_SIZE 64
#define BIG_MAXMSG 100000
#define HANDOFF_MS 300
#define SIG_NOTIFY SIGUSR1
#define NANOS_PER_SEC 1000000000L

struct attr {
    long flags;
    long maxmsg;
    long msgsize;
    long curmsgs;
    long reserved[4];
};

struct sigev {
    long value;
    int signo;
    int notify;
    char pad[48];
};

static volatile int got_signal;

static void on_signal(int sig)
{
    (void)sig;
    got_signal = 1;
}

static long raw(long nr, long a, long b, long c, long d, long e)
{
    errno = 0;
    return syscall(nr, a, b, c, d, e, 0);
}

static void now_plus(struct timespec *ts, long ms)
{
    clock_gettime(CLOCK_REALTIME, ts);
    ts->tv_nsec += ms * 1000000L;
    ts->tv_sec += ts->tv_nsec / NANOS_PER_SEC;
    ts->tv_nsec %= NANOS_PER_SEC;
}

static long send_msg(long fd, const char *text, unsigned prio)
{
    return raw(NR_MQ_TIMEDSEND, fd, (long)text, (long)strlen(text), prio, 0);
}

static long recv_msg(long fd, char *buf, unsigned *prio)
{
    memset(buf, 0, MSG_SIZE);
    return raw(NR_MQ_TIMEDRECEIVE, fd, (long)buf, MSG_SIZE, (long)prio, 0);
}

static long open_queue(const char *name, long flags)
{
    struct attr a = {0, MSG_MAX, MSG_SIZE, 0, {0}};
    return raw(NR_MQ_OPEN, (long)name, flags, 0600, (long)&a, 0);
}

static void open_checks(long *fd_out)
{
    long fd = open_queue("tq1", O_RDWR | O_CREAT | O_EXCL);
    CHECKC("open_create", fd >= 0);
    *fd_out = fd;
    long r = open_queue("tq1", O_RDWR | O_CREAT | O_EXCL);
    CHECK("open_excl_exists", r == -1 && errno == EEXIST, "r=%ld errno=%d", r, errno);
    r = raw(NR_MQ_OPEN, (long)"tq_missing", O_RDWR, 0, 0, 0);
    CHECK("open_missing_enoent", r == -1 && errno == ENOENT, "r=%ld errno=%d", r, errno);
    r = raw(NR_MQ_OPEN, (long)"a/b", O_RDWR | O_CREAT, 0600, 0, 0);
    CHECK("open_slash_eacces", r == -1 && errno == EACCES, "r=%ld errno=%d", r, errno);
    r = raw(NR_MQ_OPEN, (long)"tq1", 3, 0, 0, 0);
    CHECK("open_bad_accmode", r == -1 && errno == EINVAL, "r=%ld errno=%d", r, errno);
    struct attr bad = {0, 0, MSG_SIZE, 0, {0}};
    r = raw(NR_MQ_OPEN, (long)"tq_bad", O_RDWR | O_CREAT, 0600, (long)&bad, 0);
    CHECK("open_attr_zero_maxmsg", r == -1 && errno == EINVAL, "r=%ld errno=%d", r, errno);
    bad.maxmsg = BIG_MAXMSG;
    r = raw(NR_MQ_OPEN, (long)"tq_bad", O_RDWR | O_CREAT, 0600, (long)&bad, 0);
    CHECK("open_attr_too_big", r == -1 && errno == EINVAL, "r=%ld errno=%d", r, errno);
    r = raw(NR_MQ_OPEN, 0, O_RDWR, 0, 0, 0);
    CHECK("open_null_name", r == -1 && errno == EFAULT, "r=%ld errno=%d", r, errno);
    long again = raw(NR_MQ_OPEN, (long)"tq1", O_RDONLY, 0, 0, 0);
    CHECKC("open_existing", again >= 0);
    if (again >= 0)
        close(again);
}

static void attr_checks(long fd)
{
    struct attr a;
    memset(&a, 0xff, sizeof a);
    long r = raw(NR_MQ_GETSETATTR, fd, 0, (long)&a, 0, 0);
    CHECK("getattr_values", r == 0 && a.maxmsg == MSG_MAX && a.msgsize == MSG_SIZE && a.curmsgs == 0 && a.flags == 0,
          "r=%ld max=%ld size=%ld cur=%ld flags=%ld", r, a.maxmsg, a.msgsize, a.curmsgs, a.flags);
    struct attr set = {O_NONBLOCK, 0, 0, 0, {0}};
    struct attr old;
    r = raw(NR_MQ_GETSETATTR, fd, (long)&set, (long)&old, 0, 0);
    CHECK("setattr_nonblock", r == 0 && old.flags == 0, "r=%ld old=%ld", r, old.flags);
    r = raw(NR_MQ_GETSETATTR, fd, 0, (long)&a, 0, 0);
    CHECK("setattr_sticks", r == 0 && a.flags == O_NONBLOCK, "r=%ld flags=%ld", r, a.flags);
    set.flags = O_NONBLOCK | 1;
    r = raw(NR_MQ_GETSETATTR, fd, (long)&set, 0, 0, 0);
    CHECK("setattr_bad_flags", r == -1 && errno == EINVAL, "r=%ld errno=%d", r, errno);
    r = raw(NR_MQ_GETSETATTR, 0, 0, (long)&a, 0, 0);
    CHECK("getattr_not_queue", r == -1 && errno == EBADF, "r=%ld errno=%d", r, errno);
}

static void order_checks(long fd)
{
    char buf[MSG_SIZE];
    unsigned prio = 99;
    long r = recv_msg(fd, buf, &prio);
    CHECK("recv_empty_eagain", r == -1 && errno == EAGAIN, "r=%ld errno=%d", r, errno);
    CHECKC("send_low", send_msg(fd, "low", 1) == 0);
    CHECKC("send_high", send_msg(fd, "high", 9) == 0);
    CHECKC("send_mid", send_msg(fd, "mid", 5) == 0);
    CHECKC("send_mid2", send_msg(fd, "mid2", 5) == 0);
    r = send_msg(fd, "full", 0);
    CHECK("send_full_eagain", r == -1 && errno == EAGAIN, "r=%ld errno=%d", r, errno);
    struct attr a;
    raw(NR_MQ_GETSETATTR, fd, 0, (long)&a, 0, 0);
    CHECK("curmsgs_four", a.curmsgs == MSG_MAX, "cur=%ld", a.curmsgs);
    r = recv_msg(fd, buf, &prio);
    CHECK("recv_highest_first", r == 4 && prio == 9 && !strcmp(buf, "high"), "r=%ld prio=%u buf=%s", r, prio, buf);
    r = recv_msg(fd, buf, &prio);
    CHECK("recv_fifo_in_prio_a", r == 3 && prio == 5 && !strcmp(buf, "mid"), "r=%ld prio=%u buf=%s", r, prio, buf);
    r = recv_msg(fd, buf, &prio);
    CHECK("recv_fifo_in_prio_b", r == 4 && prio == 5 && !strcmp(buf, "mid2"), "r=%ld prio=%u buf=%s", r, prio, buf);
    r = recv_msg(fd, buf, &prio);
    CHECK("recv_lowest_last", r == 3 && prio == 1 && !strcmp(buf, "low"), "r=%ld prio=%u buf=%s", r, prio, buf);
    r = raw(NR_MQ_TIMEDSEND, fd, (long)"x", 1, 32768, 0);
    CHECK("send_prio_too_big", r == -1 && errno == EINVAL, "r=%ld errno=%d", r, errno);
    char big[MSG_SIZE + 1];
    memset(big, 'z', sizeof big);
    r = raw(NR_MQ_TIMEDSEND, fd, (long)big, sizeof big, 0, 0);
    CHECK("send_too_long", r == -1 && errno == EMSGSIZE, "r=%ld errno=%d", r, errno);
    r = raw(NR_MQ_TIMEDRECEIVE, fd, (long)buf, MSG_SIZE - 1, 0, 0);
    CHECK("recv_small_buffer", r == -1 && errno == EMSGSIZE, "r=%ld errno=%d", r, errno);
    r = raw(NR_MQ_TIMEDSEND, fd, 0, 0, 0, 0);
    CHECK("send_zero_length", r == 0, "r=%ld errno=%d", r, errno);
    r = recv_msg(fd, buf, &prio);
    CHECK("recv_zero_length", r == 0, "r=%ld errno=%d", r, errno);
    r = raw(NR_MQ_TIMEDSEND, fd, 1, 1, 0, 0);
    CHECK("send_bad_pointer", r == -1 && errno == EFAULT, "r=%ld errno=%d", r, errno);
}

static void timeout_checks(long fd)
{
    struct attr set = {0, 0, 0, 0, {0}};
    raw(NR_MQ_GETSETATTR, fd, (long)&set, 0, 0, 0);
    char buf[MSG_SIZE];
    struct timespec ts;
    now_plus(&ts, 100);
    long r = raw(NR_MQ_TIMEDRECEIVE, fd, (long)buf, MSG_SIZE, 0, (long)&ts);
    CHECK("recv_timeout", r == -1 && errno == ETIMEDOUT, "r=%ld errno=%d", r, errno);
    struct timespec bad = {0, NANOS_PER_SEC};
    r = raw(NR_MQ_TIMEDRECEIVE, fd, (long)buf, MSG_SIZE, 0, (long)&bad);
    CHECK("recv_bad_timespec", r == -1 && errno == EINVAL, "r=%ld errno=%d", r, errno);
    int i;
    for (i = 0; i < MSG_MAX; i++)
        send_msg(fd, "f", 0);
    now_plus(&ts, 100);
    r = raw(NR_MQ_TIMEDSEND, fd, (long)"x", 1, 0, (long)&ts);
    CHECK("send_timeout", r == -1 && errno == ETIMEDOUT, "r=%ld errno=%d", r, errno);
    struct timespec past = {1, 0};
    r = raw(NR_MQ_TIMEDSEND, fd, (long)"x", 1, 0, (long)&past);
    CHECK("send_past_deadline", r == -1 && errno == ETIMEDOUT, "r=%ld errno=%d", r, errno);
    for (i = 0; i < MSG_MAX; i++)
        recv_msg(fd, buf, 0);
}

static void blocking_checks(long fd)
{
    pid_t child = fork();
    if (child == 0) {
        struct timespec nap = {0, HANDOFF_MS * 1000000L};
        nanosleep(&nap, NULL);
        send_msg(fd, "wake", 3);
        _exit(0);
    }
    char buf[MSG_SIZE];
    unsigned prio = 0;
    struct timespec ts;
    now_plus(&ts, 5000);
    long r = raw(NR_MQ_TIMEDRECEIVE, fd, (long)buf, MSG_SIZE, (long)&prio, (long)&ts);
    CHECK("recv_blocks_until_send", r == 4 && prio == 3 && !strcmp(buf, "wake"), "r=%ld errno=%d buf=%s", r, errno, buf);
    waitpid(child, NULL, 0);
    int i;
    for (i = 0; i < MSG_MAX; i++)
        send_msg(fd, "f", 0);
    child = fork();
    if (child == 0) {
        struct timespec nap = {0, HANDOFF_MS * 1000000L};
        nanosleep(&nap, NULL);
        recv_msg(fd, buf, 0);
        _exit(0);
    }
    now_plus(&ts, 5000);
    r = raw(NR_MQ_TIMEDSEND, fd, (long)"late", 4, 0, (long)&ts);
    CHECK("send_blocks_until_recv", r == 0, "r=%ld errno=%d", r, errno);
    waitpid(child, NULL, 0);
    for (i = 0; i < MSG_MAX; i++)
        recv_msg(fd, buf, 0);
}

static void poll_checks(long fd)
{
    struct pollfd p = {(int)fd, POLLIN, 0};
    int n = poll(&p, 1, 0);
    CHECK("poll_empty_not_readable", n == 0, "n=%d rev=%x", n, p.revents);
    p.events = POLLOUT;
    n = poll(&p, 1, 0);
    CHECK("poll_empty_writable", n == 1 && (p.revents & POLLOUT), "n=%d rev=%x", n, p.revents);
    int ep = epoll_create1(0);
    struct epoll_event ev = {EPOLLIN, {.u32 = 7}};
    long r = epoll_ctl(ep, EPOLL_CTL_ADD, (int)fd, &ev);
    CHECK("epoll_add_queue", r == 0, "r=%ld errno=%d", r, errno);
    struct epoll_event out;
    n = epoll_wait(ep, &out, 1, 0);
    CHECK("epoll_idle", n == 0, "n=%d", n);
    send_msg(fd, "ep", 0);
    n = epoll_wait(ep, &out, 1, 200);
    CHECK("epoll_readable", n == 1 && out.data.u32 == 7 && (out.events & EPOLLIN), "n=%d", n);
    char buf[MSG_SIZE];
    recv_msg(fd, buf, 0);
    close(ep);
}

static void notify_checks(long fd)
{
    struct sigaction sa;
    memset(&sa, 0, sizeof sa);
    sa.sa_handler = on_signal;
    sigaction(SIG_NOTIFY, &sa, NULL);
    struct sigev ev;
    memset(&ev, 0, sizeof ev);
    ev.signo = SIG_NOTIFY;
    ev.notify = SIGEV_SIGNAL;
    long r = raw(NR_MQ_NOTIFY, fd, (long)&ev, 0, 0, 0);
    CHECK("notify_register", r == 0, "r=%ld errno=%d", r, errno);
    r = raw(NR_MQ_NOTIFY, fd, (long)&ev, 0, 0, 0);
    CHECK("notify_busy", r == -1 && errno == EBUSY, "r=%ld errno=%d", r, errno);
    got_signal = 0;
    send_msg(fd, "n", 0);
    struct timespec nap = {0, 100000000L};
    nanosleep(&nap, NULL);
    CHECK("notify_signal_arrives", got_signal == 1, "got=%d", got_signal);
    got_signal = 0;
    send_msg(fd, "n2", 0);
    nanosleep(&nap, NULL);
    CHECK("notify_one_shot", got_signal == 0, "got=%d", got_signal);
    char buf[MSG_SIZE];
    recv_msg(fd, buf, 0);
    recv_msg(fd, buf, 0);
    r = raw(NR_MQ_NOTIFY, fd, (long)&ev, 0, 0, 0);
    CHECK("notify_reregister", r == 0, "r=%ld errno=%d", r, errno);
    r = raw(NR_MQ_NOTIFY, fd, 0, 0, 0, 0);
    CHECK("notify_remove", r == 0, "r=%ld errno=%d", r, errno);
    ev.signo = 0;
    r = raw(NR_MQ_NOTIFY, fd, (long)&ev, 0, 0, 0);
    CHECK("notify_bad_signo", r == -1 && errno == EINVAL, "r=%ld errno=%d", r, errno);
}

static void unlink_checks(long fd)
{
    long r = raw(NR_MQ_UNLINK, (long)"tq1", 0, 0, 0, 0);
    CHECK("unlink_ok", r == 0, "r=%ld errno=%d", r, errno);
    r = raw(NR_MQ_UNLINK, (long)"tq1", 0, 0, 0, 0);
    CHECK("unlink_twice_enoent", r == -1 && errno == ENOENT, "r=%ld errno=%d", r, errno);
    r = raw(NR_MQ_OPEN, (long)"tq1", O_RDWR, 0, 0, 0);
    CHECK("open_after_unlink_enoent", r == -1 && errno == ENOENT, "r=%ld errno=%d", r, errno);
    CHECK("unlinked_still_usable", send_msg(fd, "alive", 2) == 0, "errno=%d", errno);
    char buf[MSG_SIZE];
    r = recv_msg(fd, buf, 0);
    CHECK("unlinked_recv", r == 5 && !strcmp(buf, "alive"), "r=%ld buf=%s", r, buf);
    long again = open_queue("tq1", O_RDWR | O_CREAT | O_EXCL);
    CHECK("unlinked_name_reusable", again >= 0, "errno=%d", errno);
    struct attr a;
    raw(NR_MQ_GETSETATTR, again, 0, (long)&a, 0, 0);
    CHECK("recreated_is_empty", a.curmsgs == 0, "cur=%ld", a.curmsgs);
    r = raw(NR_MQ_UNLINK, (long)"tq1", 0, 0, 0, 0);
    close(again);
    close(fd);
    long fresh = open_queue("tq1", O_RDWR | O_CREAT);
    CHECK("fresh_after_close_all", fresh >= 0, "errno=%d", errno);
    raw(NR_MQ_UNLINK, (long)"tq1", 0, 0, 0, 0);
    close(fresh);
    r = write(fresh, "x", 1);
    CHECK("closed_fd_ebadf", r == -1 && errno == EBADF, "r=%ld errno=%d", r, errno);
}

static void mode_checks(void)
{
    long ro = open_queue("tq2", O_RDONLY | O_CREAT);
    long wo = raw(NR_MQ_OPEN, (long)"tq2", O_WRONLY, 0, 0, 0);
    CHECKC("open_modes", ro >= 0 && wo >= 0);
    long r = send_msg(ro, "x", 0);
    CHECK("send_on_readonly_ebadf", r == -1 && errno == EBADF, "r=%ld errno=%d", r, errno);
    char buf[MSG_SIZE];
    r = raw(NR_MQ_TIMEDRECEIVE, wo, (long)buf, MSG_SIZE, 0, 0);
    CHECK("recv_on_writeonly_ebadf", r == -1 && errno == EBADF, "r=%ld errno=%d", r, errno);
    r = send_msg(wo, "ok", 0);
    CHECK("send_on_writeonly", r == 0, "r=%ld errno=%d", r, errno);
    r = recv_msg(ro, buf, 0);
    CHECK("recv_on_readonly", r == 2 && !strcmp(buf, "ok"), "r=%ld errno=%d", r, errno);
    r = send_msg(0, "x", 0);
    CHECK("send_on_stdin_ebadf", r == -1 && errno == EBADF, "r=%ld errno=%d", r, errno);
    raw(NR_MQ_UNLINK, (long)"tq2", 0, 0, 0, 0);
    close(ro);
    close(wo);
}

int main(void)
{
    long fd = -1;
    open_checks(&fd);
    if (fd < 0)
        return 0;
    attr_checks(fd);
    order_checks(fd);
    timeout_checks(fd);
    blocking_checks(fd);
    poll_checks(fd);
    notify_checks(fd);
    mode_checks();
    unlink_checks(fd);
    return 0;
}
