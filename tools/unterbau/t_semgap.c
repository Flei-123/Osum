#define TNAME "semgap"
#include "t.h"
#include <fcntl.h>
#include <poll.h>
#include <signal.h>
#include <stdlib.h>
#include <sys/file.h>
#include <sys/ioctl.h>
#include <sys/socket.h>
#include <sys/stat.h>
#include <sys/syscall.h>
#include <sys/time.h>
#include <sys/wait.h>
#include <time.h>

#define CHECK_SECONDS 12
#define BUF_MAX 65536
#define F_GETPIPE_SZ_CMD 1032
#define F_SETPIPE_SZ_CMD 1031
#define RECORD_BYTES 512
#define RECORDS_PER_WRITER 160
#define N_RENAMEAT2 316
#define RENAME_NOREPLACE_FLAG 1
#define RENAME_EXCHANGE_FLAG 2
#define CWD (-100L)
#define DIR_PATH "/tmp/semgap"

typedef int (*check_fn)(char *detail, size_t detail_size);

static void run_check(const char *name, check_fn fn)
{
    char detail[160] = "";
    int result[2];
    if (pipe(result) != 0) {
        FAIL(name, "pipe errno=%d", errno);
        return;
    }
    pid_t pid = fork();
    if (pid == 0) {
        alarm(CHECK_SECONDS);
        int rc = fn(detail, sizeof detail);
        (void)!write(result[1], detail, strlen(detail) + 1);
        _exit(rc);
    }
    close(result[1]);
    ssize_t n = read(result[0], detail, sizeof detail - 1);
    if (n < 0)
        n = 0;
    detail[n] = 0;
    close(result[0]);
    int status = 0;
    waitpid(pid, &status, 0);
    if (WIFEXITED(status) && WEXITSTATUS(status) == 0)
        PASS(name);
    else if (WIFEXITED(status))
        FAIL(name, "%s", detail);
    else
        FAIL(name, "child died, signal %d %s", WTERMSIG(status), detail);
}

#define BAD(...) do { snprintf(detail, detail_size, __VA_ARGS__); return 1; } while (0)

static long pipe_capacity(int fd)
{
    return fcntl(fd, F_GETPIPE_SZ_CMD);
}

static int set_nonblock(int fd)
{
    return fcntl(fd, F_SETFL, fcntl(fd, F_GETFL) | O_NONBLOCK);
}

static int pipe_nb_partial(char *detail, size_t detail_size)
{
    int p[2];
    static char big[200000];
    pipe(p);
    set_nonblock(p[1]);
    long cap = pipe_capacity(p[1]);
    ssize_t n = write(p[1], big, sizeof big);
    if (cap < 4096 || n != cap)
        BAD("first nonblocking write returned %zd cap=%ld errno=%d", n, cap, errno);
    errno = 0;
    n = write(p[1], big, 1);
    if (n != -1 || errno != EAGAIN)
        BAD("full pipe write n=%zd errno=%d", n, errno);
    return 0;
}

static int pipe_atomic_nonblock(char *detail, size_t detail_size)
{
    int p[2];
    static char buf[BUF_MAX];
    pipe(p);
    set_nonblock(p[1]);
    long cap = pipe_capacity(p[1]);
    if (write(p[1], buf, cap - 100) != cap - 100)
        BAD("prefill");
    errno = 0;
    ssize_t n = write(p[1], buf, 4096);
    int queued = 0;
    ioctl(p[0], FIONREAD, &queued);
    if (n != -1 || errno != EAGAIN)
        BAD("4096 into 100 free: n=%zd errno=%d queued=%d", n, errno, queued);
    if (queued != cap - 100)
        BAD("partial data queued=%d", queued);
    return 0;
}

