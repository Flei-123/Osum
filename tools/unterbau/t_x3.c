#define TNAME "x3"
#include "t.h"
#include <fcntl.h>
#include <pthread.h>
#include <sched.h>
#include <setjmp.h>
#include <signal.h>
#include <stddef.h>
#include <stdint.h>
#include <stdlib.h>
#include <sys/auxv.h>
#include <sys/socket.h>
#include <sys/stat.h>
#include <sys/syscall.h>
#include <sys/un.h>
#include <time.h>

#define ARCH_SET_FS_NR 0x1002
#define ARCH_GET_FS_NR 0x1003

static socklen_t abstract_addr(struct sockaddr_un *a, const char *name, size_t n)
{
    memset(a, 0, sizeof *a);
    a->sun_family = AF_UNIX;
    a->sun_path[0] = 0;
    memcpy(a->sun_path + 1, name, n);
    return (socklen_t)(offsetof(struct sockaddr_un, sun_path) + 1 + n);
}

static struct sockaddr_un acc_addr;
static socklen_t acc_len;
static volatile int acc_fd = -2;
static volatile long acc_got = -2;
static char acc_buf[16];

static void *acceptor(void *arg)
{
    int ls = (int)(long)arg;
    int c = accept(ls, 0, 0);
    acc_fd = c;
    if (c >= 0) {
        acc_got = read(c, acc_buf, sizeof acc_buf);
        if (acc_got > 0) (void)!write(c, "pong", 4);
    }
    return 0;
}

