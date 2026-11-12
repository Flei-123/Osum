#define TNAME "sysmisc"
#include "t.h"
#include <sys/syscall.h>
#include <sys/time.h>
#include <sys/utsname.h>
#include <time.h>

#define NR_PERSONALITY 135
#define NR_SCHED_RR_GET_INTERVAL 148
#define NR_SETTIMEOFDAY 164
#define NR_LREMOVEXATTR 198
#define NR_FREMOVEXATTR 199
#define NR_IOPRIO_SET 251
#define NR_IOPRIO_GET 252
#define NR_SETFSUID 122
#define IOPRIO_WHO_PROCESS 1
#define IOPRIO_CLASS_SHIFT 13
#define IOPRIO_CLASS_BE 2
#define IOPRIO_CLASS_IDLE 3
#define PERSONALITY_QUERY 0xffffffffUL
#define ADDR_NO_RANDOMIZE 0x0040000UL
#define RR_SLICE_NS 100000000L
#define CLOCK_STEP_SECONDS 5
#define NO_SUCH_PID 999999

static long raw(long nr, long a, long b, long c)
{
    errno = 0;
    return syscall(nr, a, b, c, 0L, 0L, 0L);
}

static void ioprio_checks(void)
{
    long r = raw(NR_IOPRIO_GET, IOPRIO_WHO_PROCESS, 0, 0);
    CHECKC("ioprio_get", r >= 0);
    r = raw(NR_IOPRIO_SET, IOPRIO_WHO_PROCESS, 0, (IOPRIO_CLASS_BE << IOPRIO_CLASS_SHIFT) | 4);
    CHECKC("ioprio_set_be", r == 0);
    r = raw(NR_IOPRIO_SET, IOPRIO_WHO_PROCESS, 0, IOPRIO_CLASS_IDLE << IOPRIO_CLASS_SHIFT);
    CHECKC("ioprio_set_idle", r == 0);
    r = raw(NR_IOPRIO_SET, IOPRIO_WHO_PROCESS, 0, 4 << IOPRIO_CLASS_SHIFT);
    CHECKC("ioprio_bad_class", r == -1 && errno == EINVAL);
    r = raw(NR_IOPRIO_SET, 9, 0, 0);
    CHECKC("ioprio_bad_which", r == -1 && errno == EINVAL);
    r = raw(NR_IOPRIO_SET, IOPRIO_WHO_PROCESS, 0, (IOPRIO_CLASS_BE << IOPRIO_CLASS_SHIFT) | 8);
    CHECKC("ioprio_bad_level", r == -1 && errno == EINVAL);
    r = raw(NR_IOPRIO_GET, IOPRIO_WHO_PROCESS, NO_SUCH_PID, 0);
    CHECKC("ioprio_no_such_pid", r == -1 && errno == ESRCH);
}

static void hostname_checks(void)
{
    struct utsname u;
    char buf[80];
    char big[80];
    const char host[] = "orient-test";
    const char domain[] = "orient.example";
    errno = 0;
    CHECKC("sethostname", sethostname(host, sizeof host - 1) == 0);
    uname(&u);
    CHECK("sethostname_uname", strcmp(u.nodename, host) == 0, "nodename=%s", u.nodename);
    gethostname(buf, sizeof buf);
    CHECK("gethostname", strcmp(buf, host) == 0, "got=%s", buf);
    errno = 0;
    CHECKC("setdomainname", setdomainname(domain, sizeof domain - 1) == 0);
    uname(&u);
    CHECK("setdomainname_uname", strcmp(u.domainname, domain) == 0, "domain=%s", u.domainname);
    memset(big, 'a', sizeof big);
    errno = 0;
    CHECKC("sethostname_too_long", sethostname(big, 65) == -1 && errno == EINVAL);
    errno = 0;
    CHECKC("sethostname_fault", sethostname((const char *)1, 4) == -1 && errno == EFAULT);
    uname(&u);
    CHECK("sethostname_failed_keeps_old", strcmp(u.nodename, host) == 0, "nodename=%s", u.nodename);
}

static void personality_checks(void)
{
    long base = raw(NR_PERSONALITY, (long)PERSONALITY_QUERY, 0, 0);
    CHECKC("personality_query", base == 0);
    long prev = raw(NR_PERSONALITY, (long)ADDR_NO_RANDOMIZE, 0, 0);
    CHECKC("personality_set_returns_old", prev == 0);
    long now = raw(NR_PERSONALITY, (long)PERSONALITY_QUERY, 0, 0);
    CHECK("personality_set_sticks", now == (long)ADDR_NO_RANDOMIZE, "now=0x%lx", now);
    raw(NR_PERSONALITY, 0, 0, 0);
}

static void rr_interval_checks(void)
{
    struct timespec ts = { 7, 7 };
    long r = raw(NR_SCHED_RR_GET_INTERVAL, 0, (long)&ts, 0);
    CHECKC("rr_interval", r == 0 && ts.tv_sec == 0 && ts.tv_nsec == RR_SLICE_NS);
    r = raw(NR_SCHED_RR_GET_INTERVAL, -1, (long)&ts, 0);
    CHECKC("rr_interval_negative_pid", r == -1 && errno == EINVAL);
    r = raw(NR_SCHED_RR_GET_INTERVAL, NO_SUCH_PID, (long)&ts, 0);
    CHECKC("rr_interval_no_such_pid", r == -1 && errno == ESRCH);
    r = raw(NR_SCHED_RR_GET_INTERVAL, 0, 1, 0);
    CHECKC("rr_interval_fault", r == -1 && errno == EFAULT);
}

static void settimeofday_checks(void)
{
    struct timeval before, after, want;
    gettimeofday(&before, 0);
    want.tv_sec = before.tv_sec + CLOCK_STEP_SECONDS;
    want.tv_usec = 0;
    long r = raw(NR_SETTIMEOFDAY, (long)&want, 0, 0);
    CHECKC("settimeofday", r == 0);
    gettimeofday(&after, 0);
    long delta = after.tv_sec - before.tv_sec;
    CHECK("settimeofday_moves_clock", delta >= CLOCK_STEP_SECONDS && delta <= CLOCK_STEP_SECONDS + 2, "delta=%ld", delta);
    want.tv_usec = 1000000;
    r = raw(NR_SETTIMEOFDAY, (long)&want, 0, 0);
    CHECKC("settimeofday_bad_usec", r == -1 && errno == EINVAL);
    r = raw(NR_SETTIMEOFDAY, 1, 0, 0);
    CHECKC("settimeofday_fault", r == -1 && errno == EFAULT);
}

static void small_checks(void)
{
    long r = raw(NR_SETFSUID, -1, 0, 0);
    CHECK("setfsuid_returns_previous", r == (long)geteuid(), "r=%ld euid=%d", r, (int)geteuid());
    errno = 0;
    r = raw(NR_LREMOVEXATTR, (long)"/", (long)"user.x", 0);
    CHECK("lremovexattr_not_enosys", r == -1 && errno != ENOSYS, "errno=%d", errno);
    r = raw(NR_FREMOVEXATTR, 0, (long)"user.x", 0);
    CHECK("fremovexattr_not_enosys", r == -1 && errno != ENOSYS, "errno=%d", errno);
}

int main(void)
{
    alarm(60);
    ioprio_checks();
    hostname_checks();
    personality_checks();
    rr_interval_checks();
    settimeofday_checks();
    small_checks();
    return 0;
}
