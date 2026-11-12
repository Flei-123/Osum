#define TNAME "abiwide"
#include "t.h"
#include <fcntl.h>
#include <net/if.h>
#include <signal.h>
#include <stdlib.h>
#include <sys/ioctl.h>
#include <sys/prctl.h>
#include <sys/socket.h>
#include <sys/stat.h>
#include <sys/syscall.h>
#include <termios.h>

#define COUNT(a) (sizeof(a) / sizeof((a)[0]))

static const char *readable[] = {
    "/proc/self/environ", "/proc/self/comm", "/proc/self/auxv", "/proc/self/smaps",
    "/proc/self/smaps_rollup", "/proc/self/statm", "/proc/self/io", "/proc/self/oom_score_adj",
    "/proc/self/oom_score", "/proc/self/mounts", "/proc/self/sched", "/proc/self/wchan",
    "/proc/self/syscall", "/proc/self/personality", "/proc/self/cpuset", "/proc/self/loginuid",
    "/proc/self/timerslack_ns", "/proc/self/task/1/comm", "/proc/self/net/dev",
    "/proc/mounts", "/proc/filesystems", "/proc/cmdline", "/proc/swaps", "/proc/vmstat",
    "/proc/diskstats", "/proc/partitions", "/proc/interrupts", "/proc/devices", "/proc/locks",
    "/proc/kallsyms", "/proc/modules", "/proc/iomem", "/proc/ioports", "/proc/zoneinfo",
    "/proc/buddyinfo", "/proc/pressure/cpu", "/proc/pressure/memory", "/proc/pressure/io",
    "/proc/crypto", "/proc/sysvipc/shm", "/proc/sysvipc/sem", "/proc/sysvipc/msg",
    "/proc/consoles", "/proc/misc", "/proc/softirqs", "/proc/timer_list", "/proc/schedstat",
    "/proc/1/stat", "/proc/1/cmdline", "/proc/1/status",
    "/proc/sys/kernel/hostname", "/proc/sys/kernel/osrelease", "/proc/sys/kernel/ostype",
    "/proc/sys/kernel/version", "/proc/sys/kernel/domainname", "/proc/sys/kernel/threads-max",
    "/proc/sys/kernel/ngroups_max", "/proc/sys/kernel/overflowuid", "/proc/sys/kernel/core_pattern",
    "/proc/sys/kernel/randomize_va_space", "/proc/sys/kernel/random/boot_id",
    "/proc/sys/kernel/random/entropy_avail", "/proc/sys/kernel/printk", "/proc/sys/kernel/kptr_restrict",
    "/proc/sys/kernel/dmesg_restrict", "/proc/sys/kernel/perf_event_paranoid",
    "/proc/sys/kernel/yama/ptrace_scope", "/proc/sys/kernel/sched_rt_runtime_us",
    "/proc/sys/kernel/shmmax", "/proc/sys/kernel/sem", "/proc/sys/kernel/msgmax",
    "/proc/sys/kernel/pty/max", "/proc/sys/kernel/pty/nr", "/proc/sys/kernel/tainted",
    "/proc/sys/kernel/panic", "/proc/sys/kernel/nmi_watchdog", "/proc/sys/kernel/keys/maxkeys",
    "/proc/sys/vm/max_map_count", "/proc/sys/vm/swappiness", "/proc/sys/vm/overcommit_ratio",
    "/proc/sys/vm/mmap_min_addr", "/proc/sys/vm/dirty_ratio", "/proc/sys/vm/min_free_kbytes",
    "/proc/sys/vm/vfs_cache_pressure", "/proc/sys/vm/page-cluster",
    "/proc/sys/fs/file-max", "/proc/sys/fs/file-nr", "/proc/sys/fs/nr_open",
    "/proc/sys/fs/inotify/max_user_watches", "/proc/sys/fs/inotify/max_user_instances",
    "/proc/sys/fs/inotify/max_queued_events", "/proc/sys/fs/pipe-max-size",
    "/proc/sys/fs/epoll/max_user_watches", "/proc/sys/fs/mqueue/msg_max",
    "/proc/sys/fs/protected_symlinks", "/proc/sys/fs/suid_dumpable",
    "/proc/sys/net/core/somaxconn", "/proc/sys/net/core/rmem_max", "/proc/sys/net/core/wmem_max",
    "/proc/sys/net/ipv4/ip_local_port_range", "/proc/sys/net/ipv4/ip_forward",
    "/proc/sys/net/ipv4/tcp_fin_timeout", "/proc/sys/net/ipv4/tcp_keepalive_time",
    "/proc/sys/net/ipv4/tcp_rmem", "/proc/sys/net/ipv4/tcp_wmem", "/proc/sys/net/ipv6/conf/all/disable_ipv6",
    "/proc/net/tcp", "/proc/net/tcp6", "/proc/net/udp", "/proc/net/udp6", "/proc/net/unix",
    "/proc/net/route", "/proc/net/arp", "/proc/net/if_inet6", "/proc/net/sockstat",
    "/proc/net/snmp", "/proc/net/netstat", "/proc/net/raw", "/proc/net/fib_trie",
    "/proc/net/dev_snmp6", "/proc/net/ipv6_route", "/proc/net/protocols",
    "/sys/devices/system/cpu/present", "/sys/devices/system/cpu/kernel_max",
    "/sys/devices/system/cpu/cpu0/topology/core_id", "/sys/devices/system/cpu/cpu0/topology/physical_package_id",
    "/sys/devices/system/cpu/cpu0/topology/thread_siblings_list",
    "/sys/devices/system/cpu/cpu0/cpufreq/scaling_cur_freq", "/sys/devices/system/cpu/cpu0/online",
    "/sys/devices/system/node/online", "/sys/devices/system/memory/block_size_bytes",
    "/sys/kernel/mm/transparent_hugepage/enabled", "/sys/kernel/mm/hugepages/hugepages-2048kB/nr_hugepages",
    "/sys/class/net/lo/address", "/sys/class/net/lo/operstate", "/sys/class/net/lo/mtu",
    "/sys/class/net/lo/flags", "/sys/class/net/lo/ifindex", "/sys/class/net/lo/type",
    "/sys/class/dmi/id/sys_vendor", "/sys/devices/virtual/dmi/id/product_name",
    "/sys/class/power_supply", "/sys/class/thermal", "/sys/class/tty", "/sys/class/input",
    "/sys/class/backlight", "/sys/class/block", "/sys/block", "/sys/bus/pci/devices",
    "/sys/bus/usb/devices", "/sys/fs/cgroup/cgroup.controllers", "/sys/fs/cgroup/cgroup.procs",
    "/sys/kernel/random/boot_id", "/sys/kernel/security", "/sys/firmware/efi",
    "/sys/module", "/sys/dev/char", "/sys/dev/block",
    "/dev/full", "/dev/console", "/dev/stdin", "/dev/stdout", "/dev/stderr", "/dev/fd",
    "/dev/tty0", "/dev/loop-control", "/dev/fuse", "/dev/net/tun", "/dev/input/event0",
    "/dev/snd/controlC0", "/dev/kvm", "/dev/rtc0", "/dev/hwrng", "/dev/log", "/dev/kmsg",
    "/dev/mem", "/dev/port", "/dev/mqueue", "/dev/pts/ptmx", "/dev/vga_arbiter",
    "/etc/os-release", "/etc/group", "/etc/hostname", "/etc/nsswitch.conf", "/etc/services",
    "/etc/protocols", "/etc/shells", "/etc/ld.so.cache", "/etc/mtab", "/etc/profile",
    "/etc/issue", "/etc/timezone", "/etc/ssl/certs/ca-certificates.crt", "/etc/ssl/openssl.cnf",
    "/etc/inputrc", "/etc/host.conf", "/etc/gai.conf", "/etc/login.defs", "/etc/environment",
    "/etc/fstab", "/etc/mime.types", "/etc/ethertypes", "/etc/rpc",
    "/usr/share/zoneinfo/UTC", "/usr/share/zoneinfo/Europe/Berlin", "/usr/share/zoneinfo/zone.tab",
    "/usr/lib/os-release", "/lib/modules", "/usr/bin/env", "/bin/sh", "/usr/bin/sh",
    "/tmp", "/var/tmp", "/run", "/var/run", "/var/log", "/root", "/home", "/usr/local/bin",
    "/usr/share/terminfo", "/usr/share/X11/xkb", "/usr/share/mime", "/usr/share/icons",
};

