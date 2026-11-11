#define TNAME "syscompat"
#include "t.h"
#include <fcntl.h>
#include <signal.h>
#include <stdint.h>
#include <stdlib.h>
#include <time.h>
#include <sys/epoll.h>
#include <sys/mman.h>
#include <sys/socket.h>
#include <sys/stat.h>
#include <sys/syscall.h>
#include <sys/time.h>
#include <sys/times.h>
#include <sys/uio.h>
#include <utime.h>

struct mmsg {
    struct msghdr hdr;
    unsigned int len;
};

struct cap_hdr {
    uint32_t version;
    int pid;
};

struct cap_data {
    uint32_t effective;
    uint32_t permitted;
    uint32_t inheritable;
};

struct open_how {
    uint64_t flags;
    uint64_t mode;
    uint64_t resolve;
};

struct old_dirent {
    unsigned long ino;
    unsigned long off;
    unsigned short reclen;
    char name[];
};

static int put(const char *path, const char *text)
{
    int fd = open(path, O_WRONLY | O_CREAT | O_TRUNC, 0644);
    if (fd < 0)
        return -1;
    int n = write(fd, text, strlen(text));
    close(fd);
    return n;
}

static void check_messages(void)
{
    int sv[2];
    char bufs[4][16];
    struct iovec iov[4];
    struct mmsg mm[4];
    int i;
    if (socketpair(AF_UNIX, SOCK_DGRAM, 0, sv) != 0) {
        GAP("socketpair", "errno=%d", errno);
        return;
    }
    send(sv[0], "aa", 2, 0);
    send(sv[0], "bbb", 3, 0);
    send(sv[0], "c", 1, 0);
    memset(mm, 0, sizeof mm);
    for (i = 0; i < 4; i++) {
        iov[i].iov_base = bufs[i];
        iov[i].iov_len = sizeof bufs[i];
        mm[i].hdr.msg_iov = &iov[i];
        mm[i].hdr.msg_iovlen = 1;
    }
    errno = 0;
    long r = syscall(299, sv[1], mm, 4, MSG_DONTWAIT, 0);
    CHECKC("recvmmsg_count", r == 3);
    CHECK("recvmmsg_lengths", mm[0].len == 2 && mm[1].len == 3 && mm[2].len == 1,
          "%u %u %u", mm[0].len, mm[1].len, mm[2].len);
    CHECK("recvmmsg_data", !memcmp(bufs[1], "bbb", 3), "second datagram");
    struct iovec out[2] = {{"xy", 2}, {"zzz", 3}};
    struct mmsg send_mm[2];
    memset(send_mm, 0, sizeof send_mm);
    send_mm[0].hdr.msg_iov = &out[0];
    send_mm[0].hdr.msg_iovlen = 1;
    send_mm[1].hdr.msg_iov = &out[1];
    send_mm[1].hdr.msg_iovlen = 1;
    errno = 0;
    r = syscall(307, sv[0], send_mm, 2, 0);
    CHECKC("sendmmsg_count", r == 2);
    CHECK("sendmmsg_lengths", send_mm[0].len == 2 && send_mm[1].len == 3, "%u %u",
          send_mm[0].len, send_mm[1].len);
    char got[16];
    CHECK("sendmmsg_delivered", recv(sv[1], got, sizeof got, 0) == 2, "first datagram");
    close(sv[0]);
    close(sv[1]);
}

static void check_memory(void)
{
    unsigned char vec[3] = {0, 0, 0};
    char *p = mmap(0, 3 * 4096, PROT_READ | PROT_WRITE, MAP_PRIVATE | MAP_ANONYMOUS, -1, 0);
    if (p == MAP_FAILED) {
        FAIL("mmap", "errno=%d", errno);
        return;
    }
    memset(p, 1, 3 * 4096);
    errno = 0;
    long r = syscall(27, p, 3 * 4096, vec);
    CHECKC("mincore_call", r == 0);
    CHECK("mincore_resident", (vec[0] & 1) && (vec[1] & 1) && (vec[2] & 1), "%d %d %d", vec[0],
          vec[1], vec[2]);
    errno = 0;
    CHECK("mincore_unaligned", syscall(27, p + 1, 4096, vec) == -1 && errno == EINVAL, "errno=%d",
          errno);
    errno = 0;
    CHECKC("mlock2", syscall(325, p, 4096, 0) == 0);
    munmap(p, 3 * 4096);
}

