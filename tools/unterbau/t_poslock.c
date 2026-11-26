/* Record locks: POSIX locks belong to the PROCESS: a thread that exits must not drop them (Firefox profile lock, SQLite),
 * a child that exits must not touch the parent's locks, and close() of ANY descriptor of the file releases the process's locks on it. */
#define TNAME "poslock"
#include "t.h"
#include <fcntl.h>
#include <pthread.h>
#include <stdlib.h>
#include <signal.h>
#include <sys/file.h>
#include <sys/wait.h>
#include <time.h>

#define PATH "/tmp/poslock.dat"
#define OTHER_PATH "/tmp/poslock.other"
#define SETTLE_US 150000
#define BLOCK_MIN_MS 80
#define BLOCK_MAX_MS 4000
#define EXEC_POLL_MS 2500
#define THREAD_ROUNDS 20

static int lock_whole(int fd, short type)
{
    struct flock fl = {.l_type = type, .l_whence = SEEK_SET, .l_start = 0, .l_len = 0};
    return fcntl(fd, F_SETLK, &fl);
}

static int foreign_sees(short want)
{
    pid_t child = fork();
    if (child == 0) {
        int fd = open(PATH, O_RDWR);
        struct flock fl = {.l_type = F_WRLCK, .l_whence = SEEK_SET, .l_start = 0, .l_len = 0};
        int r = fcntl(fd, F_GETLK, &fl);
        _exit(r == 0 && fl.l_type == want ? 0 : 1);
    }
    int status = 0;
    waitpid(child, &status, 0);
    return WIFEXITED(status) && WEXITSTATUS(status) == 0;
}

static void *noop(void *arg)
{
    return arg;
}

static void churn_threads(int rounds)
{
    for (int i = 0; i < rounds; i++) {
        pthread_t th;
        pthread_create(&th, 0, noop, 0);
        pthread_join(th, 0);
    }
}


static long now_ms(void)
{
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return ts.tv_sec * 1000 + ts.tv_nsec / 1000000;
}

static int range_lock(int fd, int cmd, short type, off_t start, off_t len)
{
    struct flock fl = {.l_type = type, .l_whence = SEEK_SET, .l_start = start, .l_len = len};
    return fcntl(fd, cmd, &fl);
}

static int probe(short type, off_t start, off_t len, struct flock *out)
{
    int pipefd[2];
    if (pipe(pipefd) != 0)
        return -1;
    pid_t child = fork();
    if (child == 0) {
        int fd = open(PATH, O_RDWR);
        struct flock fl = {.l_type = type, .l_whence = SEEK_SET, .l_start = start, .l_len = len};
        int r = fcntl(fd, F_GETLK, &fl);
        if (r != 0)
            fl.l_type = 99;
        (void)!write(pipefd[1], &fl, sizeof fl);
        _exit(0);
    }
    close(pipefd[1]);
    memset(out, 0, sizeof *out);
    out->l_type = 99;
    (void)!read(pipefd[0], out, sizeof *out);
    close(pipefd[0]);
    waitpid(child, 0, 0);
    return 0;
}

static int probe_type(short type, off_t start, off_t len)
{
    struct flock fl;
    probe(type, start, len, &fl);
    return fl.l_type;
}

static void wait_ok(const char *name, pid_t child)
{
    int status = 0;
    waitpid(child, &status, 0);
    CHECK(name, WIFEXITED(status) && WEXITSTATUS(status) == 0, "child status=0x%x", status);
}

static int blocked_child(int (*action)(void *), void *arg, int *ready_fd)
{
    int pipefd[2];
    if (pipe(pipefd) != 0)
        return -1;
    pid_t child = fork();
    if (child == 0) {
        close(pipefd[0]);
        (void)!write(pipefd[1], "r", 1);
        close(pipefd[1]);
        _exit(action(arg));
    }
    close(pipefd[1]);
    *ready_fd = pipefd[0];
    return child;
}

static int wait_ready(int fd)
{
    char c;
    return read(fd, &c, 1) == 1;
}

struct wait_args {
    int fd;
    int cmd;
    short type;
};