static int pipe_atomic_blocking(char *detail, size_t detail_size)
{
    int p[2];
    static char buf[BUF_MAX];
    pipe(p);
    long cap = pipe_capacity(p[1]);
    if (write(p[1], buf, cap - 100) != cap - 100)
        BAD("prefill");
    pid_t pid = fork();
    if (pid == 0) {
        static char rec[4096];
        _exit(write(p[1], rec, sizeof rec) == (ssize_t)sizeof rec ? 0 : 1);
    }
    usleep(700000);
    int queued = 0;
    ioctl(p[0], FIONREAD, &queued);
    if (queued != cap - 100) {
        kill(pid, SIGKILL);
        BAD("writer placed bytes early: queued=%d", queued);
    }
    ssize_t n = read(p[0], buf, 4096);
    int status = 0;
    waitpid(pid, &status, 0);
    if (n != 4096 || !WIFEXITED(status) || WEXITSTATUS(status) != 0)
        BAD("n=%zd status=0x%x", n, status);
    return 0;
}

static int pipe_records_interleave(char *detail, size_t detail_size)
{
    int p[2];
    pipe(p);
    char tags[2] = {'A', 'B'};
    int i;
    for (i = 0; i < 2; i++) {
        if (fork() == 0) {
            char rec[RECORD_BYTES];
            memset(rec, tags[i], sizeof rec);
            int k;
            for (k = 0; k < RECORDS_PER_WRITER; k++)
                if (write(p[1], rec, sizeof rec) != sizeof rec)
                    _exit(1);
            _exit(0);
        }
    }
    close(p[1]);
    usleep(500000);
    char got[RECORD_BYTES];
    long total = 0, torn = 0;
    ssize_t n;
    size_t have = 0;
    while ((n = read(p[0], got + have, sizeof got - have)) > 0) {
        have += n;
        total += n;
        if (have == sizeof got) {
            size_t j;
            for (j = 1; j < sizeof got; j++)
                if (got[j] != got[0]) {
                    torn++;
                    break;
                }
            have = 0;
        }
        if (total % 7 == 0)
            usleep(1000);
    }
    while (wait(NULL) > 0)
        ;
    if (torn || total != 2L * RECORDS_PER_WRITER * RECORD_BYTES)
        BAD("torn records=%ld total=%ld", torn, total);
    return 0;
}

static int pipe_sigpipe(char *detail, size_t detail_size)
{
    int p[2];
    pipe(p);
    close(p[0]);
    signal(SIGPIPE, SIG_IGN);
    errno = 0;
    ssize_t n = write(p[1], "x", 1);
    if (n != -1 || errno != EPIPE)
        BAD("ignored SIGPIPE: n=%zd errno=%d", n, errno);
    pid_t pid = fork();
    if (pid == 0) {
        signal(SIGPIPE, SIG_DFL);
        (void)!write(p[1], "x", 1);
        _exit(0);
    }
    int status = 0;
    waitpid(pid, &status, 0);
    if (!WIFSIGNALED(status) || WTERMSIG(status) != SIGPIPE)
        BAD("default action: status=0x%x", status);
    return 0;
}

static int pipe_size_fcntl(char *detail, size_t detail_size)
{
    int p[2];
    pipe(p);
    int sz = fcntl(p[1], F_GETPIPE_SZ_CMD);
    if (sz < 4096)
        BAD("F_GETPIPE_SZ=%d errno=%d", sz, errno);
    int r = fcntl(p[1], F_SETPIPE_SZ_CMD, 4096);
    if (r < 4096)
        BAD("F_SETPIPE_SZ=%d errno=%d", r, errno);
    return 0;
}

static int pipe_poll_flags(char *detail, size_t detail_size)
{
    int p[2];
    pipe(p);
    struct pollfd w = { p[1], POLLOUT, 0 };
    struct pollfd r = { p[0], POLLIN, 0 };
    poll(&w, 1, 0);
    poll(&r, 1, 0);
    if (!(w.revents & POLLOUT) || (r.revents & POLLIN))
        BAD("initial w=0x%x r=0x%x", w.revents, r.revents);
    close(p[0]);
    w.revents = 0;
    poll(&w, 1, 0);
    if (!(w.revents & POLLERR))
        BAD("reader closed, write end revents=0x%x", w.revents);
    int q[2];
    pipe(q);
    close(q[1]);
    r.fd = q[0];
    r.revents = 0;
    poll(&r, 1, 0);
    if (!(r.revents & POLLHUP))
        BAD("writer closed, read end revents=0x%x", r.revents);
    return 0;
}