static void check_xattr_caps(void)
{
    char v[8];
    errno = 0;
    long r = syscall(191, "/tmp", "user.x", v, sizeof v);
    CHECK("getxattr_refused", r == -1 && (errno == EOPNOTSUPP || errno == ENODATA), "r=%ld errno=%d",
          r, errno);
    errno = 0;
    r = syscall(188, "/tmp", "user.x", "1", 1, 0);
    CHECK("setxattr_refused", r == -1 && errno == EOPNOTSUPP, "r=%ld errno=%d", r, errno);
    struct cap_hdr hdr = {0x20080522, 0};
    struct cap_data data[2];
    errno = 0;
    CHECKC("capget_v3", syscall(125, &hdr, data) == 0);
    struct cap_hdr bad = {1234, 0};
    errno = 0;
    CHECK("capget_bad_version", syscall(125, &bad, data) == -1 && errno == EINVAL, "errno=%d", errno);
    errno = 0;
    CHECKC("capset_roundtrip", syscall(126, &hdr, data) == 0);
    struct tms t;
    errno = 0;
    clock_t c = times(&t);
    CHECK("times_ticks", c != (clock_t)-1, "errno=%d", errno);
    errno = 0;
    long sid = syscall(124, 0);
    CHECKC("getsid_self", sid >= 0);
    errno = 0;
    CHECK("getsid_missing_pid", syscall(124, 999999) == -1 && errno == ESRCH, "errno=%d", errno);
}

static void check_files(void)
{
    struct stat st;
    mkdir("/tmp/sc", 0755);
    put("/tmp/sc/t", "0123456789");
    errno = 0;
    CHECKC("truncate_call", syscall(76, "/tmp/sc/t", 4) == 0);
    CHECK("truncate_size", stat("/tmp/sc/t", &st) == 0 && st.st_size == 4, "size=%ld",
          (long)st.st_size);
    struct utimbuf ub = {1000, 2000};
    errno = 0;
    CHECKC("utime_call", syscall(132, "/tmp/sc/t", &ub) == 0);
    CHECK("utime_mtime", stat("/tmp/sc/t", &st) == 0 && st.st_mtime == 2000, "mtime=%ld",
          (long)st.st_mtime);
    struct timeval tv[2] = {{3000, 0}, {4000, 0}};
    errno = 0;
    CHECKC("utimes_call", syscall(235, "/tmp/sc/t", tv) == 0);
    CHECK("utimes_mtime", stat("/tmp/sc/t", &st) == 0 && st.st_mtime == 4000, "mtime=%ld",
          (long)st.st_mtime);
    struct timeval tw[2] = {{5000, 0}, {6000, 0}};
    errno = 0;
    CHECKC("futimesat_call", syscall(261, AT_FDCWD, "/tmp/sc/t", tw) == 0);
    CHECK("futimesat_mtime", stat("/tmp/sc/t", &st) == 0 && st.st_mtime == 6000, "mtime=%ld",
          (long)st.st_mtime);
    errno = 0;
    CHECKC("fchmodat2_call", syscall(452, AT_FDCWD, "/tmp/sc/t", 0600, 0) == 0);
    CHECK("fchmodat2_mode", stat("/tmp/sc/t", &st) == 0 && (st.st_mode & 0777) == 0600, "mode=%o",
          st.st_mode & 0777);
    int fd = open("/tmp/sc/t", O_RDONLY);
    errno = 0;
    CHECKC("syncfs", syscall(306, fd) == 0);
    errno = 0;
    CHECKC("sync_file_range", syscall(277, fd, 0, 0, 0) == 0);
    close(fd);
    struct open_how how = {O_RDONLY, 0, 0};
    errno = 0;
    fd = syscall(437, AT_FDCWD, "/tmp/sc/t", &how, sizeof how);
    CHECKC("openat2_call", fd >= 0);
    char b[8] = {0};
    CHECK("openat2_read", fd >= 0 && read(fd, b, 4) == 4 && !memcmp(b, "0123", 4), "read");
    if (fd >= 0)
        close(fd);
    how.resolve = 0xFF;
    errno = 0;
    CHECK("openat2_resolve_refused", syscall(437, AT_FDCWD, "/tmp/sc/t", &how, sizeof how) == -1,
          "accepted RESOLVE flags");
    errno = 0;
    CHECK("openat2_short_how", syscall(437, AT_FDCWD, "/tmp/sc/t", &how, 8) == -1 && errno == EINVAL,
          "errno=%d", errno);
}

static void check_dirents(void)
{
    char buf[1024];
    mkdir("/tmp/sc/d", 0755);
    put("/tmp/sc/d/alpha", "x");
    mkdir("/tmp/sc/d/beta", 0755);
    int fd = open("/tmp/sc/d", O_RDONLY | O_DIRECTORY);
    if (fd < 0) {
        FAIL("open_dir", "errno=%d", errno);
        return;
    }
    errno = 0;
    long n = syscall(78, fd, buf, sizeof buf);
    CHECKC("getdents_call", n > 0);
    int saw_alpha = 0, saw_beta = 0, kind_ok = 1;
    long pos = 0;
    while (n > 0 && pos < n) {
        struct old_dirent *d = (struct old_dirent *)(buf + pos);
        char kind = buf[pos + d->reclen - 1];
        if (!strcmp(d->name, "alpha")) {
            saw_alpha = 1;
            kind_ok &= kind == 8;
        }
        if (!strcmp(d->name, "beta")) {
            saw_beta = 1;
            kind_ok &= kind == 4;
        }
        pos += d->reclen;
    }
    CHECK("getdents_names", saw_alpha && saw_beta, "alpha=%d beta=%d", saw_alpha, saw_beta);
    CHECK("getdents_types", kind_ok, "d_type at reclen-1 wrong");
    close(fd);
}

