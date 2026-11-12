#define TNAME "prctl"
#include "t.h"
#include <signal.h>
#include <stdlib.h>
#include <string.h>
#include <sys/syscall.h>
#include <sys/wait.h>
#include <unistd.h>

#define OPT_SET_PDEATHSIG 1
#define OPT_GET_PDEATHSIG 2
#define OPT_GET_KEEPCAPS 7
#define OPT_SET_KEEPCAPS 8
#define OPT_CAPBSET_READ 23
#define OPT_CAPBSET_DROP 24
#define OPT_GET_SECUREBITS 27
#define OPT_SET_SECUREBITS 28
#define OPT_SET_TIMERSLACK 29
#define OPT_GET_TIMERSLACK 30
#define OPT_SET_CHILD_SUBREAPER 36
#define OPT_GET_CHILD_SUBREAPER 37
#define OPT_GET_TID_ADDRESS 40
#define OPT_SET_THP_DISABLE 41
#define OPT_GET_THP_DISABLE 42
#define OPT_SET_PTRACER 0x59616d61
#define OPT_GET_TIMING 13
#define OPT_GET_TSC 25
#define OPT_MCE_KILL_GET 34
#define OPT_GET_SPECULATION_CTRL 52
#define OPT_GET_IO_FLUSHER 58
#define ANY_PTRACER (-1L)
#define DEFAULT_SLACK 50000L
#define WAIT_TICKS 300

static long pr(long option, long a2)
{
    errno = 0;
    return syscall(SYS_prctl, option, a2, 0L, 0L, 0L);
}

static int in_child(int (*body)(void))
{
    pid_t pid = fork();
    if (pid < 0)
        return -1;
    if (pid == 0)
        _exit(body());
    int status = 0;
    if (waitpid(pid, &status, 0) != pid || !WIFEXITED(status))
        return -1;
    return WEXITSTATUS(status);
}

static int pdeathsig_child_cleared(void)
{
    int v = -1;
    return pr(OPT_GET_PDEATHSIG, (long)&v) == 0 && v == 0 ? 0 : 1;
}

static void test_pdeathsig_state(void)
{
    int got = -1;
    CHECK("pdeathsig_default_zero", pr(OPT_GET_PDEATHSIG, (long)&got) == 0 && got == 0, "got=%d errno=%d", got, errno);
    CHECK("pdeathsig_set", pr(OPT_SET_PDEATHSIG, SIGUSR1) == 0, "errno=%d", errno);
    got = -1;
    CHECK("pdeathsig_roundtrip", pr(OPT_GET_PDEATHSIG, (long)&got) == 0 && got == SIGUSR1, "got=%d", got);
    CHECK("pdeathsig_bad_signal", pr(OPT_SET_PDEATHSIG, 65) == -1 && errno == EINVAL, "errno=%d", errno);
    CHECK("pdeathsig_null_pointer", pr(OPT_GET_PDEATHSIG, 0) == -1 && errno == EFAULT, "errno=%d", errno);
    CHECK("pdeathsig_cleared_by_fork", in_child(pdeathsig_child_cleared) == 0, "child failed");
    pr(OPT_SET_PDEATHSIG, 0);
}

static volatile sig_atomic_t death_seen;

static void on_death(int sig)
{
    (void)sig;
    death_seen = 1;
}

static int grandchild_waits_for_signal(int report_fd)
{
    struct sigaction sa;
    memset(&sa, 0, sizeof sa);
    sa.sa_handler = on_death;
    sigaction(SIGUSR2, &sa, NULL);
    if (pr(OPT_SET_PDEATHSIG, SIGUSR2) != 0)
        return 2;
    char ready = 1;
    if (write(report_fd, &ready, 1) != 1)
        return 3;
    int ticks = 0;
    while (!death_seen && ticks < WAIT_TICKS) {
        usleep(10000);
        ticks++;
    }
    char result = death_seen ? 'y' : 'n';
    if (write(report_fd, &result, 1) != 1)
        return 4;
    return 0;
}

static void test_pdeathsig_effect(void)
{
    int fds[2];
    if (pipe(fds) != 0) {
        FAIL("pdeathsig_effect", "pipe errno=%d", errno);
        return;
    }
    pid_t middle = fork();
    if (middle == 0) {
        pid_t grand = fork();
        if (grand == 0) {
            _exit(grandchild_waits_for_signal(fds[1]));
        }
        char ready = 0;
        if (read(fds[0], &ready, 1) != 1)
            _exit(5);
        _exit(0);
    }
    int status = 0;
    waitpid(middle, &status, 0);
    char result = 0;
    ssize_t n = read(fds[0], &result, 1);
    CHECK("pdeathsig_effect", n == 1 && result == 'y', "n=%zd result=%d", n, result);
    while (waitpid(-1, &status, WNOHANG) > 0) {
    }
    close(fds[0]);
    close(fds[1]);
}