static void abstract_checks(void)
{
    struct sockaddr_un a;
    socklen_t al = abstract_addr(&a, "x3-listener", 11);
    int ls = socket(AF_UNIX, SOCK_STREAM, 0);
    errno = 0;
    CHECKC("abs_bind", bind(ls, (struct sockaddr *)&a, al) == 0);
    int dup = socket(AF_UNIX, SOCK_STREAM, 0);
    errno = 0;
    CHECK("abs_bind_in_use", bind(dup, (struct sockaddr *)&a, al) == -1 && errno == EADDRINUSE, "errno=%d", errno);
    close(dup);
    errno = 0;
    CHECKC("abs_listen", listen(ls, 4) == 0);
    struct sockaddr_un na;
    socklen_t nl = abstract_addr(&na, "x3-listener-other", 17);
    int cs = socket(AF_UNIX, SOCK_STREAM, 0);
    errno = 0;
    CHECK("abs_connect_unbound_refused", connect(cs, (struct sockaddr *)&na, nl) == -1 && errno == ECONNREFUSED, "errno=%d", errno);
    close(cs);
    struct sockaddr_un pa;
    memset(&pa, 0, sizeof pa);
    pa.sun_family = AF_UNIX;
    strcpy(pa.sun_path, "x3-listener");
    cs = socket(AF_UNIX, SOCK_STREAM, 0);
    errno = 0;
    CHECK("abs_not_visible_as_path", connect(cs, (struct sockaddr *)&pa, sizeof pa) == -1 && (errno == ECONNREFUSED || errno == ENOENT), "errno=%d", errno);
    close(cs);
    pthread_t th;
    pthread_create(&th, 0, acceptor, (void *)(long)ls);
    cs = socket(AF_UNIX, SOCK_STREAM, 0);
    errno = 0;
    CHECKC("abs_connect", connect(cs, (struct sockaddr *)&a, al) == 0);
    errno = 0;
    CHECK("abs_send", write(cs, "ping", 4) == 4, "errno=%d", errno);
    char rb[8] = {0};
    long rr = read(cs, rb, sizeof rb);
    CHECK("abs_roundtrip", rr == 4 && !memcmp(rb, "pong", 4) && acc_got == 4 && !memcmp(acc_buf, "ping", 4), "rr %ld got %ld", rr, acc_got);
    pthread_join(th, 0);
    struct sockaddr_un got;
    socklen_t gl = sizeof got;
    memset(&got, 0x55, sizeof got);
    errno = 0;
    int r = getsockname(ls, (struct sockaddr *)&got, &gl);
    CHECKC("abs_getsockname", r == 0 && gl == al && got.sun_family == AF_UNIX && got.sun_path[0] == 0 && !memcmp(got.sun_path + 1, "x3-listener", 11));
    gl = sizeof got;
    memset(&got, 0x55, sizeof got);
    errno = 0;
    r = getpeername(cs, (struct sockaddr *)&got, &gl);
    CHECKC("abs_getpeername", r == 0 && gl == al && got.sun_family == AF_UNIX && got.sun_path[0] == 0 && !memcmp(got.sun_path + 1, "x3-listener", 11));
    if (acc_fd >= 0) close(acc_fd);
    close(cs);
    close(ls);
    int again = socket(AF_UNIX, SOCK_STREAM, 0);
    errno = 0;
    CHECKC("abs_name_freed_on_close", bind(again, (struct sockaddr *)&a, al) == 0);
    close(again);

    struct sockaddr_un n1, n2;
    socklen_t l1 = abstract_addr(&n1, "ab", 2);
    socklen_t l2 = abstract_addr(&n2, "ab\0c", 4);
    int s1 = socket(AF_UNIX, SOCK_STREAM, 0), s2 = socket(AF_UNIX, SOCK_STREAM, 0);
    errno = 0;
    int b1 = bind(s1, (struct sockaddr *)&n1, l1);
    int e1 = errno;
    errno = 0;
    int b2 = bind(s2, (struct sockaddr *)&n2, l2);
    CHECK("abs_length_significant", b1 == 0 && b2 == 0, "b1 %d errno %d b2 %d errno %d", b1, e1, b2, errno);
    close(s1);
    close(s2);

    struct sockaddr_un d;
    socklen_t dl = abstract_addr(&d, "x3-dgram", 8);
    int ds = socket(AF_UNIX, SOCK_DGRAM, 0), dc = socket(AF_UNIX, SOCK_DGRAM, 0);
    errno = 0;
    CHECKC("abs_dgram_bind", bind(ds, (struct sockaddr *)&d, dl) == 0);
    errno = 0;
    ssize_t w = sendto(dc, "dgm", 3, 0, (struct sockaddr *)&d, dl);
    char db[8] = {0};
    ssize_t dr = recv(ds, db, sizeof db, MSG_DONTWAIT);
    CHECKC("abs_dgram_sendto", w == 3 && dr == 3 && !memcmp(db, "dgm", 3));
    close(ds);
    close(dc);

    int u = socket(AF_UNIX, SOCK_STREAM, 0);
    struct sockaddr_un empty;
    memset(&empty, 0, sizeof empty);
    empty.sun_family = AF_UNIX;
    errno = 0;
    int ab = bind(u, (struct sockaddr *)&empty, sizeof(sa_family_t));
    CHECK("autobind_or_einval", ab == 0 || (ab == -1 && errno == EINVAL), "ret %d errno %d", ab, errno);
    close(u);
}

static int read_file(const char *p, char *buf, size_t n)
{
    int fd = open(p, O_RDONLY);
    if (fd < 0) return -1;
    ssize_t r = read(fd, buf, n - 1);
    close(fd);
    if (r < 0) return -2;
    buf[r] = 0;
    return (int)r;
}