static void probe_paths(void)
{
    size_t i;
    for (i = 0; i < COUNT(readable); i++) {
        char name[160];
        snprintf(name, sizeof name, "path%s", readable[i]);
        int fd = open(readable[i], O_RDONLY | O_NONBLOCK);
        if (fd < 0) {
            GAP(name, "errno=%d", errno);
            continue;
        }
        struct stat st;
        if (fstat(fd, &st) < 0) {
            FAIL(name, "fstat errno=%d", errno);
            close(fd);
            continue;
        }
        if (S_ISREG(st.st_mode)) {
            char b[64];
            ssize_t n = read(fd, b, sizeof b);
            if (n < 0) {
                FAIL(name, "read errno=%d", errno);
                close(fd);
                continue;
            }
        }
        PASS(name);
        close(fd);
    }
}

struct prctl_probe {
    const char *name;
    long option;
    long arg2;
};

static const struct prctl_probe prctls[] = {
    {"get_pdeathsig", 2, 0}, {"get_dumpable", 3, 0}, {"get_keepcaps", 7, 0}, {"set_keepcaps", 8, 0},
    {"get_endian", 19, 0}, {"get_seccomp", 21, 0}, {"capbset_read", 23, 0}, {"get_timerslack", 30, 0},
    {"set_timerslack", 29, 50000}, {"set_child_subreaper", 36, 1}, {"get_child_subreaper", 37, 0},
    {"get_tid_address", 40, 0}, {"get_thp_disable", 42, 0}, {"set_thp_disable", 41, 0},
    {"get_no_new_privs", 39, 0}, {"get_speculation", 52, 0}, {"get_tsc", 25, 0},
    {"set_ptracer", 0x59616d61, -1}, {"get_securebits", 27, 0}, {"get_fpexc", 11, 0},
    {"get_unalign", 5, 0}, {"get_timing", 13, 0}, {"mce_kill_get", 34, 0},
    {"get_io_flusher", 58, 0}, {"get_auxv_trailer", 0, 0},
};

