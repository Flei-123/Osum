#define TNAME "procmore"
#include "t.h"
#include <fcntl.h>
#include <stdlib.h>
#include <sys/stat.h>

static const char *const readable_files[] = {
    "/proc/self/smaps", "/proc/self/smaps_rollup", "/proc/self/status", "/proc/self/stat", "/proc/self/statm",
    "/proc/self/maps", "/proc/self/limits", "/proc/self/io", "/proc/self/mountinfo", "/proc/self/mounts",
    "/proc/self/cgroup", "/proc/self/oom_score_adj", "/proc/self/oom_score", "/proc/self/auxv", "/proc/self/environ",
    "/proc/self/cmdline", "/proc/self/comm", "/proc/self/fdinfo/0", "/proc/self/sched", "/proc/self/schedstat",
    "/proc/self/personality", "/proc/self/wchan", "/proc/self/syscall", "/proc/self/timerslack_ns", "/proc/self/loginuid",
    "/proc/net/dev", "/proc/net/route", "/proc/net/tcp", "/proc/net/tcp6", "/proc/net/udp", "/proc/net/udp6",
    "/proc/net/unix", "/proc/net/if_inet6", "/proc/net/arp", "/proc/net/sockstat", "/proc/net/snmp",
    "/proc/net/netstat", "/proc/net/dev_mcast", "/proc/net/ipv6_route", "/proc/net/fib_trie", "/proc/net/raw",
    "/proc/net/packet", "/proc/net/protocols", "/proc/net/wireless",
    "/proc/modules", "/proc/iomem", "/proc/ioports", "/proc/zoneinfo", "/proc/pressure/cpu", "/proc/pressure/memory",
    "/proc/pressure/io", "/proc/sysvipc/shm", "/proc/sysvipc/sem", "/proc/sysvipc/msg",
    "/proc/sys/vm/overcommit_memory", "/proc/sys/vm/swappiness", "/proc/sys/vm/max_map_count",
    "/proc/sys/vm/dirty_ratio", "/proc/sys/vm/dirty_background_ratio", "/proc/sys/vm/min_free_kbytes",
    "/proc/sys/vm/vfs_cache_pressure", "/proc/sys/vm/overcommit_ratio", "/proc/sys/vm/mmap_min_addr",
    "/proc/sys/vm/page-cluster", "/proc/sys/vm/drop_caches", "/proc/sys/vm/panic_on_oom",
    "/proc/sys/kernel/pid_max", "/proc/sys/kernel/random/uuid", "/proc/sys/kernel/random/boot_id",
    "/proc/sys/kernel/random/entropy_avail", "/proc/sys/kernel/hostname", "/proc/sys/kernel/osrelease",
    "/proc/sys/kernel/ostype", "/proc/sys/kernel/version", "/proc/sys/kernel/threads-max",
    "/proc/sys/kernel/core_pattern", "/proc/sys/kernel/randomize_va_space", "/proc/sys/kernel/yama/ptrace_scope",
    "/proc/sys/kernel/unprivileged_userns_clone", "/proc/sys/kernel/printk", "/proc/sys/kernel/sched_child_runs_first",
    "/proc/sys/kernel/shmmax", "/proc/sys/kernel/sem", "/proc/sys/kernel/msgmax", "/proc/sys/kernel/domainname",
    "/proc/sys/kernel/perf_event_paranoid", "/proc/sys/kernel/kptr_restrict", "/proc/sys/kernel/tainted",
    "/proc/sys/kernel/pty/max", "/proc/sys/kernel/pty/nr", "/proc/sys/user/max_user_namespaces",
    "/proc/sys/fs/file-max", "/proc/sys/fs/file-nr", "/proc/sys/fs/nr_open", "/proc/sys/fs/inotify/max_user_watches",
    "/proc/sys/fs/inotify/max_user_instances", "/proc/sys/fs/inotify/max_queued_events", "/proc/sys/fs/pipe-max-size",
    "/proc/sys/fs/suid_dumpable", "/proc/sys/fs/aio-max-nr", "/proc/sys/fs/protected_hardlinks",
    "/proc/sys/net/core/somaxconn", "/proc/sys/net/core/rmem_max", "/proc/sys/net/core/wmem_max",
    "/proc/sys/net/ipv4/ip_local_port_range", "/proc/sys/net/ipv4/tcp_keepalive_time", "/proc/sys/net/ipv4/ip_forward",
    "/proc/sys/net/ipv4/tcp_syncookies", "/proc/sys/net/ipv6/conf/all/disable_ipv6",
    "/proc/cpuinfo", "/proc/meminfo", "/proc/version", "/proc/uptime", "/proc/loadavg", "/proc/stat", "/proc/vmstat",
    "/proc/mounts", "/proc/filesystems", "/proc/partitions", "/proc/diskstats", "/proc/devices", "/proc/interrupts",
    "/proc/cmdline", "/proc/swaps", "/proc/locks", "/proc/buddyinfo", "/proc/slabinfo", "/proc/kallsyms",
    "/proc/softirqs", "/proc/misc", "/proc/consoles", "/proc/crypto", "/proc/execdomains", "/proc/cgroups",
    "/proc/key-users", "/proc/keys", "/proc/pagetypeinfo", "/proc/timer_list", "/proc/sched_debug",
    "/sys/devices/system/cpu/online", "/sys/devices/system/cpu/possible", "/sys/devices/system/cpu/present",
    "/sys/devices/system/cpu/cpu0/topology/core_id", "/sys/devices/system/cpu/cpu0/cpufreq/scaling_cur_freq",
    "/sys/devices/system/node/online", "/sys/kernel/mm/transparent_hugepage/enabled",
    "/sys/kernel/mm/transparent_hugepage/hpage_pmd_size", "/sys/fs/cgroup/cgroup.controllers",
    "/sys/class/net/lo/address", "/sys/class/net/lo/operstate", "/sys/class/power_supply/BAT0/capacity",
    "/sys/devices/virtual/dmi/id/sys_vendor", "/sys/kernel/random/boot_id", "/sys/firmware/efi/fw_platform_size",
    "/dev/urandom", "/dev/random", "/dev/null", "/dev/zero", "/dev/full", "/dev/tty", "/dev/ptmx", "/dev/console",
    "/dev/fd/0", "/dev/stdin", "/dev/stdout", "/dev/stderr", "/dev/shm", "/dev/pts", "/dev/fuse", "/dev/kmsg",
    "/dev/mem", "/dev/loop-control", "/dev/net/tun", "/dev/dri/card0", "/dev/input/event0", "/dev/snd/controlC0",
    "/dev/rtc0", "/dev/cpu_dma_latency", "/dev/hugepages", "/dev/mqueue", "/dev/log",
    "/etc/passwd", "/etc/group", "/etc/hosts", "/etc/resolv.conf", "/etc/nsswitch.conf", "/etc/localtime",
    "/etc/os-release", "/etc/hostname", "/etc/machine-id", "/etc/shells", "/etc/protocols", "/etc/services",
    "/etc/ld.so.cache", "/etc/mtab", "/etc/fstab", "/etc/ssl/certs/ca-certificates.crt", "/etc/timezone",
    "/etc/host.conf", "/etc/gai.conf", "/etc/issue", "/etc/passwd-", "/etc/login.defs",
    "/usr/share/zoneinfo/UTC", "/usr/share/zoneinfo/Europe/Berlin", "/usr/lib/os-release", "/var/run", "/run",
    "/var/tmp", "/tmp", "/root", "/home", "/usr/bin/env", "/bin/sh", "/usr/bin/true", "/bin/true",
};

int main(void)
{
    size_t i;
    for (i = 0; i < sizeof readable_files / sizeof readable_files[0]; i++) {
        const char *path = readable_files[i];
        char name[160];
        snprintf(name, sizeof name, "%s", path + 1);
        char *c;
        for (c = name; *c; c++)
            if (*c == '/')
                *c = '_';
        struct stat st;
        errno = 0;
        if (stat(path, &st) != 0) {
            GAP(name, "stat errno=%d", errno);
            continue;
        }
        if (S_ISDIR(st.st_mode)) {
            PASS(name);
            continue;
        }
        errno = 0;
        int fd = open(path, O_RDONLY | O_NONBLOCK);
        if (fd < 0) {
            GAP(name, "open errno=%d", errno);
            continue;
        }
        char buf[64];
        errno = 0;
        ssize_t n = (S_ISCHR(st.st_mode) || S_ISSOCK(st.st_mode)) ? 0 : read(fd, buf, sizeof buf);
        close(fd);
        if (n < 0 && errno != EAGAIN && errno != EIO && errno != EINVAL && errno != EPERM && errno != ENOTTY)
            FAIL(name, "read errno=%d", errno);
        else
            PASS(name);
    }
    return 0;
}