static void noop_handler(int sig)
{
    (void)sig;
}

static void arm_signal(int flags, int usec)
{
    struct sigaction sa;
    memset(&sa, 0, sizeof sa);
    sa.sa_handler = noop_handler;
    sa.sa_flags = flags;
    sigaction(SIGALRM, &sa, 0);
    struct itimerval it = { { 0, 0 }, { 0, usec } };
    setitimer(ITIMER_REAL, &it, 0);
}

static int restart_write_full_pipe(char *detail, size_t detail_size)
{
    int p[2];
    static char buf[BUF_MAX];
    pipe(p);
    long cap = pipe_capacity(p[1]);
    if (write(p[1], buf, cap) != cap)
        BAD("prefill");
    pid_t pid = fork();
    if (pid == 0) {
        usleep(900000);
        (void)!read(p[0], buf, 4096);
        _exit(0);
    }
    arm_signal(SA_RESTART, 300000);
    errno = 0;
    ssize_t n = write(p[1], buf, 1024);
    waitpid(pid, 0, 0);
    if (n != 1024)
        BAD("SA_RESTART write n=%zd errno=%d", n, errno);
    return 0;
}

static int eintr_write_full_pipe(char *detail, size_t detail_size)
{
    int p[2];
    static char buf[BUF_MAX];
    pipe(p);
    long cap = pipe_capacity(p[1]);
    if (write(p[1], buf, cap) != cap)
        BAD("prefill");
    arm_signal(0, 300000);
    errno = 0;
    ssize_t n = write(p[1], buf, 1024);
    if (n != -1 || errno != EINTR)
        BAD("no SA_RESTART write n=%zd errno=%d", n, errno);
    return 0;
}

static int restart_accept(char *detail, size_t detail_size)
{
    int s = socket(AF_UNIX, SOCK_STREAM, 0);
    struct sockaddr_un_min { unsigned short family; char path[108]; } a;
    memset(&a, 0, sizeof a);
    a.family = AF_UNIX;
    strcpy(a.path, "/tmp/semgap-acc");
    unlink(a.path);
    if (bind(s, (struct sockaddr *)&a, sizeof a) != 0 || listen(s, 4) != 0)
        BAD("bind/listen errno=%d", errno);
    pid_t pid = fork();
    if (pid == 0) {
        usleep(900000);
        int c = socket(AF_UNIX, SOCK_STREAM, 0);
        connect(c, (struct sockaddr *)&a, sizeof a);
        _exit(0);
    }
    arm_signal(SA_RESTART, 300000);
    errno = 0;
    int c = accept(s, 0, 0);
    waitpid(pid, 0, 0);
    unlink(a.path);
    if (c < 0)
        BAD("SA_RESTART accept errno=%d", errno);
    return 0;
}

static int restart_never_nanosleep(char *detail, size_t detail_size)
{
    struct timespec ts = { 3, 0 };
    arm_signal(SA_RESTART, 300000);
    errno = 0;
    int r = nanosleep(&ts, 0);
    if (r != -1 || errno != EINTR)
        BAD("nanosleep r=%d errno=%d", r, errno);
    return 0;
}

static int restart_never_poll(char *detail, size_t detail_size)
{
    int p[2];
    pipe(p);
    struct pollfd r = { p[0], POLLIN, 0 };
    arm_signal(SA_RESTART, 300000);
    errno = 0;
    int n = poll(&r, 1, 3000);
    if (n != -1 || errno != EINTR)
        BAD("poll n=%d errno=%d", n, errno);
    return 0;
}

