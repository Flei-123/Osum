#define TNAME "seccomp"
#include "t.h"
#include <pthread.h>
#include <signal.h>
#include <stdint.h>
#include <stdlib.h>
#include <sys/prctl.h>
#include <sys/syscall.h>
#include <sys/wait.h>

#ifndef SYS_seccomp
#define SYS_seccomp 317
#endif
#define PR_SET_NNP 38
#define PR_GET_NNP 39
#define PR_GET_SECCOMP_NR 21
#define PR_SET_SECCOMP_NR 22
#define SC_SET_MODE_STRICT 0
#define RET_KILL_THREAD 0u
#define SYS_SECCOMP_CODE 1
#define SIGINFO_CALL_ADDR 16
#define SIGINFO_SYSCALL 24
#define SIGINFO_ARCH 28
#define SC_SET_MODE_FILTER 1
#define SC_GET_ACTION_AVAIL 2
#define SC_FLAG_TSYNC 1
#define ARCH_X86_64 0xC000003Eu
#define RET_KILL_PROCESS 0x80000000u
#define RET_TRAP 0x00030000u
#define RET_ERRNO 0x00050000u
#define RET_ALLOW 0x7FFF0000u
#define OFF_NR 0
#define OFF_ARCH 4
#define OFF_ARG0 16
#define NR_PROBE SYS_getppid

struct insn { uint16_t code; uint8_t jt; uint8_t jf; uint32_t k; };
struct prog { uint16_t len; uint16_t pad[3]; struct insn *filter; };

#define LD_ABS(off) { 0x20, 0, 0, (off) }
#define JEQ(v, jt, jf) { 0x15, (jt), (jf), (v) }
#define JGT(v, jt, jf) { 0x25, (jt), (jf), (v) }
#define RET(v) { 0x06, 0, 0, (v) }
#define RET_A { 0x16, 0, 0, 0 }

static long seccomp_call(unsigned op, unsigned flags, void *args)
{
    return syscall(SYS_seccomp, op, flags, args);
}

static long install(struct insn *f, unsigned n, unsigned flags)
{
    struct prog p = { (uint16_t)n, {0, 0, 0}, f };
    return seccomp_call(SC_SET_MODE_FILTER, flags, &p);
}

static long install_nr_action(unsigned nr, unsigned action, unsigned flags)
{
    struct insn f[] = { LD_ABS(OFF_NR), JEQ(nr, 0, 1), RET(action), RET(RET_ALLOW) };
    return install(f, 4, flags);
}

static int probe_errno(void)
{
    errno = 0;
    long r = syscall(NR_PROBE);
    return r == -1 ? errno : 0;
}

static volatile sig_atomic_t trapped;
static void on_sigsys(int s) { (void)s; trapped = 1; }

static volatile int info_signo, info_code, info_syscall;
static volatile long info_rax;
static volatile unsigned info_arch;
static volatile unsigned long info_call_addr;

static void on_sigsys_info(int s, siginfo_t *si, void *uc)
{
    info_rax = ((ucontext_t *)uc)->uc_mcontext.gregs[REG_RAX];
    const unsigned char *raw = (const unsigned char *)si;
    info_signo = s == si->si_signo ? s : -1;
    info_code = si->si_code;
    info_call_addr = *(const unsigned long *)(raw + SIGINFO_CALL_ADDR);
    info_syscall = *(const int *)(raw + SIGINFO_SYSCALL);
    info_arch = *(const unsigned *)(raw + SIGINFO_ARCH);
    trapped = 1;
}

static int child_status(int (*body)(void))
{
    pid_t pid = fork();
    if (pid == 0)
        _exit(body());
    int st = 0;
    waitpid(pid, &st, 0);
    return st;
}

static int body_errno(void)
{
    prctl(PR_SET_NNP, 1, 0, 0, 0);
    if (install_nr_action(NR_PROBE, RET_ERRNO | EACCES, 0) != 0)
        return 90;
    return probe_errno() == EACCES ? 0 : 91;
}

static int body_other_allowed(void)
{
    prctl(PR_SET_NNP, 1, 0, 0, 0);
    if (install_nr_action(NR_PROBE, RET_ERRNO | EACCES, 0) != 0)
        return 90;
    return syscall(SYS_getpid) > 0 ? 0 : 91;
}