static int wait_for_lock_action(void *arg)
{
    struct wait_args *a = arg;
    long t0 = now_ms();
    int r = a->cmd == -1 ? flock(a->fd, LOCK_EX) : range_lock(a->fd, a->cmd, a->type, 0, 0);
    long dt = now_ms() - t0;
    return r == 0 && dt >= BLOCK_MIN_MS && dt < BLOCK_MAX_MS ? 0 : 1;
}

static void test_blocking_wait(void)
{
    int fd = open(PATH, O_RDWR | O_CREAT | O_TRUNC, 0644);
    lock_whole(fd, F_WRLCK);
    int cfd = open(PATH, O_RDWR);
    struct wait_args a = {.fd = cfd, .cmd = F_SETLKW, .type = F_WRLCK};
    int ready;
    pid_t child = blocked_child(wait_for_lock_action, &a, &ready);
    wait_ready(ready);
    close(ready);
    usleep(SETTLE_US);
    CHECK("setlkw_waits_for_unlock", waitpid(child, 0, WNOHANG) == 0, "SETLKW returned while the lock was held");
    range_lock(fd, F_SETLK, F_UNLCK, 0, 0);
    wait_ok("setlkw_woken_by_unlock", child);
    close(cfd);
    close(fd);
}

static void test_wait_woken_by_close(void)
{
    int fd = open(PATH, O_RDWR | O_CREAT | O_TRUNC, 0644);
    lock_whole(fd, F_WRLCK);
    int cfd = open(PATH, O_RDWR);
    struct wait_args a = {.fd = cfd, .cmd = F_SETLKW, .type = F_WRLCK};
    int ready;
    pid_t child = blocked_child(wait_for_lock_action, &a, &ready);
    wait_ready(ready);
    close(ready);
    usleep(SETTLE_US);
    close(fd);
    wait_ok("setlkw_woken_by_close", child);
    close(cfd);
}

static void noop_handler(int sig)
{
    (void)sig;
}

static int interrupted_action(void *arg)
{
    struct wait_args *a = arg;
    struct sigaction sa;
    memset(&sa, 0, sizeof sa);
    sa.sa_handler = noop_handler;
    sigaction(SIGUSR1, &sa, 0);
    int r = range_lock(a->fd, F_SETLKW, a->type, 0, 0);
    return r == -1 && errno == EINTR ? 0 : 1;
}

static void test_wait_interrupted(void)
{
    int fd = open(PATH, O_RDWR | O_CREAT | O_TRUNC, 0644);
    lock_whole(fd, F_WRLCK);
    int cfd = open(PATH, O_RDWR);
    struct wait_args a = {.fd = cfd, .cmd = F_SETLKW, .type = F_WRLCK};
    int ready;
    pid_t child = blocked_child(interrupted_action, &a, &ready);
    wait_ready(ready);
    close(ready);
    usleep(SETTLE_US * 2);
    kill(child, SIGUSR1);
    wait_ok("setlkw_interrupted_by_signal", child);
    close(cfd);
    close(fd);
}

static int deadlock_a(int fd, int to_b, int from_b)
{
    char c = 'x';
    range_lock(fd, F_SETLK, F_WRLCK, 0, 1);
    (void)!write(to_b, &c, 1);
    (void)!read(from_b, &c, 1);
    int r = range_lock(fd, F_SETLKW, F_WRLCK, 1, 1);
    return r == 0 ? 0 : 1;
}

static int deadlock_b(int fd, int to_a, int from_a)
{
    char c = 'x';
    range_lock(fd, F_SETLK, F_WRLCK, 1, 1);
    (void)!read(from_a, &c, 1);
    (void)!write(to_a, &c, 1);
    usleep(SETTLE_US * 3);
    int r = range_lock(fd, F_SETLKW, F_WRLCK, 0, 1);
    return r == -1 && errno == EDEADLK ? 0 : 1;
}

