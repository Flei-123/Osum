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
        CHECK("self_maps_stack_or_heap_named", strstr(b, "[stack]") || strstr(b, "[heap]"), "no [stack]/[heap] marker");
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
    errno = 0; fd = memfd_create("ub", 0);
    CHECKC("memfd_create", fd >= 0);
    if (fd >= 0) { errno = 0; CHECKC("memfd_ftruncate", ftruncate(fd, 4096) == 0); char *m = mmap(0, 4096, PROT_READ | PROT_WRITE, MAP_SHARED, fd, 0); CHECKC("memfd_mmap", m != MAP_FAILED); }
    struct statfs sf; errno = 0; CHECKC("statfs_tmp", statfs("/tmp", &sf) == 0);
    errno = 0; CHECKC("statfs_root", statfs("/", &sf) == 0);
    return 0;
}