static int restart_socket_read(char *detail, size_t detail_size)
{
    int sv[2];
    socketpair(AF_UNIX, SOCK_STREAM, 0, sv);
    pid_t pid = fork();
    if (pid == 0) {
        usleep(900000);
        (void)!write(sv[1], "z", 1);
        _exit(0);
    }
    arm_signal(SA_RESTART, 300000);
    char c = 0;
    errno = 0;
    ssize_t n = read(sv[0], &c, 1);
    waitpid(pid, 0, 0);
    if (n != 1 || c != 'z')
        BAD("SA_RESTART socket read n=%zd errno=%d", n, errno);
    return 0;
}

static void mk(const char *path, const char *text)
{
    int fd = open(path, O_WRONLY | O_CREAT | O_TRUNC, 0644);
    (void)!write(fd, text, strlen(text));
    close(fd);
}

static void slurp(const char *path, char *out, size_t size)
{
    int fd = open(path, O_RDONLY);
    ssize_t n = fd < 0 ? -1 : read(fd, out, size - 1);
    out[n < 0 ? 0 : n] = 0;
    if (fd >= 0)
        close(fd);
}

static const char *const dir_entries[] = { "target", "new", "link", "moved", "file", "a", "b", "c", "dangling", "lockfile", "full/x", "full", "d1", "d2", 0 };

static void remove_dir(void)
{
    const char *const *e;
    char path[96];
    for (e = dir_entries; *e; e++) {
        snprintf(path, sizeof path, DIR_PATH "/%s", *e);
        if (unlink(path) != 0)
            rmdir(path);
    }
    rmdir(DIR_PATH);
}

static void fresh_dir(void)
{
    remove_dir();
    mkdir(DIR_PATH, 0755);
}

static int rename_over_symlink(char *detail, size_t detail_size)
{
    char got[32];
    fresh_dir();
    mk(DIR_PATH "/target", "target");
    mk(DIR_PATH "/new", "new");
    symlink(DIR_PATH "/target", DIR_PATH "/link");
    if (rename(DIR_PATH "/new", DIR_PATH "/link") != 0)
        BAD("rename errno=%d", errno);
    struct stat st;
    if (lstat(DIR_PATH "/link", &st) != 0 || S_ISLNK(st.st_mode))
        BAD("link is still a symlink");
    slurp(DIR_PATH "/target", got, sizeof got);
    if (strcmp(got, "target") != 0)
        BAD("target overwritten with '%s'", got);
    slurp(DIR_PATH "/link", got, sizeof got);
    if (strcmp(got, "new") != 0)
        BAD("link content '%s'", got);
    return 0;
}

static int rename_symlink_itself(char *detail, size_t detail_size)
{
    char got[160];
    fresh_dir();
    mk(DIR_PATH "/target", "target");
    symlink(DIR_PATH "/target", DIR_PATH "/link");
    if (rename(DIR_PATH "/link", DIR_PATH "/moved") != 0)
        BAD("rename errno=%d", errno);
    struct stat st;
    if (lstat(DIR_PATH "/moved", &st) != 0 || !S_ISLNK(st.st_mode))
        BAD("moved is not a symlink");
    ssize_t n = readlink(DIR_PATH "/moved", got, sizeof got - 1);
    if (n != (ssize_t)strlen(DIR_PATH "/target"))
        BAD("readlink n=%zd", n);
    if (lstat(DIR_PATH "/link", &st) == 0)
        BAD("old name still there");
    return 0;
}

static int rename_dir_cases(char *detail, size_t detail_size)
{
    fresh_dir();
    mkdir(DIR_PATH "/d1", 0755);
    mkdir(DIR_PATH "/d2", 0755);
    mkdir(DIR_PATH "/full", 0755);
    mk(DIR_PATH "/full/x", "x");
    mk(DIR_PATH "/file", "f");
    errno = 0;
    if (rename(DIR_PATH "/d1", DIR_PATH "/full") != -1 || (errno != ENOTEMPTY && errno != EEXIST))
        BAD("dir over non-empty dir errno=%d", errno);
    errno = 0;
    if (rename(DIR_PATH "/d1", DIR_PATH "/file") != -1 || errno != ENOTDIR)
        BAD("dir over file errno=%d", errno);
    errno = 0;
    if (rename(DIR_PATH "/file", DIR_PATH "/d2") != -1 || errno != EISDIR)
        BAD("file over dir errno=%d", errno);
    errno = 0;
    if (rename(DIR_PATH "/full", DIR_PATH "/full/sub") != -1 || errno != EINVAL)
        BAD("dir into itself errno=%d", errno);
    if (rename(DIR_PATH "/d1", DIR_PATH "/d2") != 0)
        BAD("dir over empty dir errno=%d", errno);
    struct stat st;
    if (stat(DIR_PATH "/d1", &st) == 0)
        BAD("source dir still there");
    return 0;
}