static void test_deadlock(void)
{
    int fd = open(PATH, O_RDWR | O_CREAT | O_TRUNC, 0644);
    int ab[2], ba[2];
    pipe(ab);
    pipe(ba);
    pid_t a = fork();
    if (a == 0) {
        int afd = open(PATH, O_RDWR);
        _exit(deadlock_a(afd, ab[1], ba[0]));
    }
    pid_t b = fork();
    if (b == 0) {
        int bfd = open(PATH, O_RDWR);
        _exit(deadlock_b(bfd, ba[1], ab[0]));
    }
    close(fd);
    int status_b = 0;
    waitpid(b, &status_b, 0);
    CHECK("deadlock_detected_edeadlk", WIFEXITED(status_b) && WEXITSTATUS(status_b) == 0, "status=0x%x", status_b);
    wait_ok("deadlock_other_side_proceeds", a);
    close(ab[0]); close(ab[1]); close(ba[0]); close(ba[1]);
}

static void test_ranges(void)
{
    int fd = open(PATH, O_RDWR | O_CREAT | O_TRUNC, 0644);
    range_lock(fd, F_SETLK, F_WRLCK, 0, 100);
    range_lock(fd, F_SETLK, F_UNLCK, 40, 20);
    CHECK("split_keeps_left", probe_type(F_WRLCK, 10, 5) == F_WRLCK, "type=%d", probe_type(F_WRLCK, 10, 5));
    CHECK("split_hole_is_free", probe_type(F_WRLCK, 45, 5) == F_UNLCK, "type=%d", probe_type(F_WRLCK, 45, 5));
    CHECK("split_keeps_right", probe_type(F_WRLCK, 70, 5) == F_WRLCK, "type=%d", probe_type(F_WRLCK, 70, 5));
    CHECK("split_edge_left", probe_type(F_WRLCK, 39, 1) == F_WRLCK && probe_type(F_WRLCK, 40, 1) == F_UNLCK, "edge");
    CHECK("split_edge_right", probe_type(F_WRLCK, 59, 1) == F_UNLCK && probe_type(F_WRLCK, 60, 1) == F_WRLCK, "edge");
    range_lock(fd, F_SETLK, F_UNLCK, 0, 0);
    range_lock(fd, F_SETLK, F_WRLCK, 0, 10);
    range_lock(fd, F_SETLK, F_WRLCK, 10, 10);
    struct flock fl;
    probe(F_WRLCK, 5, 1, &fl);
    CHECK("adjacent_locks_merge", fl.l_type == F_WRLCK && fl.l_start == 0 && fl.l_len == 20, "type=%d start=%ld len=%ld", fl.l_type, (long)fl.l_start, (long)fl.l_len);
    range_lock(fd, F_SETLK, F_UNLCK, 0, 0);
    range_lock(fd, F_SETLK, F_WRLCK, 0, 100);
    range_lock(fd, F_SETLK, F_RDLCK, 20, 10);
    CHECK("downgrade_middle_reads", probe_type(F_RDLCK, 25, 1) == F_UNLCK && probe_type(F_WRLCK, 25, 1) == F_RDLCK, "inner");
    CHECK("downgrade_keeps_outer_write", probe_type(F_RDLCK, 5, 1) == F_WRLCK && probe_type(F_RDLCK, 50, 1) == F_WRLCK, "outer");
    range_lock(fd, F_SETLK, F_UNLCK, 0, 0);
    range_lock(fd, F_SETLK, F_WRLCK, 10, 10);
    range_lock(fd, F_SETLK, F_WRLCK, 30, 10);
    range_lock(fd, F_SETLK, F_WRLCK, 15, 20);
    probe(F_WRLCK, 12, 1, &fl);
    CHECK("bridging_lock_merges_three", fl.l_type == F_WRLCK && fl.l_start == 10 && fl.l_len == 30, "start=%ld len=%ld", (long)fl.l_start, (long)fl.l_len);
    range_lock(fd, F_SETLK, F_UNLCK, 0, 0);
    struct flock end = {.l_type = F_WRLCK, .l_whence = SEEK_END, .l_start = -10, .l_len = 5};
    ftruncate(fd, 100);
    CHECK("seek_end_lock", fcntl(fd, F_SETLK, &end) == 0 && probe_type(F_WRLCK, 92, 1) == F_WRLCK && probe_type(F_WRLCK, 89, 1) == F_UNLCK, "errno=%d", errno);
    range_lock(fd, F_SETLK, F_UNLCK, 0, 0);
    struct flock back = {.l_type = F_WRLCK, .l_whence = SEEK_SET, .l_start = 50, .l_len = -10};
    CHECK("negative_length", fcntl(fd, F_SETLK, &back) == 0 && probe_type(F_WRLCK, 40, 1) == F_WRLCK && probe_type(F_WRLCK, 49, 1) == F_WRLCK && probe_type(F_WRLCK, 50, 1) == F_UNLCK, "errno=%d", errno);
    close(fd);
}