static void check_fd_calls(void)
{
    int a = open("/tmp/sc/t", O_RDONLY);
    int b = dup(a);
    int c = dup(a);
    errno = 0;
    CHECKC("close_range_call", syscall(436, b, c, 0) == 0);
    CHECK("close_range_closed", fcntl(b, F_GETFD) == -1 && errno == EBADF && fcntl(c, F_GETFD) == -1,
          "fd still open");
    CHECK("close_range_keeps_first", fcntl(a, F_GETFD) != -1, "closed outside the range");
    b = dup(a);
    errno = 0;
    CHECKC("close_range_cloexec", syscall(436, b, b, 4) == 0);
    CHECK("close_range_cloexec_set", (fcntl(b, F_GETFD) & FD_CLOEXEC) != 0, "flag missing");
    errno = 0;
    CHECK("close_range_bad_order", syscall(436, 5, 3, 0) == -1 && errno == EINVAL, "errno=%d", errno);
    close(a);
    close(b);
}

static void check_copy(void)
{
    char b[32] = {0};
    put("/tmp/sc/src", "hello world");
    int in = open("/tmp/sc/src", O_RDONLY);
    int out = open("/tmp/sc/dst", O_WRONLY | O_CREAT | O_TRUNC, 0644);
    errno = 0;
    long r = syscall(326, in, 0, out, 0, 11, 0);
    CHECKC("copy_file_range_count", r == 11);
    close(in);
    close(out);
    int fd = open("/tmp/sc/dst", O_RDONLY);
    CHECK("copy_file_range_data", fd >= 0 && read(fd, b, 11) == 11 && !strcmp(b, "hello world"), "got %s", b);
    if (fd >= 0)
        close(fd);
    in = open("/tmp/sc/src", O_RDONLY);
    out = open("/tmp/sc/dst2", O_WRONLY | O_CREAT | O_TRUNC, 0644);
    long off = 6;
    errno = 0;
    r = syscall(326, in, &off, out, 0, 5, 0);
    CHECK("copy_file_range_offset", r == 5 && off == 11, "r=%ld off=%ld", r, off);
    errno = 0;
    CHECK("copy_file_range_flags", syscall(326, in, 0, out, 0, 1, 1) == -1 && errno == EINVAL, "errno=%d",
          errno);
    lseek(in, 0, SEEK_SET);
    errno = 0;
    r = syscall(275, in, 0, out, 0, 5, 0);
    CHECKC("splice_file_to_file", r == 5);
    close(in);
    close(out);
}

static void check_misc(void)
{
    long head = 1, len = 0;
    errno = 0;
    CHECKC("get_robust_list", syscall(274, 0, &head, &len) == 0);
    long attr[7] = {0};
    errno = 0;
    CHECKC("sched_getattr", syscall(315, 0, attr, sizeof attr, 0) == 0);
    CHECK("sched_getattr_size", (attr[0] & 0xFFFFFFFF) == 56, "size=%ld", attr[0] & 0xFFFFFFFF);
    attr[0] = 56;
    errno = 0;
    CHECKC("sched_setattr_other", syscall(314, 0, attr, 0) == 0);
    int p[2];
    if (pipe(p) != 0) {
        FAIL("pipe", "errno=%d", errno);
        return;
    }
    int ep = epoll_create1(0);
    struct epoll_event ev = {EPOLLIN, {.fd = p[0]}};
    epoll_ctl(ep, EPOLL_CTL_ADD, p[0], &ev);
    struct epoll_event out[2];
    struct timespec zero = {0, 1000000};
    errno = 0;
    long r = syscall(441, ep, out, 2, &zero, 0, 0);
    CHECKC("epoll_pwait2_timeout", r == 0);
    (void)!write(p[1], "x", 1);
    errno = 0;
    r = syscall(441, ep, out, 2, &zero, 0, 0);
    CHECKC("epoll_pwait2_ready", r == 1);
    close(p[0]);
    close(p[1]);
    close(ep);
}

int main(void)
{
    alarm(60);
    check_messages();
    check_memory();
    check_xattr_caps();
    check_files();
    check_dirents();
    check_fd_calls();
    check_copy();
    check_misc();
    return 0;
}