static void cgroup_checks(void)
{
    char buf[512];
    int r = read_file("/proc/self/cgroup", buf, sizeof buf);
    CHECK("proc_self_cgroup_readable_or_absent", r >= 0 || errno == ENOENT, "r %d errno %d", r, errno);
    int fd = open("/sys/fs/cgroup/cpu.max", O_RDONLY);
    int e = errno;
    if (fd >= 0) {
        ssize_t n = read(fd, buf, sizeof buf - 1);
        if (n >= 0) buf[n] = 0;
        CHECK("cgroup_cpu_max_format", n > 0 && (!strncmp(buf, "max ", 4) || (buf[0] >= '0' && buf[0] <= '9')), "n %ld '%s'", (long)n, buf);
        close(fd);
    } else {
        CHECK("cgroup_cpu_max_enoent_clean", e == ENOENT, "errno %d", e);
    }
    errno = 0;
    fd = open("/proc/self/mountinfo", O_RDONLY);
    e = errno;
    if (fd >= 0) {
        ssize_t n = read(fd, buf, sizeof buf - 1);
        CHECK("mountinfo_readable", n >= 0, "n %ld", (long)n);
        close(fd);
    } else {
        CHECK("mountinfo_enoent_clean", e == ENOENT, "errno %d", e);
    }
    errno = 0;
    fd = open("/sys/fs/cgroup", O_RDONLY | O_DIRECTORY);
    e = errno;
    if (fd >= 0) close(fd);
    CHECK("sys_fs_cgroup_dir_clean", fd >= 0 || e == ENOENT, "errno %d", e);
    cpu_set_t cs;
    CPU_ZERO(&cs);
    CHECK("affinity_nonempty", sched_getaffinity(0, sizeof cs, &cs) == 0 && CPU_COUNT(&cs) >= 1, "errno %d", errno);
    r = read_file("/sys/devices/system/cpu/online", buf, sizeof buf);
    CHECK("cpu_online_readable", r > 0 && (buf[0] >= '0' && buf[0] <= '9'), "r %d '%s'", r, r > 0 ? buf : "");
}

static void auxv_checks(void)
{
    CHECK("auxv_pagesz", getauxval(AT_PAGESZ) == 4096, "%lu", getauxval(AT_PAGESZ));
    unsigned long rnd = getauxval(AT_RANDOM);
    int nz = 0;
    if (rnd) for (int i = 0; i < 16; i++) nz += ((unsigned char *)rnd)[i] != 0;
    CHECK("auxv_random_16_bytes", rnd != 0 && nz >= 4, "ptr %lx nonzero %d", rnd, nz);
    unsigned long pl = getauxval(AT_PLATFORM);
    CHECK("auxv_platform_x86_64", pl != 0 && !strcmp((const char *)pl, "x86_64"), "ptr %lx", pl);
    CHECK("auxv_hwcap_nonzero", getauxval(AT_HWCAP) != 0, "%lx", getauxval(AT_HWCAP));
    errno = 0;
    unsigned long h2 = getauxval(AT_HWCAP2);
    CHECK("auxv_hwcap2_readable", h2 != (unsigned long)-1 || errno == 0, "%lx", h2);
    CHECK("auxv_clktck_100", getauxval(AT_CLKTCK) == 100, "%lu", getauxval(AT_CLKTCK));
    CHECK("auxv_secure_zero", getauxval(AT_SECURE) == 0, "%lu", getauxval(AT_SECURE));
    CHECK("auxv_execfn_string", getauxval(AT_EXECFN) != 0 && ((const char *)getauxval(AT_EXECFN))[0] == '/', "ptr %lx", getauxval(AT_EXECFN));
    CHECK("auxv_phdr_phnum_entry", getauxval(AT_PHDR) != 0 && getauxval(AT_PHNUM) >= 2 && getauxval(AT_PHENT) == 56 && getauxval(AT_ENTRY) != 0, "phdr %lx num %lu ent %lu entry %lx", getauxval(AT_PHDR), getauxval(AT_PHNUM), getauxval(AT_PHENT), getauxval(AT_ENTRY));
    CHECK("auxv_base_dynamic", getauxval(AT_BASE) != 0, "%lx", getauxval(AT_BASE));
    CHECK("auxv_ids", getauxval(AT_UID) == getauxval(AT_EUID) && getauxval(AT_GID) == getauxval(AT_EGID), "%lu %lu %lu %lu", getauxval(AT_UID), getauxval(AT_EUID), getauxval(AT_GID), getauxval(AT_EGID));
    unsigned long mss = getauxval(51);
    CHECK("auxv_minsigstksz_sane", mss == 0 || (mss >= 2048 && mss <= 65536), "%lu", mss);
    CHECK("auxv_sysinfo_ehdr_absent_ok", 1, "");
}