static int body_kill(void)
{
    prctl(PR_SET_NNP, 1, 0, 0, 0);
    if (install_nr_action(NR_PROBE, RET_KILL_PROCESS, 0) != 0)
        return 90;
    syscall(NR_PROBE);
    return 92;
}

static int body_trap(void)
{
    struct sigaction sa;
    memset(&sa, 0, sizeof sa);
    sa.sa_handler = on_sigsys;
    sigaction(SIGSYS, &sa, 0);
    prctl(PR_SET_NNP, 1, 0, 0, 0);
    if (install_nr_action(NR_PROBE, RET_TRAP, 0) != 0)
        return 90;
    syscall(NR_PROBE);
    return trapped ? 0 : 91;
}

static int body_trap_info(void)
{
    struct sigaction sa;
    memset(&sa, 0, sizeof sa);
    sa.sa_sigaction = on_sigsys_info;
    sa.sa_flags = SA_SIGINFO;
    sigaction(SIGSYS, &sa, 0);
    prctl(PR_SET_NNP, 1, 0, 0, 0);
    if (install_nr_action(NR_PROBE, RET_TRAP, 0) != 0)
        return 90;
    errno = 0;
    long r = syscall(NR_PROBE);
    int e = errno;
    if (!trapped)
        return 91;
    if (info_signo != SIGSYS || info_code != SYS_SECCOMP_CODE)
        return 92;
    if (info_syscall != NR_PROBE || info_arch != ARCH_X86_64 || info_call_addr == 0)
        return 93;
    (void)e;
    if (info_rax != NR_PROBE)
        return 95;
    return r == NR_PROBE ? 0 : 94;
}

static int body_trap_blocked(void)
{
    struct sigaction sa;
    memset(&sa, 0, sizeof sa);
    sa.sa_handler = on_sigsys;
    sigaction(SIGSYS, &sa, 0);
    sigset_t set;
    sigemptyset(&set);
    sigaddset(&set, SIGSYS);
    sigprocmask(SIG_BLOCK, &set, 0);
    prctl(PR_SET_NNP, 1, 0, 0, 0);
    if (install_nr_action(NR_PROBE, RET_TRAP, 0) != 0)
        return 90;
    syscall(NR_PROBE);
    return trapped ? 0 : 91;
}

static int body_kill_thread_with_handler(void)
{
    struct sigaction sa;
    memset(&sa, 0, sizeof sa);
    sa.sa_handler = on_sigsys;
    sigaction(SIGSYS, &sa, 0);
    prctl(PR_SET_NNP, 1, 0, 0, 0);
    if (install_nr_action(NR_PROBE, RET_KILL_THREAD, 0) != 0)
        return 90;
    syscall(NR_PROBE);
    return trapped ? 93 : 92;
}

static int body_strict_exit(void)
{
    int p[2];
    if (pipe(p) != 0)
        return 90;
    if (prctl(PR_SET_SECCOMP_NR, 1, 0, 0, 0) != 0)
        return 91;
    if (syscall(SYS_write, p[1], "x", 1) != 1)
        syscall(SYS_exit, 92);
    syscall(SYS_exit, 0);
    return 93;
}

static int body_strict_seccomp_call(void)
{
    int p[2];
    if (pipe(p) != 0)
        return 90;
    if (seccomp_call(SC_SET_MODE_STRICT, 0, 0) != 0)
        return 91;
    char c = 0;
    if (syscall(SYS_write, p[1], "x", 1) != 1 || syscall(SYS_read, p[0], &c, 1) != 1 || c != 'x')
        syscall(SYS_exit, 92);
    syscall(SYS_exit, 0);
    return 93;
}

static int body_strict_kill(void)
{
    if (prctl(PR_SET_SECCOMP_NR, 1, 0, 0, 0) != 0)
        return 91;
    syscall(NR_PROBE);
    syscall(SYS_exit, 92);
    return 93;
}

static int body_strict_conflicts(void)
{
    prctl(PR_SET_NNP, 1, 0, 0, 0);
    int bits = 0;
    errno = 0; if (seccomp_call(SC_SET_MODE_STRICT, 1, 0) == -1 && errno == EINVAL) bits |= 1;
    errno = 0; if (seccomp_call(SC_SET_MODE_STRICT, 0, (void *)8) == -1 && errno == EINVAL) bits |= 2;
    if (install_nr_action(NR_PROBE, RET_ALLOW, 0) != 0)
        return 90;
    errno = 0; if (seccomp_call(SC_SET_MODE_STRICT, 0, 0) == -1 && errno == EINVAL) bits |= 4;
    errno = 0; if (prctl(PR_SET_SECCOMP_NR, 1, 0, 0, 0) == -1 && errno == EINVAL) bits |= 8;
    return bits == 15 ? 0 : bits + 1;
}

