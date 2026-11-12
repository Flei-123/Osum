#define TNAME "sysnew"
#include "t.h"
#include <fcntl.h>
#include <pthread.h>
#include <sys/syscall.h>
#include <sys/timex.h>
#include <time.h>

#define NR_KCMP 312
#define NR_CLOCK_ADJTIME 305
#define NR_FUTEX_WAKE 454
#define NR_FUTEX_WAIT 455
#define KCMP_FILE 0
#define KCMP_VM 1
#define KCMP_FILES 2
#define KCMP_BAD_TYPE 99
#define FUTEX2_SIZE_U32 0x02
#define FUTEX2_PRIVATE 0x80
#define FLAGS_PRIVATE_U32 (FUTEX2_SIZE_U32 | FUTEX2_PRIVATE)
#define MASK_ALL 0xffffffffUL
#define NO_SUCH_PID 999999
#define WAKE_WAIT_MS 200

static volatile unsigned futex_word;
static volatile int waiter_result = 1;

static long raw(long nr, long a, long b, long c, long d, long e, long f)
{
    errno = 0;
    return syscall(nr, a, b, c, d, e, f);
}

static void kcmp_checks(void)
{
    long self = getpid();
    int fd_a = open("/dev/null", O_RDONLY);
    int fd_b = dup(fd_a);
    int fd_c = open("/dev/null", O_RDONLY);
    long r = raw(NR_KCMP, self, self, KCMP_FILE, fd_a, fd_b, 0);
    CHECKC("kcmp_file_dup_equal", r == 0);
    r = raw(NR_KCMP, self, self, KCMP_FILE, fd_a, fd_c, 0);
    CHECKC("kcmp_file_distinct", r == 1 || r == 2);
    r = raw(NR_KCMP, self, self, KCMP_FILE, fd_a, 9999, 0);
    CHECK("kcmp_file_bad_fd", r == -1 && errno == EBADF, "r=%ld errno=%d", r, errno);
    r = raw(NR_KCMP, self, self, KCMP_VM, 0, 0, 0);
    CHECKC("kcmp_vm_self", r == 0);
    r = raw(NR_KCMP, self, self, KCMP_FILES, 0, 0, 0);
    CHECKC("kcmp_files_self", r == 0);
    r = raw(NR_KCMP, self, self, KCMP_BAD_TYPE, 0, 0, 0);
    CHECK("kcmp_bad_type", r == -1 && errno == EINVAL, "r=%ld errno=%d", r, errno);
    r = raw(NR_KCMP, NO_SUCH_PID, self, KCMP_FILE, 0, 0, 0);
    CHECK("kcmp_no_such_pid", r == -1 && errno == ESRCH, "r=%ld errno=%d", r, errno);
    close(fd_a);
    close(fd_b);
    close(fd_c);
}

static void clock_adjtime_checks(void)
{
    struct timex tx;
    memset(&tx, 0, sizeof tx);
    long r = raw(NR_CLOCK_ADJTIME, CLOCK_REALTIME, (long)&tx, 0, 0, 0, 0);
    CHECKC("clock_adjtime_realtime_read", r >= 0);
    r = raw(NR_CLOCK_ADJTIME, CLOCK_MONOTONIC, (long)&tx, 0, 0, 0, 0);
    CHECK("clock_adjtime_monotonic_refused", r == -1 && errno == EOPNOTSUPP, "r=%ld errno=%d", r, errno);
    r = raw(NR_CLOCK_ADJTIME, CLOCK_REALTIME, 0, 0, 0, 0, 0);
    CHECK("clock_adjtime_null", r == -1 && errno == EFAULT, "r=%ld errno=%d", r, errno);
}

static void *waiter(void *arg)
{
    (void)arg;
    long r = raw(NR_FUTEX_WAIT, (long)&futex_word, 0, MASK_ALL, FLAGS_PRIVATE_U32, 0, CLOCK_MONOTONIC);
    waiter_result = (int)r;
    return NULL;
}