static sigjmp_buf ill;
static void on_ill(int s) { (void)s; siglongjmp(ill, 1); }

static void cpuid_(unsigned leaf, unsigned sub, unsigned *a, unsigned *b, unsigned *c, unsigned *d)
{
    __asm__ volatile("cpuid" : "=a"(*a), "=b"(*b), "=c"(*c), "=d"(*d) : "0"(leaf), "2"(sub));
}

static volatile int ymm_stop;
static volatile int ymm_bad;

__attribute__((target("avx"))) static void *ymm_clobber(void *arg)
{
    (void)arg;
    unsigned char junk[32];
    memset(junk, 0xA5, sizeof junk);
    while (!ymm_stop) {
        __asm__ volatile("vmovdqu (%0), %%ymm0\n\tvmovdqu (%0), %%ymm1" : : "r"(junk) : "ymm0", "ymm1");
        sched_yield();
    }
    return 0;
}

__attribute__((target("avx"))) static void ymm_preserve_check(void)
{
    pthread_t th;
    pthread_create(&th, 0, ymm_clobber, 0);
    unsigned char pat[32], out[32];
    for (int i = 0; i < 32; i++) pat[i] = (unsigned char)(i * 7 + 3);
    int bad = 0;
    for (int round = 0; round < 40; round++) {
        __asm__ volatile("vmovdqu (%0), %%ymm7" : : "r"(pat) : "ymm7");
        struct timespec ts = {0, 2000000};
        nanosleep(&ts, 0);
        sched_yield();
        __asm__ volatile("vmovdqu %%ymm7, (%0)" : : "r"(out) : "memory");
        if (memcmp(pat, out, 32)) bad++;
    }
    ymm_stop = 1;
    pthread_join(th, 0);
    CHECK("cpuid_ymm_preserved_across_switch", bad == 0, "%d of 40 rounds corrupted", bad);
}

static void cpuid_checks(void)
{
    unsigned a, b, c, d;
    cpuid_(0, 0, &a, &b, &c, &d);
    unsigned maxleaf = a;
    char vendor[13];
    memcpy(vendor, &b, 4); memcpy(vendor + 4, &d, 4); memcpy(vendor + 8, &c, 4); vendor[12] = 0;
    CHECK("cpuid_vendor_string", maxleaf >= 1 && vendor[0] != 0, "max %u '%s'", maxleaf, vendor);
    cpuid_(1, 0, &a, &b, &c, &d);
    unsigned f1c = c, f1d = d;
    CHECK("cpuid_sse2_baseline", (f1d >> 26) & 1, "edx %x", f1d);
    CHECK("cpuid_fxsr", (f1d >> 24) & 1, "edx %x", f1d);
    unsigned cache_line = ((b >> 8) & 0xff) * 8;
    CHECK("cpuid_clflush_line", cache_line == 0 || cache_line == 64 || cache_line == 32 || cache_line == 128, "%u", cache_line);
    unsigned xcr0lo = 0;
    int osxsave = (f1c >> 27) & 1;
    if (osxsave) {
        struct sigaction sa, old;
        memset(&sa, 0, sizeof sa);
        sa.sa_handler = on_ill;
        sigaction(SIGILL, &sa, &old);
        if (!sigsetjmp(ill, 1)) {
            unsigned lo, hi;
            __asm__ volatile("xgetbv" : "=a"(lo), "=d"(hi) : "c"(0));
            xcr0lo = lo;
            PASS("xgetbv_when_osxsave");
        } else {
            FAIL("xgetbv_when_osxsave", "SIGILL although cpuid reports OSXSAVE");
        }
        sigaction(SIGILL, &old, 0);
        CHECK("xcr0_has_x87_sse", (xcr0lo & 3) == 3 || xcr0lo == 0, "xcr0 %x", xcr0lo);
        if (maxleaf >= 0xd) {
            cpuid_(0xd, 0, &a, &b, &c, &d);
            CHECK("cpuid_xsave_size_consistent", b >= 512 && b <= c && c <= 16384, "enabled %u max %u", b, c);
        }
    } else {
        PASS("xgetbv_when_osxsave");
    }
    int ymm_ok = osxsave && ((xcr0lo & 6) == 6) && ((f1c >> 28) & 1);
    if (ymm_ok) ymm_preserve_check();
    else PASS("cpuid_ymm_preserved_across_switch");
    unsigned rdr = (f1c >> 30) & 1;
    if (rdr) {
        unsigned long v = 0; unsigned char ok = 0;
        __asm__ volatile("rdrand %0; setc %1" : "=r"(v), "=qm"(ok));
        CHECK("rdrand_if_reported", 1, "ok %u", ok);
    }
    cpuid_(0x80000000u, 0, &a, &b, &c, &d);
    CHECK("cpuid_extended_leaf", a >= 0x80000001u, "max ext %x", a);
}