static void probe_prctl(void)
{
    size_t i;
    for (i = 0; i < COUNT(prctls); i++) {
        char name[96];
        snprintf(name, sizeof name, "prctl_%s", prctls[i].name);
        if (prctls[i].option == 0) {
            continue;
        }
        errno = 0;
        long r = syscall(SYS_prctl, prctls[i].option, prctls[i].arg2, 0L, 0L, 0L);
        if (r != -1) {
            PASS(name);
        } else if (errno == EINVAL || errno == ENOSYS) {
            GAP(name, "errno=%d", errno);
        } else {
            PASS(name);
        }
    }
}

struct ioctl_probe {
    const char *name;
    unsigned long req;
    int kind;
};

enum { ON_PTY, ON_FILE, ON_SOCK };

static const struct ioctl_probe ioctls[] = {
    {"tcgets", TCGETS, ON_PTY}, {"tiocgwinsz", TIOCGWINSZ, ON_PTY}, {"tiocgpgrp", TIOCGPGRP, ON_PTY},
    {"tiocgsid", TIOCGSID, ON_PTY}, {"tiocinq", TIOCINQ, ON_PTY}, {"tiocoutq", TIOCOUTQ, ON_PTY},
    {"fionread_pty", FIONREAD, ON_PTY}, {"tiocmget", TIOCMGET, ON_PTY}, {"tiocgetd", TIOCGETD, ON_PTY},
    {"tiocgptn", TIOCGPTN, ON_PTY}, {"tiocgpktstate", TIOCPKT, ON_PTY},
    {"fionbio_pty", FIONBIO, ON_PTY}, {"fioclex_pty", FIOCLEX, ON_PTY},
    {"fs_getflags", _IOR('f', 1, long), ON_FILE}, {"figetbsz", _IO(0x00, 2), ON_FILE},
    {"fionread_file", FIONREAD, ON_FILE}, {"fioclex_file", FIOCLEX, ON_FILE}, {"fionclex_file", FIONCLEX, ON_FILE},
    {"fionbio_file", FIONBIO, ON_FILE},
    {"siocgifconf", SIOCGIFCONF, ON_SOCK}, {"siocgifflags", SIOCGIFFLAGS, ON_SOCK},
    {"siocgifaddr", SIOCGIFADDR, ON_SOCK}, {"siocgifnetmask", SIOCGIFNETMASK, ON_SOCK},
    {"siocgifhwaddr", SIOCGIFHWADDR, ON_SOCK}, {"siocgifindex", SIOCGIFINDEX, ON_SOCK},
    {"siocgifmtu", SIOCGIFMTU, ON_SOCK}, {"siocgifname", SIOCGIFNAME, ON_SOCK},
    {"siocgifbrdaddr", SIOCGIFBRDADDR, ON_SOCK}, {"fionread_sock", FIONREAD, ON_SOCK},
    {"siocinq", 0x541B, ON_SOCK}, {"siocoutq", 0x5411, ON_SOCK}, {"siocgstamp", SIOCGSTAMP, ON_SOCK},
};