static int body_inherit(void)
{
    prctl(PR_SET_NNP, 1, 0, 0, 0);
    if (install_nr_action(NR_PROBE, RET_ERRNO | EACCES, 0) != 0)
        return 90;
    pid_t pid = fork();
    if (pid == 0)
        _exit(probe_errno() == EACCES ? 0 : 91);
    int st = 0;
    waitpid(pid, &st, 0);
    return WIFEXITED(st) ? WEXITSTATUS(st) : 92;
}

static int body_stack(void)
{
    prctl(PR_SET_NNP, 1, 0, 0, 0);
    if (install_nr_action(NR_PROBE, RET_ERRNO | EACCES, 0) != 0)
        return 90;
    struct insn allow[] = { RET(RET_ALLOW) };
    if (install(allow, 1, 0) != 0)
        return 91;
    return probe_errno() == EACCES ? 0 : 92;
}

static int body_arg(void)
{
    prctl(PR_SET_NNP, 1, 0, 0, 0);
    struct insn f[] = {
        LD_ABS(OFF_NR), JEQ(SYS_dup, 0, 3),
        LD_ABS(OFF_ARG0), JEQ(900, 0, 1), RET(RET_ERRNO | EBADF), RET(RET_ALLOW),
    };
    if (install(f, 6, 0) != 0)
        return 90;
    errno = 0;
    long blocked = dup(900);
    int e1 = errno;
    int fd = dup(1);
    if (fd >= 0)
        close(fd);
    return blocked == -1 && e1 == EBADF && fd >= 0 ? 0 : 91;
}

static int body_arch(void)
{
    prctl(PR_SET_NNP, 1, 0, 0, 0);
    struct insn f[] = { LD_ABS(OFF_ARCH), JEQ(ARCH_X86_64, 1, 0), RET(RET_KILL_PROCESS), RET(RET_ALLOW) };
    if (install(f, 4, 0) != 0)
        return 90;
    return syscall(SYS_getpid) > 0 ? 0 : 91;
}

static int body_mode_get(void)
{
    prctl(PR_SET_NNP, 1, 0, 0, 0);
    if (prctl(PR_GET_SECCOMP_NR) != 0)
        return 90;
    if (install_nr_action(NR_PROBE, RET_ALLOW, 0) != 0)
        return 91;
    return prctl(PR_GET_SECCOMP_NR) == 2 ? 0 : 92;
}

static int body_alu(void)
{
    prctl(PR_SET_NNP, 1, 0, 0, 0);
    struct insn f[] = {
        LD_ABS(OFF_NR), { 0x04, 0, 0, 1 }, { 0x14, 0, 0, 1 }, { 0x24, 0, 0, 3 }, { 0x34, 0, 0, 3 },
        { 0xA4, 0, 0, 0x100 }, { 0xA4, 0, 0, 0x100 }, { 0x64, 0, 0, 2 }, { 0x74, 0, 0, 2 },
        { 0x54, 0, 0, 0xFFFF }, { 0x07, 0, 0, 0 }, { 0x00, 0, 0, 0 }, { 0x87, 0, 0, 0 },
        JEQ(NR_PROBE, 0, 1), RET(RET_ERRNO | EACCES), RET(RET_ALLOW),
    };
    if (install(f, 16, 0) != 0)
        return 90;
    return probe_errno() == EACCES && syscall(SYS_getpid) > 0 ? 0 : 91;
}

static int body_jset(void)
{
    prctl(PR_SET_NNP, 1, 0, 0, 0);
    struct insn f[] = {
        LD_ABS(OFF_NR), JEQ(NR_PROBE, 0, 3), { 0x45, 0, 1, 0x6E }, RET(RET_ERRNO | EBUSY),
        RET(RET_ALLOW), RET(RET_ALLOW),
    };
    if (install(f, 6, 0) != 0)
        return 90;
    return probe_errno() == EBUSY ? 0 : 91;
}

