#define TNAME "sysroot"
#include "t.h"
#include <sched.h>
#include <sys/syscall.h>

#define NR_VHANGUP 153
#define NR_PIVOT_ROOT 155
#define NR_ACCT 163
#define NR_SWAPON 167
#define NR_SWAPOFF 168
#define NR_IOPL 172
#define NR_IOPERM 173
#define NR_UNSHARE 272
#define NR_SETNS 308
#define PORT_COUNT 8
#define PORT_BASE 0x80
#define IOPL_USER 3

static long raw(long nr, long a, long b, long c)
{
    errno = 0;
    return syscall(nr, a, b, c, 0L, 0L, 0L);
}

static int denied(long r)
{
    return r == -1 && (errno == EPERM || errno == EACCES);
}

int main(void)
{
    alarm(30);
    CHECKC("vhangup", raw(NR_VHANGUP, 0, 0, 0) == 0);
    CHECKC("unshare_zero", raw(NR_UNSHARE, 0, 0, 0) == 0);
    CHECKC("unshare_newns_denied", denied(raw(NR_UNSHARE, CLONE_NEWNS, 0, 0)));
    CHECKC("ioperm_denied", denied(raw(NR_IOPERM, PORT_BASE, PORT_COUNT, 1)));
    CHECKC("iopl_denied", denied(raw(NR_IOPL, IOPL_USER, 0, 0)));
    CHECKC("swapon_denied", denied(raw(NR_SWAPON, (long)"/nonexistent", 0, 0)));
    CHECKC("swapoff_denied", denied(raw(NR_SWAPOFF, (long)"/nonexistent", 0, 0)));
    CHECKC("pivot_root_denied", denied(raw(NR_PIVOT_ROOT, (long)"/", (long)"/", 0)));
    CHECKC("setns_denied", denied(raw(NR_SETNS, -1, 0, 0)));
    CHECKC("acct_off", raw(NR_ACCT, 0, 0, 0) == 0);
    CHECKC("acct_path_denied", denied(raw(NR_ACCT, (long)"/tmp/acct", 0, 0)));
    return 0;
}