static int rename_noreplace(char *detail, size_t detail_size)
{
    fresh_dir();
    mk(DIR_PATH "/a", "a");
    mk(DIR_PATH "/b", "b");
    errno = 0;
    long r = syscall(N_RENAMEAT2, CWD, DIR_PATH "/a", CWD, DIR_PATH "/b", (long)RENAME_NOREPLACE_FLAG);
    if (r != -1 || errno != EEXIST)
        BAD("noreplace over existing r=%ld errno=%d", r, errno);
    char got[8];
    slurp(DIR_PATH "/b", got, sizeof got);
    if (strcmp(got, "b") != 0)
        BAD("target was changed");
    r = syscall(N_RENAMEAT2, CWD, DIR_PATH "/a", CWD, DIR_PATH "/c", (long)RENAME_NOREPLACE_FLAG);
    if (r != 0)
        BAD("noreplace to free name r=%ld errno=%d", r, errno);
    struct stat st;
    if (stat(DIR_PATH "/a", &st) == 0 || stat(DIR_PATH "/c", &st) != 0)
        BAD("source/target state wrong");
    return 0;
}

static int rename_exchange(char *detail, size_t detail_size)
{
    fresh_dir();
    mk(DIR_PATH "/a", "aaa");
    mk(DIR_PATH "/b", "bbb");
    long r = syscall(N_RENAMEAT2, CWD, DIR_PATH "/a", CWD, DIR_PATH "/b", (long)RENAME_EXCHANGE_FLAG);
    if (r != 0)
        BAD("exchange r=%ld errno=%d", r, errno);
    char a[8], b[8];
    slurp(DIR_PATH "/a", a, sizeof a);
    slurp(DIR_PATH "/b", b, sizeof b);
    if (strcmp(a, "bbb") != 0 || strcmp(b, "aaa") != 0)
        BAD("after exchange a='%s' b='%s'", a, b);
    errno = 0;
    r = syscall(N_RENAMEAT2, CWD, DIR_PATH "/a", CWD, DIR_PATH "/none", (long)RENAME_EXCHANGE_FLAG);
    if (r != -1 || errno != ENOENT)
        BAD("exchange with missing target r=%ld errno=%d", r, errno);
    return 0;
}

static int rename_bad_flags(char *detail, size_t detail_size)
{
    fresh_dir();
    mk(DIR_PATH "/a", "a");
    errno = 0;
    long r = syscall(N_RENAMEAT2, CWD, DIR_PATH "/a", CWD, DIR_PATH "/b", 3L);
    if (r != -1 || errno != EINVAL)
        BAD("noreplace+exchange r=%ld errno=%d", r, errno);
    errno = 0;
    r = syscall(N_RENAMEAT2, CWD, DIR_PATH "/a", CWD, DIR_PATH "/b", 0x80L);
    if (r != -1 || errno != EINVAL)
        BAD("unknown flag r=%ld errno=%d", r, errno);
    return 0;
}

static int excl_over_dangling_symlink(char *detail, size_t detail_size)
{
    fresh_dir();
    symlink(DIR_PATH "/nowhere", DIR_PATH "/dangling");
    errno = 0;
    int fd = open(DIR_PATH "/dangling", O_CREAT | O_EXCL | O_WRONLY, 0644);
    if (fd >= 0 || errno != EEXIST)
        BAD("fd=%d errno=%d", fd, errno);
    return 0;
}