static void test_access_mode(void)
{
    int fd = open(PATH, O_RDONLY);
    CHECK("write_lock_needs_write_access", range_lock(fd, F_SETLK, F_WRLCK, 0, 0) == -1 && errno == EBADF, "errno=%d", errno);
    CHECK("read_lock_on_read_only_ok", range_lock(fd, F_SETLK, F_RDLCK, 0, 0) == 0, "errno=%d", errno);
    close(fd);
    fd = open(PATH, O_WRONLY);
    CHECK("read_lock_needs_read_access", range_lock(fd, F_SETLK, F_RDLCK, 0, 0) == -1 && errno == EBADF, "errno=%d", errno);
    close(fd);
}

static void test_ofd(void)
{
    int fd1 = open(PATH, O_RDWR | O_CREAT | O_TRUNC, 0644);
    int fd2 = open(PATH, O_RDWR);
    CHECK("ofd_lock_taken", range_lock(fd1, F_OFD_SETLK, F_WRLCK, 0, 0) == 0, "errno=%d", errno);
    CHECK("ofd_conflicts_inside_one_process", range_lock(fd2, F_OFD_SETLK, F_WRLCK, 0, 0) == -1 && errno == EAGAIN, "errno=%d", errno);
    struct flock fl = {.l_type = F_WRLCK, .l_whence = SEEK_SET, .l_start = 0, .l_len = 0};
    CHECK("ofd_getlk_reports_lock", fcntl(fd2, F_OFD_GETLK, &fl) == 0 && fl.l_type == F_WRLCK && fl.l_pid == -1, "type=%d pid=%d", fl.l_type, (int)fl.l_pid);
    CHECK("ofd_conflicts_with_posix", range_lock(fd2, F_SETLK, F_WRLCK, 0, 0) == -1 && errno == EAGAIN, "errno=%d", errno);
    int dupfd = dup(fd1);
    close(dupfd);
    CHECK("ofd_survives_close_of_dup", range_lock(fd2, F_OFD_SETLK, F_WRLCK, 0, 0) == -1 && errno == EAGAIN, "errno=%d", errno);
    close(open(PATH, O_RDWR));
    CHECK("ofd_survives_close_of_other_open", range_lock(fd2, F_OFD_SETLK, F_WRLCK, 0, 0) == -1 && errno == EAGAIN, "errno=%d", errno);
    struct flock bad = {.l_type = F_WRLCK, .l_whence = SEEK_SET, .l_start = 0, .l_len = 0, .l_pid = 7};
    CHECK("ofd_rejects_nonzero_pid", fcntl(fd2, F_OFD_SETLK, &bad) == -1 && errno == EINVAL, "errno=%d", errno);
    range_lock(fd1, F_OFD_SETLK, F_UNLCK, 20, 10);
    CHECK("ofd_split_unlock", range_lock(fd2, F_OFD_SETLK, F_WRLCK, 22, 2) == 0 && range_lock(fd2, F_OFD_SETLK, F_WRLCK, 5, 2) == -1, "errno=%d", errno);
    close(fd1);
    CHECK("ofd_released_by_last_close", range_lock(fd2, F_OFD_SETLK, F_WRLCK, 0, 0) == 0, "errno=%d", errno);
    pid_t child = fork();
    if (child == 0)
        _exit(range_lock(fd2, F_OFD_SETLK, F_WRLCK, 0, 0) == 0 ? 0 : 1);
    wait_ok("ofd_shared_with_forked_child", child);
    close(fd2);
    fd1 = open(PATH, O_RDWR);
    CHECK("ofd_released_by_process_exit_of_last_holder", range_lock(fd1, F_OFD_SETLK, F_WRLCK, 0, 0) == 0, "errno=%d", errno);
    close(fd1);
}