static int open_pty(void)
{
    int fd = open("/dev/ptmx", O_RDWR | O_NOCTTY);
    if (fd < 0)
        return -1;
    int zero = 0;
    ioctl(fd, TIOCSPTLCK, &zero);
    return fd;
}

static void probe_ioctl(void)
{
    int pty = open_pty();
    int file = open("/etc/hosts", O_RDONLY);
    int sock = socket(AF_INET, SOCK_DGRAM, 0);
    size_t i;
    for (i = 0; i < COUNT(ioctls); i++) {
        char name[96], arg[512];
        snprintf(name, sizeof name, "ioctl_%s", ioctls[i].name);
        int fd = ioctls[i].kind == ON_PTY ? pty : ioctls[i].kind == ON_FILE ? file : sock;
        if (fd < 0) {
            GAP(name, "no fd");
            continue;
        }
        memset(arg, 0, sizeof arg);
        if (ioctls[i].req == SIOCGIFFLAGS || ioctls[i].req == SIOCGIFADDR || ioctls[i].req == SIOCGIFNETMASK
            || ioctls[i].req == SIOCGIFHWADDR || ioctls[i].req == SIOCGIFINDEX || ioctls[i].req == SIOCGIFMTU
            || ioctls[i].req == SIOCGIFBRDADDR)
            strcpy(arg, "lo");
        if (ioctls[i].req == SIOCGIFNAME)
            *(int *)(arg + 16) = 1;
        if (ioctls[i].req == SIOCGIFCONF) {
            struct ifconf *c = (struct ifconf *)arg;
            static char ifbuf[1024];
            c->ifc_len = sizeof ifbuf;
            c->ifc_buf = ifbuf;
        }
        errno = 0;
        int r = ioctl(fd, ioctls[i].req, arg);
        if (r >= 0)
            PASS(name);
        else if (errno == ENOTTY || errno == ENOSYS || errno == EINVAL || errno == ENODEV)
            GAP(name, "errno=%d", errno);
        else
            PASS(name);
    }
}

int main(void)
{
    alarm(120);
    probe_paths();
    probe_prctl();
    probe_ioctl();
    return 0;
}
