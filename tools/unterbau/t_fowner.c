#define TNAME "fowner"
#include "t.h"
#include <fcntl.h>
#include <sys/ioctl.h>
#include <sys/socket.h>

#define IOCTL_FIOASYNC 0x5452
#define OWNER_TID 0
#define OWNER_PID 1
#define OWNER_PGRP 2
#define MAX_FLAGS 0xFFFFFF

struct owner_ex {
    int type;
    int pid;
};

static int owner_of(int fd, int *type)
{
    struct owner_ex ex = { -1, -1 };
    int rc = fcntl(fd, 16, &ex);
    *type = ex.type;
    return rc == 0 ? ex.pid : -1;
}

static void test_setown_pid(int fd)
{
    int type = -1;
    CHECK("getown_default_zero", fcntl(fd, F_GETOWN) == 0, "errno=%d", errno);
    CHECK("getown_ex_default", owner_of(fd, &type) == 0 && type == OWNER_TID, "type=%d", type);
    CHECK("setown_pid", fcntl(fd, F_SETOWN, getpid()) == 0, "errno=%d", errno);
    CHECK("getown_pid", fcntl(fd, F_GETOWN) == getpid(), "errno=%d", errno);
    CHECK("getown_ex_pid", owner_of(fd, &type) == getpid() && type == OWNER_PID, "type=%d", type);
    CHECK("setown_clear", fcntl(fd, F_SETOWN, 0) == 0 && fcntl(fd, F_GETOWN) == 0, "errno=%d", errno);
}

static void test_setown_pgrp(int fd)
{
    int type = -1;
    int pgrp = getpgrp();
    CHECK("setown_pgrp", fcntl(fd, F_SETOWN, -pgrp) == 0, "errno=%d", errno);
    CHECK("getown_ex_pgrp", owner_of(fd, &type) == pgrp && type == OWNER_PGRP, "pid=%d type=%d", pgrp, type);
    fcntl(fd, F_SETOWN, 0);
}

static void test_owner_ex(int fd)
{
    struct owner_ex ex = { OWNER_TID, getpid() };
    int type = -1;
    CHECK("setown_ex_tid", fcntl(fd, 15, &ex) == 0, "errno=%d", errno);
    CHECK("getown_ex_tid", owner_of(fd, &type) == getpid() && type == OWNER_TID, "type=%d", type);
    ex.type = OWNER_PGRP;
    CHECK("setown_ex_pgrp", fcntl(fd, 15, &ex) == 0 && owner_of(fd, &type) == getpid() && type == OWNER_PGRP, "type=%d", type);
    ex.type = 7;
    errno = 0;
    CHECK("setown_ex_bad_type", fcntl(fd, 15, &ex) == -1 && errno == EINVAL, "errno=%d", errno);
    errno = 0;
    CHECK("setown_ex_fault", fcntl(fd, 15, (void *)1) == -1 && errno == EFAULT, "errno=%d", errno);
    errno = 0;
    CHECK("getown_ex_fault", fcntl(fd, 16, (void *)1) == -1 && errno == EFAULT, "errno=%d", errno);
    fcntl(fd, F_SETOWN, 0);
}

static void test_owner_survives(int fd)
{
    CHECK("owner_set_before_flags", fcntl(fd, F_SETOWN, getpid()) == 0, "errno=%d", errno);
    CHECK("setfl_nonblock_keeps_owner", fcntl(fd, F_SETFL, O_NONBLOCK) == 0 && fcntl(fd, F_GETOWN) == getpid(), "errno=%d", errno);
    int dupfd = fcntl(fd, F_DUPFD, 10);
    CHECK("owner_shared_by_dup", dupfd >= 0 && fcntl(dupfd, F_GETOWN) == getpid(), "errno=%d", errno);
    if (dupfd >= 0) {
        fcntl(dupfd, F_SETOWN, 0);
        CHECK("owner_cleared_via_dup", fcntl(fd, F_GETOWN) == 0, "errno=%d", errno);
        close(dupfd);
    }
}

static void test_o_async(int fd)
{
    int fl = fcntl(fd, F_GETFL);
    CHECK("getfl_no_owner_bits", fl >= 0 && fl <= MAX_FLAGS, "fl=%x", fl);
    CHECK("setfl_async", fcntl(fd, F_SETFL, fl | O_ASYNC) == 0 && (fcntl(fd, F_GETFL) & O_ASYNC) != 0, "errno=%d", errno);
    CHECK("setfl_async_clear", fcntl(fd, F_SETFL, fl & ~O_ASYNC) == 0 && (fcntl(fd, F_GETFL) & O_ASYNC) == 0, "errno=%d", errno);
    int on = 1;
    CHECK("fioasync_sets_flag", ioctl(fd, IOCTL_FIOASYNC, &on) == 0 && (fcntl(fd, F_GETFL) & O_ASYNC) != 0, "errno=%d", errno);
    on = 0;
    CHECK("fioasync_clears_flag", ioctl(fd, IOCTL_FIOASYNC, &on) == 0 && (fcntl(fd, F_GETFL) & O_ASYNC) == 0, "errno=%d", errno);
}

static void test_signals(int fd)
{
    CHECK("setsig_accepted", fcntl(fd, F_SETSIG, 0) == 0, "errno=%d", errno);
    CHECK("getsig_accepted", fcntl(fd, F_GETSIG) == 0, "errno=%d", errno);
}

static void test_badfd(void)
{
    errno = 0;
    CHECK("setown_badfd", fcntl(-1, F_SETOWN, 1) == -1 && errno == EBADF, "errno=%d", errno);
    errno = 0;
    CHECK("getown_badfd", fcntl(-1, F_GETOWN) == -1 && errno == EBADF, "errno=%d", errno);
}

int main(void)
{
    int pair[2];
    int pipefd[2];
    CHECK("socketpair_open", socketpair(AF_UNIX, SOCK_STREAM, 0, pair) == 0, "errno=%d", errno);
    CHECK("pipe_open", pipe(pipefd) == 0, "errno=%d", errno);
    test_setown_pid(pair[0]);
    test_setown_pgrp(pair[0]);
    test_owner_ex(pair[0]);
    test_owner_survives(pair[0]);
    test_o_async(pair[0]);
    test_o_async(pipefd[0]);
    test_signals(pair[1]);
    test_badfd();
    close(pair[0]);
    close(pair[1]);
    close(pipefd[0]);
    close(pipefd[1]);
    return 0;
}