static int body_scratch(void)
{
    prctl(PR_SET_NNP, 1, 0, 0, 0);
    struct insn f[] = {
        { 0x00, 0, 0, NR_PROBE }, { 0x02, 0, 0, 3 }, LD_ABS(OFF_NR), { 0x07, 0, 0, 0 },
        { 0x00, 0, 0, 0 }, { 0x60, 0, 0, 3 }, { 0x1D, 0, 1, 0 },
        RET(RET_ERRNO | EBUSY), RET(RET_ALLOW),
    };
    if (install(f, 9, 0) != 0)
        return 90;
    return probe_errno() == EBUSY ? 0 : 91;
}

static void *thread_probe(void *arg)
{
    volatile int *go = arg;
    while (!*go)
        usleep(1000);
    return (void *)(long)probe_errno();
}

static int body_tsync(void)
{
    prctl(PR_SET_NNP, 1, 0, 0, 0);
    volatile int go = 0;
    pthread_t th;
    if (pthread_create(&th, 0, thread_probe, (void *)&go) != 0)
        return 90;
    if (install_nr_action(NR_PROBE, RET_ERRNO | EACCES, SC_FLAG_TSYNC) != 0)
        return 91;
    go = 1;
    void *res = 0;
    pthread_join(th, &res);
    return (long)res == EACCES ? 0 : 92;
}

static int body_no_tsync(void)
{
    prctl(PR_SET_NNP, 1, 0, 0, 0);
    volatile int go = 0;
    pthread_t th;
    if (pthread_create(&th, 0, thread_probe, (void *)&go) != 0)
        return 90;
    if (install_nr_action(NR_PROBE, RET_ERRNO | EACCES, 0) != 0)
        return 91;
    go = 1;
    void *res = 0;
    pthread_join(th, &res);
    return (long)res == 0 ? 0 : 92;
}

static int body_invalid_programs(void)
{
    prctl(PR_SET_NNP, 1, 0, 0, 0);
    struct insn no_ret[] = { LD_ABS(OFF_NR) };
    struct insn bad_jump[] = { JEQ(1, 5, 0), RET(RET_ALLOW) };
    struct insn bad_load[] = { LD_ABS(64), RET(RET_ALLOW) };
    struct insn unaligned[] = { LD_ABS(2), RET(RET_ALLOW) };
    struct insn div_zero[] = { { 0x34, 0, 0, 0 }, RET(RET_ALLOW) };
    struct insn byte_load[] = { { 0x30, 0, 0, 0 }, RET(RET_ALLOW) };
    struct insn mem_oob[] = { { 0x02, 0, 0, 16 }, RET(RET_ALLOW) };
    struct insn ok[] = { RET(RET_ALLOW) };
    int bits = 0;
    errno = 0; if (install(no_ret, 1, 0) == -1 && errno == EINVAL) bits |= 1;
    errno = 0; if (install(bad_jump, 2, 0) == -1 && errno == EINVAL) bits |= 2;
    errno = 0; if (install(bad_load, 2, 0) == -1 && errno == EINVAL) bits |= 4;
    errno = 0; if (install(unaligned, 2, 0) == -1 && errno == EINVAL) bits |= 8;
    errno = 0; if (install(div_zero, 2, 0) == -1 && errno == EINVAL) bits |= 16;
    errno = 0; if (install(byte_load, 2, 0) == -1 && errno == EINVAL) bits |= 32;
    errno = 0; if (install(mem_oob, 2, 0) == -1 && errno == EINVAL) bits |= 64;
    errno = 0; if (install(ok, 0, 0) == -1 && errno == EINVAL) bits |= 128;
    errno = 0; if (install(ok, 1, 0x80) == -1 && errno == EINVAL) bits |= 256;
    errno = 0; if (seccomp_call(SC_SET_MODE_FILTER, 0, 0) == -1 && errno == EFAULT) bits |= 512;
    errno = 0; if (seccomp_call(77, 0, 0) == -1 && errno == EINVAL) bits |= 1024;
    return bits == 2047 ? 0 : (bits & 0x7F) + 1;
}

static int body_too_long(void)
{
    prctl(PR_SET_NNP, 1, 0, 0, 0);
    static struct insn big[4097];
    for (int i = 0; i < 4097; i++) {
        big[i].code = 0x06;
        big[i].k = RET_ALLOW;
    }
    struct prog p = { 4097, {0, 0, 0}, big };
    errno = 0;
    long r4097 = seccomp_call(SC_SET_MODE_FILTER, 0, &p);
    int e1 = errno;
    p.len = 4096;
    long r4096 = seccomp_call(SC_SET_MODE_FILTER, 0, &p);
    return r4097 == -1 && e1 == EINVAL && r4096 == 0 ? 0 : 91;
}