static void futex2_checks(void)
{
    futex_word = 1;
    long r = raw(NR_FUTEX_WAIT, (long)&futex_word, 0, MASK_ALL, FLAGS_PRIVATE_U32, 0, CLOCK_MONOTONIC);
    CHECKC("futex_wait_value_mismatch", r == -1 && errno == EAGAIN);
    r = raw(NR_FUTEX_WAKE, (long)&futex_word, 0, 1, FLAGS_PRIVATE_U32, 0, 0);
    CHECK("futex_wake_zero_mask", r == -1 && errno == EINVAL, "r=%ld errno=%d", r, errno);
    r = raw(NR_FUTEX_WAKE, (long)&futex_word, MASK_ALL, 1, 0, 0, 0);
    CHECK("futex_wake_bad_size", r == -1 && errno == EINVAL, "r=%ld errno=%d", r, errno);
    r = raw(NR_FUTEX_WAKE, (long)&futex_word, MASK_ALL, 1, FLAGS_PRIVATE_U32, 0, 0);
    CHECKC("futex_wake_nobody", r == 0);
    struct timespec past = {0, 1};
    r = raw(NR_FUTEX_WAIT, (long)&futex_word, 1, MASK_ALL, FLAGS_PRIVATE_U32, (long)&past, CLOCK_MONOTONIC);
    CHECK("futex_wait_timeout", r == -1 && errno == ETIMEDOUT, "r=%ld errno=%d", r, errno);
    futex_word = 0;
    pthread_t th;
    pthread_create(&th, NULL, waiter, NULL);
    struct timespec nap = {0, WAKE_WAIT_MS * 1000000L};
    nanosleep(&nap, NULL);
    r = raw(NR_FUTEX_WAKE, (long)&futex_word, MASK_ALL, 1, FLAGS_PRIVATE_U32, 0, 0);
    pthread_join(th, NULL);
    CHECK("futex_wake_one_waiter", r == 1 && waiter_result == 0, "wake=%ld waiter=%d", r, waiter_result);
}

static long read_file(const char *path, char *buf, size_t cap)
{
    int fd = open(path, O_RDONLY);
    if (fd < 0)
        return -1;
    long n = read(fd, buf, cap - 1);
    close(fd);
    if (n >= 0)
        buf[n] = 0;
    return n;
}

static void proc_empty_check(const char *name, const char *path)
{
    char buf[256];
    long n = read_file(path, buf, sizeof buf);
    CHECKC(name, n == 0);
}

static void proc_prefix_check(const char *name, const char *path, const char *prefix)
{
    char buf[256];
    long n = read_file(path, buf, sizeof buf);
    CHECKC(name, n > 0 && strncmp(buf, prefix, strlen(prefix)) == 0);
}

static void procfs_checks(void)
{
    proc_empty_check("proc_locks_empty", "/proc/locks");
    proc_empty_check("proc_modules_empty", "/proc/modules");
    proc_empty_check("proc_kallsyms_empty", "/proc/kallsyms");
    proc_empty_check("proc_crypto_empty", "/proc/crypto");
    proc_empty_check("proc_misc_empty", "/proc/misc");
    proc_empty_check("proc_net_if_inet6_empty", "/proc/net/if_inet6");
    proc_empty_check("proc_net_ipv6_route_empty", "/proc/net/ipv6_route");
    proc_prefix_check("proc_schedstat", "/proc/schedstat", "version 15\n");
    proc_prefix_check("proc_net_unix_header", "/proc/net/unix", "Num ");
    proc_prefix_check("proc_net_tcp6_header", "/proc/net/tcp6", "  sl  local_address");
    proc_prefix_check("proc_net_udp6_header", "/proc/net/udp6", "  sl  local_address");
    proc_prefix_check("proc_net_raw_header", "/proc/net/raw", "  sl  local_address");
}

int main(void)
{
    alarm(60);
    kcmp_checks();
    clock_adjtime_checks();
    futex2_checks();
    procfs_checks();
    return 0;
}