static int flock_probe(int fd, int op)
{
    return flock(fd, op | LOCK_NB);
}

static int flock_again(int fd)
{
    return flock_probe(fd, LOCK_EX) == -1 && errno == EWOULDBLOCK;
}

static void test_flock(void)
{
    int fd1 = open(PATH, O_RDWR | O_CREAT | O_TRUNC, 0644);
    int fd2 = open(PATH, O_RDWR);
    CHECK("flock_exclusive_taken", flock(fd1, LOCK_EX) == 0, "errno=%d", errno);
    CHECK("flock_exclusive_blocks_second_open", flock_again(fd2), "errno=%d", errno);
    CHECK("flock_shared_blocked_too", flock_probe(fd2, LOCK_SH) == -1 && errno == EWOULDBLOCK, "errno=%d", errno);
    CHECK("flock_independent_of_posix_locks", range_lock(fd2, F_SETLK, F_WRLCK, 0, 0) == 0, "errno=%d", errno);
    range_lock(fd2, F_SETLK, F_UNLCK, 0, 0);
    CHECK("flock_downgrade", flock(fd1, LOCK_SH) == 0 && flock_probe(fd2, LOCK_SH) == 0, "errno=%d", errno);
    CHECK("flock_shared_blocks_exclusive", flock_probe(fd2, LOCK_EX) == -1 && errno == EWOULDBLOCK, "errno=%d", errno);
    flock(fd2, LOCK_UN);
    CHECK("flock_upgrade", flock(fd1, LOCK_EX) == 0 && flock_again(fd2), "errno=%d", errno);
    CHECK("flock_unlock", flock(fd1, LOCK_UN) == 0 && flock_probe(fd2, LOCK_EX) == 0, "errno=%d", errno);
    flock(fd2, LOCK_UN);
    flock(fd1, LOCK_EX);
    int dupfd = dup(fd1);
    CHECK("flock_dup_shares_lock", flock_probe(dupfd, LOCK_EX) == 0, "errno=%d", errno);
    close(fd1);
    CHECK("flock_survives_close_of_one_dup", flock_again(fd2), "errno=%d", errno);
    close(dupfd);
    CHECK("flock_released_by_last_close", flock_probe(fd2, LOCK_EX) == 0, "errno=%d", errno);
    pid_t child = fork();
    if (child == 0)
        _exit(flock_probe(fd2, LOCK_EX) == 0 ? 0 : 1);
    wait_ok("flock_shared_with_forked_child", child);
    flock(fd2, LOCK_UN);
    CHECK("flock_invalid_zero_op", flock(fd2, 0) == -1 && errno == EINVAL, "errno=%d", errno);
    CHECK("flock_invalid_both", flock(fd2, LOCK_SH | LOCK_EX) == -1 && errno == EINVAL, "errno=%d", errno);
    CHECK("flock_bad_fd", flock(999, LOCK_EX) == -1 && errno == EBADF, "errno=%d", errno);
    child = fork();
    if (child == 0) {
        int cfd = open(PATH, O_RDWR);
        _exit(flock(cfd, LOCK_EX) == 0 ? 0 : 1);
    }
    wait_ok("flock_exit_of_holder_releases", child);
    CHECK("flock_free_after_holder_exit", flock_probe(fd2, LOCK_EX) == 0, "errno=%d", errno);
    flock(fd2, LOCK_UN);
    close(fd2);
}

static void test_flock_wait(void)
{
    int fd = open(PATH, O_RDWR | O_CREAT | O_TRUNC, 0644);
    flock(fd, LOCK_EX);
    int cfd = open(PATH, O_RDWR);
    struct wait_args a = {.fd = cfd, .cmd = -1, .type = 0};
    int ready;
    pid_t child = blocked_child(wait_for_lock_action, &a, &ready);
    wait_ready(ready);
    close(ready);
    usleep(SETTLE_US);
    CHECK("flock_waits_for_unlock", waitpid(child, 0, WNOHANG) == 0, "flock returned while the lock was held");
    flock(fd, LOCK_UN);
    wait_ok("flock_woken_by_unlock", child);
    close(cfd);
    close(fd);
}