static int seqpacket_shutdown_wr(char *detail, size_t detail_size)
{
    int sv[2];
    if (socketpair(AF_UNIX, SOCK_SEQPACKET, 0, sv) != 0)
        BAD("socketpair errno=%d", errno);
    if (shutdown(sv[0], SHUT_WR) != 0)
        BAD("shutdown errno=%d", errno);
    char c;
    errno = 0;
    ssize_t n = recv(sv[1], &c, 1, 0);
    if (n != 0)
        BAD("peer recv after SHUT_WR n=%zd errno=%d", n, errno);
    errno = 0;
    n = send(sv[0], "x", 1, MSG_NOSIGNAL);
    if (n != -1 || errno != EPIPE)
        BAD("send after SHUT_WR n=%zd errno=%d", n, errno);
    if (send(sv[1], "y", 1, 0) != 1 || recv(sv[0], &c, 1, 0) != 1 || c != 'y')
        BAD("reverse direction broken");
    return 0;
}

static int seqpacket_shutdown_rd(char *detail, size_t detail_size)
{
    int sv[2];
    socketpair(AF_UNIX, SOCK_SEQPACKET, 0, sv);
    if (shutdown(sv[0], SHUT_RD) != 0)
        BAD("shutdown errno=%d", errno);
    char c;
    errno = 0;
    ssize_t n = recv(sv[0], &c, 1, 0);
    if (n != 0)
        BAD("recv after SHUT_RD n=%zd errno=%d", n, errno);
    return 0;
}

static int dgram_shutdown(char *detail, size_t detail_size)
{
    int sv[2];
    if (socketpair(AF_UNIX, SOCK_DGRAM, 0, sv) != 0)
        BAD("socketpair errno=%d", errno);
    if (shutdown(sv[0], SHUT_RD) != 0)
        BAD("SHUT_RD errno=%d", errno);
    char c;
    errno = 0;
    ssize_t n = recv(sv[0], &c, 1, MSG_DONTWAIT);
    if (n != 0)
        BAD("dgram recv after SHUT_RD n=%zd errno=%d", n, errno);
    if (shutdown(sv[1], SHUT_WR) != 0)
        BAD("SHUT_WR errno=%d", errno);
    errno = 0;
    n = send(sv[1], "x", 1, MSG_NOSIGNAL);
    if (n != -1 || errno != EPIPE)
        BAD("dgram send after SHUT_WR n=%zd errno=%d", n, errno);
    return 0;
}

static int stream_shutdown_pollrdhup(char *detail, size_t detail_size)
{
    int sv[2];
    socketpair(AF_UNIX, SOCK_STREAM, 0, sv);
    shutdown(sv[0], SHUT_WR);
    struct pollfd pf = { sv[1], POLLIN | POLLRDHUP, 0 };
    poll(&pf, 1, 500);
    if (!(pf.revents & POLLRDHUP) || !(pf.revents & POLLIN))
        BAD("revents=0x%x", pf.revents);
    return 0;
}

static int shutdown_unconnected(char *detail, size_t detail_size)
{
    int s = socket(AF_UNIX, SOCK_STREAM, 0);
    errno = 0;
    int r = shutdown(s, SHUT_RDWR);
    if (r != -1 || errno != ENOTCONN)
        BAD("r=%d errno=%d", r, errno);
    errno = 0;
    r = shutdown(s, 7);
    if (r != -1 || errno != EINVAL)
        BAD("bad how r=%d errno=%d", r, errno);
    return 0;
}

static int sock_rcvtimeo(char *detail, size_t detail_size)
{
    int sv[2];
    socketpair(AF_UNIX, SOCK_STREAM, 0, sv);
    struct timeval tv = { 1, 0 };
    if (setsockopt(sv[0], SOL_SOCKET, SO_RCVTIMEO, &tv, sizeof tv) != 0)
        BAD("setsockopt errno=%d", errno);
    char c;
    errno = 0;
    ssize_t n = recv(sv[0], &c, 1, 0);
    if (n != -1 || (errno != EAGAIN && errno != EWOULDBLOCK))
        BAD("recv n=%zd errno=%d", n, errno);
    return 0;
}