static int keepcaps_child_inherited(void)
{
    return pr(OPT_GET_KEEPCAPS, 0) == 1 ? 0 : 1;
}

static void test_keepcaps(void)
{
    CHECK("keepcaps_default_zero", pr(OPT_GET_KEEPCAPS, 0) == 0, "errno=%d", errno);
    CHECK("keepcaps_set", pr(OPT_SET_KEEPCAPS, 1) == 0, "errno=%d", errno);
    CHECK("keepcaps_get_one", pr(OPT_GET_KEEPCAPS, 0) == 1, "errno=%d", errno);
    CHECK("keepcaps_bad_value", pr(OPT_SET_KEEPCAPS, 2) == -1 && errno == EINVAL, "errno=%d", errno);
    CHECK("keepcaps_inherited_by_fork", in_child(keepcaps_child_inherited) == 0, "child failed");
    pr(OPT_SET_KEEPCAPS, 0);
}

static int capbset_drop_child(void)
{
    if (pr(OPT_CAPBSET_DROP, 5) != 0)
        return 1;
    if (pr(OPT_CAPBSET_READ, 5) != 0)
        return 2;
    if (pr(OPT_CAPBSET_READ, 6) != 1)
        return 3;
    return 0;
}

static void test_capbset(void)
{
    CHECK("capbset_read_first", pr(OPT_CAPBSET_READ, 0) == 1, "errno=%d", errno);
    CHECK("capbset_read_last", pr(OPT_CAPBSET_READ, 40) == 1, "errno=%d", errno);
    CHECK("capbset_read_invalid", pr(OPT_CAPBSET_READ, 64) == -1 && errno == EINVAL, "errno=%d", errno);
    CHECK("capbset_drop_per_task", in_child(capbset_drop_child) == 0, "child failed");
    CHECK("capbset_drop_not_shared", pr(OPT_CAPBSET_READ, 5) == 1, "errno=%d", errno);
}

static int slack_child_inherited(void)
{
    return pr(OPT_GET_TIMERSLACK, 0) == 1234 ? 0 : 1;
}

static void test_timerslack(void)
{
    CHECK("timerslack_default", pr(OPT_GET_TIMERSLACK, 0) == DEFAULT_SLACK, "errno=%d", errno);
    CHECK("timerslack_set", pr(OPT_SET_TIMERSLACK, 1234) == 0, "errno=%d", errno);
    CHECK("timerslack_roundtrip", pr(OPT_GET_TIMERSLACK, 0) == 1234, "errno=%d", errno);
    CHECK("timerslack_inherited_by_fork", in_child(slack_child_inherited) == 0, "child failed");
    CHECK("timerslack_zero_resets", pr(OPT_SET_TIMERSLACK, 0) == 0 && pr(OPT_GET_TIMERSLACK, 0) == DEFAULT_SLACK, "errno=%d", errno);
}

static int grandchild_reports_parent(int report_fd)
{
    int ticks = 0;
    pid_t first = getppid();
    while (getppid() == first && ticks < WAIT_TICKS) {
        usleep(10000);
        ticks++;
    }
    pid_t now = getppid();
    return write(report_fd, &now, sizeof now) == sizeof now ? 0 : 1;
}

static void test_subreaper(void)
{
    int got = -1;
    CHECK("subreaper_default_zero", pr(OPT_GET_CHILD_SUBREAPER, (long)&got) == 0 && got == 0, "got=%d errno=%d", got, errno);
    CHECK("subreaper_set", pr(OPT_SET_CHILD_SUBREAPER, 1) == 0, "errno=%d", errno);
    got = -1;
    CHECK("subreaper_roundtrip", pr(OPT_GET_CHILD_SUBREAPER, (long)&got) == 0 && got == 1, "got=%d", got);
    int fds[2];
    if (pipe(fds) != 0) {
        FAIL("subreaper_adopts_orphan", "pipe errno=%d", errno);
        return;
    }
    pid_t middle = fork();
    if (middle == 0) {
        pid_t grand = fork();
        if (grand == 0)
            _exit(grandchild_reports_parent(fds[1]));
        usleep(50000);
        _exit(0);
    }
    int status = 0;
    waitpid(middle, &status, 0);
    pid_t adopter = -1;
    ssize_t n = read(fds[0], &adopter, sizeof adopter);
    CHECK("subreaper_adopts_orphan", n == sizeof adopter && adopter == getpid(), "adopter=%d self=%d", adopter, getpid());
    CHECK("subreaper_orphan_waitable", waitpid(-1, &status, 0) > 0, "errno=%d", errno);
    close(fds[0]);
    close(fds[1]);
    pr(OPT_SET_CHILD_SUBREAPER, 0);
}

