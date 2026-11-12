#define TNAME "vdso"
#include "t.h"
#include <elf.h>
#include <stdint.h>
#include <stdlib.h>
#include <sys/auxv.h>
#include <sys/syscall.h>
#include <sys/time.h>
#include <sys/wait.h>
#include <time.h>

#define SPEED_LOOPS 20000
#define MONO_LOOPS 200000
#define NS_PER_SEC 1000000000L
#define SKEW_NS 50000000L
#define SET_AHEAD_SECS 7200

typedef int (*cgt_fn)(clockid_t, struct timespec *);
typedef int (*gtod_fn)(struct timeval *, void *);
typedef long (*time_fn)(long *);

static const Elf64_Ehdr *base;
static cgt_fn vdso_cgt;
static gtod_fn vdso_gtod;
static time_fn vdso_time;

static long ns_of(const struct timespec *t) { return t->tv_sec * NS_PER_SEC + t->tv_nsec; }

static long raw_ns(clockid_t clk)
{
    struct timespec t;
    if (syscall(SYS_clock_gettime, clk, &t) != 0) return -1;
    return ns_of(&t);
}

static void *lookup(const char *name)
{
    const Elf64_Phdr *ph = (const void *)((const char *)base + base->e_phoff);
    uintptr_t load = 0;
    const Elf64_Dyn *dyn = 0;
    for (int i = 0; i < base->e_phnum; i++) {
        if (ph[i].p_type == PT_LOAD) load = (uintptr_t)base + ph[i].p_offset - ph[i].p_vaddr;
        if (ph[i].p_type == PT_DYNAMIC) dyn = (const void *)((const char *)base + ph[i].p_offset);
    }
    if (!dyn) return 0;
    const Elf64_Sym *sym = 0;
    const char *str = 0;
    const uint32_t *hash = 0;
    for (; dyn->d_tag != DT_NULL; dyn++) {
        if (dyn->d_tag == DT_SYMTAB) sym = (const void *)(load + dyn->d_un.d_ptr);
        if (dyn->d_tag == DT_STRTAB) str = (const void *)(load + dyn->d_un.d_ptr);
        if (dyn->d_tag == DT_HASH) hash = (const void *)(load + dyn->d_un.d_ptr);
    }
    if (!sym || !str || !hash) return 0;
    for (uint32_t i = 0; i < hash[1]; i++)
        if (sym[i].st_shndx && sym[i].st_value && strcmp(str + sym[i].st_name, name) == 0)
            return (void *)(load + sym[i].st_value);
    return 0;
}

static void locate(void)
{
    unsigned long at = getauxval(AT_SYSINFO_EHDR);
    CHECK("auxv_present", at != 0, "AT_SYSINFO_EHDR=0");
    if (!at) return;
    base = (const void *)at;
    CHECK("elf_magic", memcmp(base->e_ident, ELFMAG, SELFMAG) == 0, "bad magic");
    vdso_cgt = lookup("__vdso_clock_gettime");
    vdso_gtod = lookup("__vdso_gettimeofday");
    vdso_time = lookup("__vdso_time");
    CHECK("symbols", vdso_cgt && vdso_gtod && vdso_time, "cgt=%p gtod=%p time=%p", (void *)vdso_cgt, (void *)vdso_gtod, (void *)vdso_time);
}

static void agreement(void)
{
    if (!vdso_cgt) return;
    clockid_t clocks[] = { CLOCK_MONOTONIC, CLOCK_REALTIME, CLOCK_BOOTTIME, CLOCK_MONOTONIC_RAW, CLOCK_REALTIME_COARSE, CLOCK_MONOTONIC_COARSE };
    const char *names[] = { "mono_agrees", "real_agrees", "boot_agrees", "raw_agrees", "realcoarse_agrees", "monocoarse_agrees" };
    for (int i = 0; i < 6; i++) {
        struct timespec t = {0, 0};
        long before = raw_ns(clocks[i]);
        int rc = vdso_cgt(clocks[i], &t);
        long after = raw_ns(clocks[i]);
        long v = ns_of(&t);
        CHECK(names[i], rc == 0 && v >= before - SKEW_NS && v <= after + SKEW_NS, "rc=%d v=%ld before=%ld after=%ld", rc, v, before, after);
    }
}

static void libc_path(void)
{
    struct timespec a, b;
    long before = raw_ns(CLOCK_MONOTONIC);
    int rc = clock_gettime(CLOCK_MONOTONIC, &a);
    long after = raw_ns(CLOCK_MONOTONIC);
    CHECK("libc_mono", rc == 0 && ns_of(&a) >= before - SKEW_NS && ns_of(&a) <= after + SKEW_NS, "rc=%d", rc);
    struct timeval tv;
    struct timespec rt;
    gettimeofday(&tv, 0);
    clock_gettime(CLOCK_REALTIME, &rt);
    long diff = (tv.tv_sec * NS_PER_SEC + tv.tv_usec * 1000L) - ns_of(&rt);
    CHECK("libc_gettimeofday", diff > -SKEW_NS && diff < SKEW_NS, "diff=%ld", diff);
    long secs = (long)time(0);
    CHECK("libc_time", secs >= rt.tv_sec - 1 && secs <= rt.tv_sec + 1, "time=%ld real=%ld", secs, (long)rt.tv_sec);
    errno = 0;
    CHECK("libc_bad_clock", clock_gettime((clockid_t)99, &b) == -1 && errno == EINVAL, "errno=%d", errno);
}