static int sock_sndtimeo(char *detail, size_t detail_size)
{
    int sv[2];
    static char block[8192];
    socketpair(AF_UNIX, SOCK_STREAM, 0, sv);
    struct timeval tv = { 1, 0 };
    if (setsockopt(sv[0], SOL_SOCKET, SO_SNDTIMEO, &tv, sizeof tv) != 0)
        BAD("setsockopt errno=%d", errno);
    long total = 0;
    errno = 0;
    for (;;) {
        ssize_t n = send(sv[0], block, sizeof block, 0);
        if (n < 0)
            break;
        total += n;
        if (total > (64L << 20))
            BAD("sent 64 MiB without blocking");
    }
    if (errno != EAGAIN && errno != EWOULDBLOCK)
        BAD("errno=%d after %ld bytes", errno, total);
    return 0;
}

static int sock_blocking_long_wait(char *detail, size_t detail_size)
{
    int sv[2];
    socketpair(AF_UNIX, SOCK_STREAM, 0, sv);
    pid_t pid = fork();
    if (pid == 0) {
        sleep(10);
        (void)!write(sv[1], "k", 1);
        _exit(0);
    }
    alarm(0);
    alarm(60);
    char c = 0;
    errno = 0;
    ssize_t n = recv(sv[0], &c, 1, 0);
    waitpid(pid, 0, 0);
    if (n != 1 || c != 'k')
        BAD("n=%zd errno=%d", n, errno);
    return 0;
}

static int sockopt_basics(char *detail, size_t detail_size)
{
    int sv[2];
    socketpair(AF_UNIX, SOCK_SEQPACKET, 0, sv);
    int v = 0;
    socklen_t l = sizeof v;
    if (getsockopt(sv[0], SOL_SOCKET, SO_TYPE, &v, &l) != 0 || v != SOCK_SEQPACKET)
        BAD("SO_TYPE v=%d errno=%d", v, errno);
    v = -1;
    l = sizeof v;
    if (getsockopt(sv[0], SOL_SOCKET, SO_ERROR, &v, &l) != 0 || v != 0)
        BAD("SO_ERROR v=%d errno=%d", v, errno);
    int want = 262144;
    if (setsockopt(sv[0], SOL_SOCKET, SO_SNDBUF, &want, sizeof want) != 0)
        BAD("SO_SNDBUF set errno=%d", errno);
    l = sizeof v;
    if (getsockopt(sv[0], SOL_SOCKET, SO_SNDBUF, &v, &l) != 0 || v < 4096)
        BAD("SO_SNDBUF get v=%d errno=%d", v, errno);
    return 0;
}

static void settle(void)
{
    usleep(400000);
}

static int death_kill_closes_pipe(char *detail, size_t detail_size)
{
    int p[2];
    pipe(p);
    pid_t pid = fork();
    if (pid == 0) {
        close(p[0]);
        pause();
        _exit(0);
    }
    close(p[1]);
    usleep(200000);
    kill(pid, SIGKILL);
    settle();
    struct pollfd pf = { p[0], POLLIN, 0 };
    int n = poll(&pf, 1, 0);
    waitpid(pid, 0, 0);
    if (n != 1 || !(pf.revents & POLLHUP))
        BAD("before reap: poll n=%d revents=0x%x", n, pf.revents);
    return 0;
}

static int death_zombie_closes_pipe(char *detail, size_t detail_size)
{
    int p[2];
    pipe(p);
    pid_t pid = fork();
    if (pid == 0) {
        close(p[0]);
        _exit(0);
    }
    close(p[1]);
    settle();
    char c;
    ssize_t n = read(p[0], &c, 1);
    waitpid(pid, 0, 0);
    if (n != 0)
        BAD("zombie writer still holds the pipe: n=%zd", n);
    return 0;
}