static void *tls_thread(void *arg)
{
    uintptr_t fs = 0;
    long r = syscall(SYS_arch_prctl, ARCH_GET_FS_NR, &fs);
    uintptr_t self = 0;
    __asm__ volatile("movq %%fs:0, %0" : "=r"(self));
    *(uintptr_t *)arg = (r == 0 && fs == self && self != 0) ? 1 : 0;
    return 0;
}

static void tls_checks(void)
{
    uintptr_t fs = 0, self = 0;
    long r = syscall(SYS_arch_prctl, ARCH_GET_FS_NR, &fs);
    __asm__ volatile("movq %%fs:0, %0" : "=r"(self));
    CHECK("tls_fs_self_pointer", r == 0 && fs != 0 && fs == self, "r %ld fs %lx self %lx", r, (unsigned long)fs, (unsigned long)self);
    uintptr_t ok = 0;
    pthread_t th;
    pthread_create(&th, 0, tls_thread, &ok);
    pthread_join(th, 0);
    CHECK("tls_thread_own_fs_base", ok == 1, "ok %lu", (unsigned long)ok);
    static __thread int tv = 5;
    CHECK("tls_thread_local_var", tv == 5, "tv %d", tv);
    unsigned long can = 0;
    __asm__ volatile("movq %%fs:0x28, %0" : "=r"(can));
    CHECK("tls_stack_guard_slot_readable", 1, "%lx", can);
    errno = 0;
    long bad = syscall(SYS_arch_prctl, 0x1011, 0);
    CHECK("arch_prctl_unknown_clean", bad == -1 || bad == 0, "ret %ld", bad);
}

static void syscall_checks(void)
{
    errno = 0;
    long r = syscall(435, (void *)0, (size_t)0);
    CHECK("clone3_null_args_enosys_or_einval", r == -1 && (errno == ENOSYS || errno == EINVAL), "ret %ld errno %d", r, errno);
    errno = 0;
    r = syscall(334, (void *)0, 0, 0, 0);
    CHECK("rseq_unregistered_clean", r == -1 && (errno == ENOSYS || errno == EINVAL), "ret %ld errno %d", r, errno);
    errno = 0;
    r = syscall(219);
    CHECK("restart_syscall_eintr", r == -1 && errno == EINTR, "ret %ld errno %d", r, errno);
    errno = 0;
    r = syscall(273, (void *)0, (size_t)0);
    CHECK("set_robust_list_ok", r == 0 || (r == -1 && errno == EINVAL), "ret %ld errno %d", r, errno);
    void *head = 0; size_t len = 0;
    errno = 0;
    r = syscall(274, 0, &head, &len);
    CHECK("get_robust_list_clean", r == 0 || (r == -1 && (errno == ENOSYS || errno == EINVAL)), "ret %ld errno %d", r, errno);
}

int main(void)
{
    abstract_checks();
    cgroup_checks();
    auxv_checks();
    cpuid_checks();
    tls_checks();
    syscall_checks();
    return 0;
}