static int subreaper_not_inherited(void)
{
    int v = -1;
    return pr(OPT_GET_CHILD_SUBREAPER, (long)&v) == 0 && v == 0 ? 0 : 1;
}

static void test_subreaper_fork(void)
{
    pr(OPT_SET_CHILD_SUBREAPER, 1);
    CHECK("subreaper_not_inherited", in_child(subreaper_not_inherited) == 0, "child failed");
    pr(OPT_SET_CHILD_SUBREAPER, 0);
}

static long tid_slot;

static void test_tid_address(void)
{
    syscall(SYS_set_tid_address, &tid_slot);
    unsigned long got = 0;
    CHECK("tid_address_roundtrip", pr(OPT_GET_TID_ADDRESS, (long)&got) == 0 && got == (unsigned long)&tid_slot, "got=%lx want=%lx errno=%d", got, (unsigned long)&tid_slot, errno);
    CHECK("tid_address_null_pointer", pr(OPT_GET_TID_ADDRESS, 0) == -1 && errno == EFAULT, "errno=%d", errno);
}

static int thp_child_inherited(void)
{
    return pr(OPT_GET_THP_DISABLE, 0) == 1 ? 0 : 1;
}

static void test_thp(void)
{
    CHECK("thp_default_zero", pr(OPT_GET_THP_DISABLE, 0) == 0, "errno=%d", errno);
    CHECK("thp_set", pr(OPT_SET_THP_DISABLE, 1) == 0, "errno=%d", errno);
    CHECK("thp_get_one", pr(OPT_GET_THP_DISABLE, 0) == 1, "errno=%d", errno);
    CHECK("thp_inherited_by_fork", in_child(thp_child_inherited) == 0, "child failed");
    CHECK("thp_clear", pr(OPT_SET_THP_DISABLE, 0) == 0 && pr(OPT_GET_THP_DISABLE, 0) == 0, "errno=%d", errno);
    errno = 0;
    CHECK("thp_extra_args_rejected", syscall(SYS_prctl, OPT_SET_THP_DISABLE, 1L, 1L, 0L, 0L) == -1 && errno == EINVAL, "errno=%d", errno);
}

static void test_ptracer(void)
{
    CHECK("ptracer_any", pr(OPT_SET_PTRACER, ANY_PTRACER) == 0, "errno=%d", errno);
    CHECK("ptracer_none", pr(OPT_SET_PTRACER, 0) == 0, "errno=%d", errno);
    CHECK("ptracer_self_pid", pr(OPT_SET_PTRACER, getpid()) == 0, "errno=%d", errno);
    CHECK("ptracer_unknown_pid", pr(OPT_SET_PTRACER, 99999999) == -1 && errno == EINVAL, "errno=%d", errno);
}

static int securebits_child(void)
{
    if (pr(OPT_GET_SECUREBITS, 0) != 0)
        return 1;
    if (pr(OPT_SET_SECUREBITS, 0x10) != 0 || pr(OPT_GET_SECUREBITS, 0) != 0x10)
        return 2;
    if (pr(OPT_SET_SECUREBITS, 0x100) != -1 || errno != EPERM)
        return 3;
    if (pr(OPT_SET_SECUREBITS, 0x03) != 0)
        return 4;
    if (pr(OPT_SET_SECUREBITS, 0) != -1 || errno != EPERM)
        return 5;
    if (pr(OPT_GET_SECUREBITS, 0) != 0x03)
        return 6;
    return 0;
}

static void test_securebits(void)
{
    CHECK("securebits_lock_semantics", in_child(securebits_child) == 0, "child failed");
    CHECK("securebits_not_shared", pr(OPT_GET_SECUREBITS, 0) == 0, "errno=%d", errno);
}

static void test_constant_getters(void)
{
    int tsc = 0;
    CHECK("get_tsc", pr(OPT_GET_TSC, (long)&tsc) == 0 && tsc == 1, "tsc=%d errno=%d", tsc, errno);
    CHECK("get_timing", pr(OPT_GET_TIMING, 0) == 0, "errno=%d", errno);
    CHECK("mce_kill_get", pr(OPT_MCE_KILL_GET, 0) == 2, "errno=%d", errno);
    CHECK("get_speculation_ctrl", pr(OPT_GET_SPECULATION_CTRL, 0) == 0, "errno=%d", errno);
    CHECK("get_io_flusher", pr(OPT_GET_IO_FLUSHER, 0) == 0, "errno=%d", errno);
}

int main(void)
{
    alarm(60);
    test_constant_getters();
    test_pdeathsig_state();
    test_pdeathsig_effect();
    test_keepcaps();
    test_capbset();
    test_timerslack();
    test_subreaper();
    test_subreaper_fork();
    test_tid_address();
    test_thp();
    test_ptracer();
    test_securebits();
    return 0;
}