static void test_dup2_release(void)
{
    int locked = open(PATH, O_RDWR | O_CREAT | O_TRUNC, 0644);
    int other = open(OTHER_PATH, O_RDWR | O_CREAT | O_TRUNC, 0644);
    lock_whole(locked, F_WRLCK);
    int second = open(PATH, O_RDWR);
    CHECK("dup2_over_other_fd_of_file_releases_lock", dup2(other, second) == second && foreign_sees(F_UNLCK), "lock survived dup2 over a descriptor of the file");
    CHECK("relock_after_dup2", lock_whole(locked, F_WRLCK) == 0, "errno=%d", errno);
    int third = open(PATH, O_RDWR);
    CHECK("dup3_over_other_fd_of_file_releases_lock", dup3(other, third, 0) == third && foreign_sees(F_UNLCK), "lock survived dup3 over a descriptor of the file");
    close(third);
    close(second);
    close(locked);
    close(other);
    unlink(OTHER_PATH);
}

static void test_exec_release(void)
{
    int fd = open(PATH, O_RDWR | O_CREAT | O_TRUNC, 0644);
    int pipefd[2];
    pipe(pipefd);
    pid_t child = fork();
    if (child == 0) {
        int cfd = open(PATH, O_RDWR | O_CLOEXEC);
        range_lock(cfd, F_SETLK, F_WRLCK, 0, 0);
        (void)!write(pipefd[1], "l", 1);
        char *av[] = {"/bin/c_child", "sleep3", 0};
        execve("/bin/c_child", av, 0);
        _exit(99);
    }
    wait_ready(pipefd[0]);
    long t0 = now_ms();
    int type = F_WRLCK;
    while (now_ms() - t0 < EXEC_POLL_MS && type != F_UNLCK) {
        usleep(20000);
        type = probe_type(F_WRLCK, 0, 1);
    }
    int alive = waitpid(child, 0, WNOHANG) == 0;
    CHECK("exec_closes_cloexec_fd_and_releases_lock", type == F_UNLCK && alive, "type=%d alive=%d", type, alive);
    waitpid(child, 0, 0);
    close(pipefd[0]);
    close(pipefd[1]);
    close(fd);
}

static void test_posix_basics(void)
{
    int fd = open(PATH, O_RDWR | O_CREAT | O_TRUNC, 0644);
    CHECK("lock_taken", lock_whole(fd, F_WRLCK) == 0, "errno=%d", errno);
    CHECK("foreign_sees_lock", foreign_sees(F_WRLCK), "child saw no lock");
    churn_threads(1);
    CHECK("thread_exit_keeps_lock", foreign_sees(F_WRLCK), "lock gone after one thread exit");
    churn_threads(THREAD_ROUNDS);
    CHECK("many_thread_exits_keep_lock", foreign_sees(F_WRLCK), "lock gone after %d thread exits", THREAD_ROUNDS);
    pid_t child = fork();
    if (child == 0)
        _exit(0);
    waitpid(child, 0, 0);
    CHECK("child_exit_keeps_parent_lock", foreign_sees(F_WRLCK), "lock gone after a child exit");
    close(open(PATH, O_RDWR));
    CHECK("close_of_other_fd_releases_lock", foreign_sees(F_UNLCK), "lock survived close of a second descriptor");
    CHECK("relock", lock_whole(fd, F_WRLCK) == 0, "errno=%d", errno);
    close(dup(fd));
    CHECK("close_of_dup_releases_lock", foreign_sees(F_UNLCK), "lock survived close of a dup");
    CHECK("relock_again", lock_whole(fd, F_WRLCK) == 0, "errno=%d", errno);
    close(fd);
    CHECK("close_of_locked_fd_releases_lock", foreign_sees(F_UNLCK), "lock survived close of the locking descriptor");
}

int main(void)
{
    test_posix_basics();
    test_ranges();
    test_access_mode();
    test_ofd();
    test_flock();
    test_flock_wait();
    test_blocking_wait();
    test_wait_woken_by_close();
    test_wait_interrupted();
    test_deadlock();
    test_dup2_release();
    test_exec_release();
    unlink(PATH);
    return 0;
}
