/* /proc, /sys and the paths a big program expects. */
#define TNAME "procfs"
#include "t.h"
#include <dirent.h>
#include <fcntl.h>
#include <stdlib.h>
#include <sys/stat.h>
#include <sys/statfs.h>
#include <sys/mman.h>
#include <sys/wait.h>

static int slurp(const char *path, char *b, int n)
{
    int fd = open(path, O_RDONLY);
    if (fd < 0) return -1;
    int t = 0, r;
    while (t < n - 1 && (r = read(fd, b + t, n - 1 - t)) > 0) t += r;
    close(fd); b[t] = 0; return t;
}

int main(void)
{
    static char b[16384];
    int n;
    errno = 0; n = slurp("/proc/self/maps", b, sizeof b);
    CHECKC("self_maps_open", n > 0);
    if (n > 0) {
        CHECK("self_maps_has_lines", strchr(b, '-') && (strstr(b, "r-xp") || strstr(b, "r--p") || strstr(b, "rw-p")), "no rwx permission fields in: %.60s", b);
        void *m = mmap(0, 4096, PROT_READ | PROT_WRITE, MAP_PRIVATE | MAP_ANONYMOUS, -1, 0);
        char addr[24]; snprintf(addr, sizeof addr, "%lx-", (unsigned long)m);
        n = slurp("/proc/self/maps", b, sizeof b);
        CHECK("self_maps_lists_new_mapping", n > 0 && strstr(b, addr), "a fresh mapping at %p is not listed", m);
        CHECK("self_maps_names_libc", strstr(b, "ld-musl") || strstr(b, "libc"), "libc not named in maps");
        CHECK("self_maps_names_exe", strstr(b, "/bin/t_procfs"), "the program image is not named in maps");
        CHECK("self_maps_stack_or_heap_named", strstr(b, "[stack]") || strstr(b, "[heap]"), "no [stack]/[heap] marker");
    }
    errno = 0; n = slurp("/proc/stat", b, sizeof b);
    CHECKC("stat_open", n > 0);
    if (n > 0) {
        unsigned long long cu = 0, cn = 0, cs = 0, ci = 0;
        CHECK("stat_cpu_line", sscanf(b, "cpu %llu %llu %llu %llu", &cu, &cn, &cs, &ci) == 4, "first line is not a Linux cpu line: %.40s", b);
        const char *bt = strstr(b, "\nbtime ");
        CHECK("stat_btime", bt && strtoull(bt + 7, NULL, 10) > 1000000000ULL, "no plausible btime line in /proc/stat");
    }
    errno = 0; n = slurp("/proc/self/status", b, sizeof b);
    CHECKC("self_status_open", n > 0);
    if (n > 0) {
        CHECK("self_status_name", strstr(b, "Name:"), "no Name: line");
        CHECK("self_status_pid_threads", strstr(b, "Pid:") && strstr(b, "Threads:"), "no Pid:/Threads:");
        CHECK("self_status_vm", strstr(b, "VmRSS:") && strstr(b, "VmSize:"), "no VmRSS/VmSize");
    }
    errno = 0; n = slurp("/proc/self/stat", b, sizeof b);
    CHECKC("self_stat", n > 20);
    if (n > 20) { int pid = 0; sscanf(b, "%d", &pid); CHECK("self_stat_pid", pid == getpid(), "pid %d", pid); }
    errno = 0; n = slurp("/proc/self/cmdline", b, sizeof b);
    CHECKC("self_cmdline", n > 0);
    char l[256]; errno = 0; ssize_t ln = readlink("/proc/self/exe", l, sizeof l - 1);
    CHECKC("self_exe_readlink", ln > 0);
    if (ln > 0) { l[ln] = 0; CHECK("self_exe_is_this_program", strstr(l, "t_procfs") != 0, "exe -> %s", l); }
    errno = 0; DIR *d = opendir("/proc/self/fd");
    CHECKC("self_fd_dir", d != 0);
    if (d) { int cnt = 0; struct dirent *e; while ((e = readdir(d))) if (e->d_name[0] != '.') cnt++; closedir(d); CHECK("self_fd_lists_open_fds", cnt >= 3, "only %d entries", cnt); }
    errno = 0; n = slurp("/proc/cpuinfo", b, sizeof b);
    CHECKC("cpuinfo", n > 0);
    if (n > 0) {
        CHECK("cpuinfo_processor", strstr(b, "processor"), "no processor line");
        CHECK("cpuinfo_model_name", strstr(b, "model name"), "no model name");
        CHECK("cpuinfo_flags_sse2", strstr(b, "flags") && strstr(b, "sse2"), "no flags with sse2 (feature detection by text)");
    }
    errno = 0; n = slurp("/proc/meminfo", b, sizeof b);
    CHECKC("meminfo", n > 0);
    if (n > 0) { CHECK("meminfo_memtotal", strstr(b, "MemTotal:"), "no MemTotal"); CHECK("meminfo_memavailable", strstr(b, "MemAvailable:"), "no MemAvailable"); }
    errno = 0; n = slurp("/proc/stat", b, sizeof b); CHECKC("proc_stat", n > 0);
    errno = 0; n = slurp("/proc/uptime", b, sizeof b); CHECKC("proc_uptime", n > 0);
    errno = 0; n = slurp("/proc/loadavg", b, sizeof b); CHECKC("proc_loadavg", n > 0);
    errno = 0; n = slurp("/proc/version", b, sizeof b); CHECKC("proc_version", n > 0);
    errno = 0; n = slurp("/proc/self/limits", b, sizeof b); CHECKC("self_limits", n > 0);
    errno = 0; n = slurp("/proc/self/cgroup", b, sizeof b); CHECKC("self_cgroup", n >= 0);
    errno = 0; n = slurp("/proc/sys/kernel/random/uuid", b, sizeof b); CHECKC("random_uuid", n > 0);
    errno = 0; n = slurp("/proc/sys/vm/overcommit_memory", b, sizeof b); CHECKC("sysctl_overcommit", n > 0);
    errno = 0; n = slurp("/proc/sys/kernel/pid_max", b, sizeof b); CHECKC("sysctl_pid_max", n > 0);
    errno = 0; n = slurp("/sys/devices/system/cpu/online", b, sizeof b); CHECKC("sys_cpu_online", n > 0);
    errno = 0; n = slurp("/sys/devices/system/cpu/possible", b, sizeof b); CHECKC("sys_cpu_possible", n > 0);
    errno = 0; n = slurp("/sys/devices/system/cpu/cpu0/cache/index0/size", b, sizeof b); CHECKC("sys_cpu_cache", n > 0);
    {
        /* /sys cache view must say what the CPU says: leaf 4 (Intel) or 0x8000001D (AMD, TOPOEXT); no cache info = no index0 (nothing invented) */
        unsigned ma = 0, ea = 0, eb = 0, ec = 0, ed = 0, xa = 0, xc = 0, lf = 0;
        __asm__ volatile("cpuid" : "=a"(ma), "=b"(eb), "=c"(ec), "=d"(ed) : "a"(0), "c"(0));
        if (ma >= 4) { __asm__ volatile("cpuid" : "=a"(ea), "=b"(eb), "=c"(ec), "=d"(ed) : "a"(4), "c"(0)); if (ea & 31) lf = 4; }
        if (!lf) {
            __asm__ volatile("cpuid" : "=a"(xa), "=b"(eb), "=c"(xc), "=d"(ed) : "a"(0x80000000u), "c"(0));
            unsigned x1 = 0;
            __asm__ volatile("cpuid" : "=a"(x1), "=b"(eb), "=c"(xc), "=d"(ed) : "a"(0x80000001u), "c"(0));
            if (xa >= 0x8000001Du && ((xc >> 22) & 1)) { __asm__ volatile("cpuid" : "=a"(ea), "=b"(eb), "=c"(ec), "=d"(ed) : "a"(0x8000001Du), "c"(0)); if (ea & 31) lf = 0x8000001Du; }
        }
        struct stat cs; int has = stat("/sys/devices/system/cpu/cpu0/cache/index0", &cs) == 0;
        if (lf) {
            unsigned long sz = (unsigned long)((eb >> 22) + 1) * (((eb >> 12) & 1023) + 1) * ((eb & 4095) + 1) * (ec + 1ul);
            char exp[32]; snprintf(exp, sizeof exp, "%luK\n", sz / 1024);
            int m = slurp("/sys/devices/system/cpu/cpu0/cache/index0/size", b, sizeof b);
            CHECK("sys_cpu_cache_honest", m > 0 && !strcmp(b, exp), "size file '%s' expected '%s'", m > 0 ? b : "(none)", exp);
        } else {
            CHECK("sys_cpu_cache_honest", !has, "index0 exists but the CPU reports no cache info");
        }
        /* online: "0" or "0-N", matches the number of CPUs of /proc/cpuinfo */
        int m2 = slurp("/sys/devices/system/cpu/online", b, sizeof b);
        CHECK("sys_cpu_online_format", m2 > 0 && b[0] == '0' && (b[1] == '\n' || b[1] == '-'), "online='%s'", m2 > 0 ? b : "");
    }
    errno = 0; n = slurp("/sys/class/drm/card0/device/vendor", b, sizeof b); CHECKC("sys_drm", n > 0);

    /* paths */
    struct stat st; struct { const char *p; const char *name; int dir; } paths[] = {
        { "/tmp", "path_tmp", 1 }, { "/dev/shm", "path_dev_shm", 1 }, { "/etc/ssl", "path_etc_ssl", 1 }, { "/etc/ssl/certs", "path_etc_ssl_certs", 1 },
        { "/etc/passwd", "path_etc_passwd", 0 }, { "/etc/hosts", "path_etc_hosts", 0 }, { "/etc/resolv.conf", "path_etc_resolv_conf", 0 }, { "/etc/localtime", "path_etc_localtime", 0 },
        { "/etc/fonts/fonts.conf", "path_fontconfig", 0 }, { "/usr/share/fonts", "path_fonts", 1 }, { "/usr/share/zoneinfo", "path_zoneinfo", 1 },
        { "/dev/null", "path_dev_null", 0 }, { "/dev/zero", "path_dev_zero", 0 }, { "/dev/urandom", "path_dev_urandom", 0 }, { "/dev/random", "path_dev_random", 0 },
        { "/dev/tty", "path_dev_tty", 0 }, { "/dev/pts", "path_dev_pts", 1 }, { "/dev/dri", "path_dev_dri", 1 }, { "/run", "path_run", 1 }, { "/var/tmp", "path_var_tmp", 1 },
        { "/proc", "path_proc", 1 }, { "/sys", "path_sys", 1 }, { "/usr/lib", "path_usr_lib", 1 }, { "/lib", "path_lib", 1 }, { "/root", "path_home", 1 }, { "/etc/machine-id", "path_machine_id", 0 },
    };
    for (unsigned i = 0; i < sizeof paths / sizeof paths[0]; i++) {
        errno = 0; int r = stat(paths[i].p, &st);
        if (r == 0) { CHECK(paths[i].name, paths[i].dir ? S_ISDIR(st.st_mode) : 1, "%s exists but is not a directory", paths[i].p); }
        else GAP(paths[i].name, "stat(%s): errno %d", paths[i].p, errno);
    }
    /* /dev/shm must be writable and mappable shared (POSIX shm: shm_open uses it) */
    errno = 0; int fd = open("/dev/shm/ub_shm", O_RDWR | O_CREAT | O_TRUNC, 0600);
    CHECKC("shm_create", fd >= 0);
    if (fd >= 0) {
        errno = 0; int r = ftruncate(fd, 8192);
        CHECKC("shm_ftruncate", r == 0);
        char *m = mmap(0, 8192, PROT_READ | PROT_WRITE, MAP_SHARED, fd, 0);
        CHECKC("shm_mmap_shared", m != MAP_FAILED);
        if (m != MAP_FAILED) {
            m[100] = 42;
            pid_t k = fork(); if (k == 0) { _exit(m[100] == 42 ? 0 : 1); }
            int s; waitpid(k, &s, 0);
            char c = 0; (void)!pread(fd, &c, 1, 100);
            CHECK("shm_shared_with_file", c == 42, "write through the mapping not visible via read (%d)", c);
        }
        close(fd); unlink("/dev/shm/ub_shm");
    }
    /* LC-002: names, listing, reopen, O_EXCL, unlink drops the name, no create elsewhere in /dev */
    {
        errno = 0; int f1 = open("/dev/shm/ub_n1", O_RDWR | O_CREAT | O_EXCL, 0600);
        CHECKC("shm_name_create_excl", f1 >= 0);
        if (f1 >= 0) {
            (void)!ftruncate(f1, 4096);
            char *m1 = mmap(0, 4096, PROT_READ | PROT_WRITE, MAP_SHARED, f1, 0);
            if (m1 != MAP_FAILED) m1[7] = 77;
            errno = 0; int dup = open("/dev/shm/ub_n1", O_RDWR | O_CREAT | O_EXCL, 0600);
            CHECK("shm_name_excl_eexist", dup < 0 && errno == EEXIST, "dup=%d errno=%d", dup, errno);
            close(f1);
            int f2 = open("/dev/shm/ub_n1", O_RDWR);
            char *m2 = f2 >= 0 ? mmap(0, 4096, PROT_READ | PROT_WRITE, MAP_SHARED, f2, 0) : MAP_FAILED;
            CHECK("shm_name_reopen_same_object", m2 != MAP_FAILED && m2[7] == 77, "reopen sees %d", m2 != MAP_FAILED ? m2[7] : -1);
            struct stat st; int sr = f2 >= 0 ? fstat(f2, &st) : -1;
            CHECK("shm_name_size", sr == 0 && st.st_size == 4096, "size=%ld", sr == 0 ? (long)st.st_size : -1L);
            int seen = 0; DIR *d = opendir("/dev/shm");
            if (d) { struct dirent *e; while ((e = readdir(d))) if (!strcmp(e->d_name, "ub_n1")) seen = 1; closedir(d); }
            CHECK("shm_name_listed", seen, "ub_n1 not in readdir(/dev/shm)");
            errno = 0; int ur = unlink("/dev/shm/ub_n1");
            CHECKC("shm_name_unlink", ur == 0);
            errno = 0; int f3 = open("/dev/shm/ub_n1", O_RDWR);
            CHECK("shm_name_gone_after_unlink", f3 < 0 && errno == ENOENT, "f3=%d errno=%d", f3, errno);
            CHECK("shm_unlinked_object_lives", m2 != MAP_FAILED && m2[7] == 77, "mapping lost its data");
            if (f2 >= 0) close(f2);
        }
        errno = 0; int bad = open("/dev/ub_nope", O_RDWR | O_CREAT, 0600);
        CHECK("dev_create_elsewhere_eperm", bad < 0 && errno == EPERM, "bad=%d errno=%d", bad, errno);
        if (bad >= 0) { close(bad); unlink("/dev/ub_nope"); }
    }
    errno = 0; fd = memfd_create("ub", 0);
    CHECKC("memfd_create", fd >= 0);
    if (fd >= 0) { errno = 0; CHECKC("memfd_ftruncate", ftruncate(fd, 4096) == 0); char *m = mmap(0, 4096, PROT_READ | PROT_WRITE, MAP_SHARED, fd, 0); CHECKC("memfd_mmap", m != MAP_FAILED); }
    struct statfs sf; errno = 0; CHECKC("statfs_tmp", statfs("/tmp", &sf) == 0);
    errno = 0; CHECKC("statfs_root", statfs("/", &sf) == 0);
    return 0;
}