static int body_unpriv_denied(void)
{
    if (setuid(1000) != 0)
        return 80;
    struct insn ok[] = { RET(RET_ALLOW) };
    errno = 0;
    long r = install(ok, 1, 0);
    return r == -1 && errno == EACCES ? 0 : 91;
}

static int body_exec_keeps(void)
{
    prctl(PR_SET_NNP, 1, 0, 0, 0);
    if (install_nr_action(NR_PROBE, RET_ERRNO | EACCES, 0) != 0)
        return 90;
    return probe_errno() == EACCES && syscall(SYS_getpid) > 0 ? 0 : 91;
}

static void check_exit(const char *name, int (*body)(void))
{
    int st = child_status(body);
    CHECK(name, WIFEXITED(st) && WEXITSTATUS(st) == 0, "status=0x%x code=%d", st, WIFEXITED(st) ? WEXITSTATUS(st) : -1);
}

int main(void)
{
    errno = 0;
    long avail = seccomp_call(SC_GET_ACTION_AVAIL, 0, &(uint32_t){ RET_ERRNO });
    CHECKC("action_avail_errno", avail == 0, "r=%ld", avail);
    errno = 0;
    avail = seccomp_call(SC_GET_ACTION_AVAIL, 0, &(uint32_t){ 0x12340000u });
    CHECK("action_avail_unknown", avail == -1 && errno == EOPNOTSUPP, "r=%ld errno=%d", avail, errno);
    errno = 0;
    CHECK("nnp_off_by_default", prctl(PR_GET_NNP, 0, 0, 0, 0) == 0, "errno=%d", errno);
    check_exit("unpriv_requires_nnp", body_unpriv_denied);
    CHECK("nnp_set", prctl(PR_SET_NNP, 1, 0, 0, 0) == 0 && prctl(PR_GET_NNP, 0, 0, 0, 0) == 1, "errno=%d", errno);
    errno = 0;
    CHECK("nnp_set_zero_rejected", prctl(PR_SET_NNP, 0, 0, 0, 0) == -1 && errno == EINVAL, "errno=%d", errno);
    CHECK("probe_unfiltered", probe_errno() == 0, "errno=%d", errno);
    check_exit("errno_action", body_errno);
    check_exit("other_syscall_allowed", body_other_allowed);
    {
        int st = child_status(body_kill);
        CHECK("kill_process", WIFSIGNALED(st), "status=0x%x", st);
    }
    check_exit("trap_delivers_sigsys", body_trap);
    check_exit("trap_siginfo_fields", body_trap_info);
    check_exit("trap_forced_when_blocked", body_trap_blocked);
    {
        int st = child_status(body_kill_thread_with_handler);
        CHECK("kill_thread_ignores_handler", WIFSIGNALED(st) && WTERMSIG(st) == SIGSYS, "status=0x%x", st);
    }
    check_exit("strict_mode_prctl_allows_core", body_strict_exit);
    check_exit("strict_mode_seccomp_call", body_strict_seccomp_call);
    {
        int st = child_status(body_strict_kill);
        CHECK("strict_mode_kills_other_syscall", WIFSIGNALED(st) && WTERMSIG(st) == SIGKILL, "status=0x%x", st);
    }
    check_exit("strict_mode_conflicts", body_strict_conflicts);
    check_exit("inherited_by_fork", body_inherit);
    check_exit("strictest_filter_wins", body_stack);
    check_exit("argument_match", body_arg);
    check_exit("arch_field", body_arch);
    check_exit("get_seccomp_mode", body_mode_get);
    check_exit("alu_chain", body_alu);
    check_exit("jset", body_jset);
    check_exit("scratch_memory", body_scratch);
    check_exit("invalid_programs", body_invalid_programs);
    check_exit("program_length_limit", body_too_long);
    check_exit("tsync_covers_threads", body_tsync);
    check_exit("no_tsync_other_thread_free", body_no_tsync);
    check_exit("exec_keeps_filter_state", body_exec_keeps);
    CHECK("parent_unaffected", probe_errno() == 0, "errno=%d", errno);
    return 0;
}