static int death_fault_closes_socket(char *detail, size_t detail_size)
{
    int sv[2];
    socketpair(AF_UNIX, SOCK_STREAM, 0, sv);
    pid_t pid = fork();
    if (pid == 0) {
        close(sv[0]);
        volatile int *bad = (volatile int *)8;
        *bad = 1;
        _exit(0);
    }
    close(sv[1]);
    settle();
    struct pollfd pf = { sv[0], POLLIN, 0 };
    int n = poll(&pf, 1, 0);
    char c;
    ssize_t r = n == 1 ? recv(sv[0], &c, 1, MSG_DONTWAIT) : -2;
    waitpid(pid, 0, 0);
    if (r != 0)
        BAD("before reap: poll n=%d recv=%zd", n, r);
    return 0;
}

static int death_releases_flock(char *detail, size_t detail_size)
{
    fresh_dir();
    mk(DIR_PATH "/lockfile", "x");
    int p[2];
    pipe(p);
    pid_t pid = fork();
    if (pid == 0) {
        int fd = open(DIR_PATH "/lockfile", O_RDWR);
        flock(fd, LOCK_EX);
        (void)!write(p[1], "1", 1);
        pause();
        _exit(0);
    }
    char c;
    (void)!read(p[0], &c, 1);
    kill(pid, SIGKILL);
    settle();
    int fd = open(DIR_PATH "/lockfile", O_RDWR);
    errno = 0;
    int r = flock(fd, LOCK_EX | LOCK_NB);
    waitpid(pid, 0, 0);
    if (r != 0)
        BAD("lock still held before reap: errno=%d", errno);
    return 0;
}

int main(void)
{
    alarm(600);
    run_check("pipe_nb_partial_fill", pipe_nb_partial);
    run_check("pipe_atomic_nonblock", pipe_atomic_nonblock);
    run_check("pipe_atomic_blocking", pipe_atomic_blocking);
    run_check("pipe_records_not_interleaved", pipe_records_interleave);
    run_check("pipe_sigpipe_epipe", pipe_sigpipe);
    run_check("pipe_size_fcntl", pipe_size_fcntl);
    run_check("pipe_poll_flags", pipe_poll_flags);
    run_check("restart_write_full_pipe", restart_write_full_pipe);
    run_check("eintr_write_full_pipe", eintr_write_full_pipe);
    run_check("restart_accept", restart_accept);
    run_check("restart_socket_read", restart_socket_read);
    run_check("restart_never_nanosleep", restart_never_nanosleep);
    run_check("restart_never_poll", restart_never_poll);
    run_check("rename_over_symlink", rename_over_symlink);
    run_check("rename_symlink_itself", rename_symlink_itself);
    run_check("rename_dir_cases", rename_dir_cases);
    run_check("rename_noreplace", rename_noreplace);
    run_check("rename_exchange", rename_exchange);
    run_check("rename_bad_flags", rename_bad_flags);
    run_check("excl_over_dangling_symlink", excl_over_dangling_symlink);
    run_check("seqpacket_shutdown_wr", seqpacket_shutdown_wr);
    run_check("seqpacket_shutdown_rd", seqpacket_shutdown_rd);
    run_check("dgram_shutdown", dgram_shutdown);
    run_check("stream_shutdown_pollrdhup", stream_shutdown_pollrdhup);
    run_check("shutdown_unconnected", shutdown_unconnected);
    run_check("sock_rcvtimeo", sock_rcvtimeo);
    run_check("sock_sndtimeo", sock_sndtimeo);
    run_check("sock_blocking_long_wait", sock_blocking_long_wait);
    run_check("sockopt_basics", sockopt_basics);
    run_check("death_kill_closes_pipe", death_kill_closes_pipe);
    run_check("death_zombie_closes_pipe", death_zombie_closes_pipe);
    run_check("death_fault_closes_socket", death_fault_closes_socket);
    run_check("death_releases_flock", death_releases_flock);
    remove_dir();
    return 0;
}