static void direct_variants(void)
{
    if (!vdso_gtod || !vdso_time || !vdso_cgt) return;
    struct timeval tv;
    struct timespec rt;
    int rc = vdso_gtod(&tv, 0);
    vdso_cgt(CLOCK_REALTIME, &rt);
    long diff = (tv.tv_sec * NS_PER_SEC + tv.tv_usec * 1000L) - ns_of(&rt);
    CHECK("gtod_matches", rc == 0 && diff > -SKEW_NS && diff < SKEW_NS && tv.tv_usec >= 0 && tv.tv_usec < 1000000, "rc=%d diff=%ld", rc, diff);
    long out = 0;
    long r = vdso_time(&out);
    CHECK("time_matches", r == out && r >= rt.tv_sec - 1 && r <= rt.tv_sec + 1, "r=%ld out=%ld real=%ld", r, out, (long)rt.tv_sec);
    CHECK("time_null", vdso_time(0) >= rt.tv_sec - 1, "null arg");
    struct timespec t;
    long bad = vdso_cgt((clockid_t)99, &t);
    CHECK("bad_clock_einval", bad == -EINVAL, "rc=%ld", bad);
}

static void monotonic(void)
{
    if (!vdso_cgt) return;
    struct timespec t;
    long prev = 0;
    long back = 0;
    for (int i = 0; i < MONO_LOOPS; i++) {
        vdso_cgt(CLOCK_MONOTONIC, &t);
        long v = ns_of(&t);
        if (v < prev) back++;
        prev = v;
    }
    CHECK("monotonic_never_back", back == 0, "backwards=%ld", back);
}

static long timed(int via_vdso)
{
    struct timespec t, a, b;
    clock_gettime(CLOCK_MONOTONIC, &a);
    for (int i = 0; i < SPEED_LOOPS; i++) {
        if (via_vdso) vdso_cgt(CLOCK_MONOTONIC, &t);
        else syscall(SYS_clock_gettime, CLOCK_MONOTONIC, &t);
    }
    clock_gettime(CLOCK_MONOTONIC, &b);
    return (ns_of(&b) - ns_of(&a)) / SPEED_LOOPS;
}

static void speed(void)
{
    if (!vdso_cgt) return;
    long sys_ns = timed(0);
    long vdso_ns = timed(1);
    CHECK("faster_than_syscall", vdso_ns * 2 < sys_ns, "vdso=%ldns syscall=%ldns", vdso_ns, sys_ns);
    t_emit("cost", "PASS", "vdso=%ldns syscall=%ldns", vdso_ns, sys_ns);
}

static void inheritance(void)
{
    if (!vdso_cgt) return;
    pid_t p = fork();
    if (p == 0) {
        struct timespec t;
        _exit(vdso_cgt(CLOCK_MONOTONIC, &t) == 0 && t.tv_sec >= 0 ? 0 : 1);
    }
    int st = 0;
    waitpid(p, &st, 0);
    CHECK("fork_child_uses_vdso", WIFEXITED(st) && WEXITSTATUS(st) == 0, "status=%d", st);
}

static void settime(void)
{
    if (!vdso_cgt) return;
    struct timespec orig, target, got;
    vdso_cgt(CLOCK_REALTIME, &orig);
    target = orig;
    target.tv_sec += SET_AHEAD_SECS;
    errno = 0;
    if (clock_settime(CLOCK_REALTIME, &target) != 0) {
        GAP("settime_visible", "clock_settime errno=%d", errno);
        return;
    }
    vdso_cgt(CLOCK_REALTIME, &got);
    long moved = got.tv_sec - orig.tv_sec;
    CHECK("settime_visible", moved >= SET_AHEAD_SECS - 1 && moved <= SET_AHEAD_SECS + 2, "moved=%ld", moved);
    struct timespec back;
    clock_gettime(CLOCK_REALTIME, &back);
    back.tv_sec -= SET_AHEAD_SECS;
    clock_settime(CLOCK_REALTIME, &back);
    vdso_cgt(CLOCK_REALTIME, &got);
    moved = got.tv_sec - orig.tv_sec;
    CHECK("settime_restored", moved >= -1 && moved <= 3, "moved=%ld", moved);
}

int main(void)
{
    locate();
    agreement();
    libc_path();
    direct_variants();
    monotonic();
    speed();
    inheritance();
    settime();
    return 0;
}
