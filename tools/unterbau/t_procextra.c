#define TNAME "procextra"
#include "t.h"
#include <dirent.h>
#include <fcntl.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/prctl.h>
#include <unistd.h>

static int slurp(const char *path, char *out, size_t cap)
{
    int fd = open(path, O_RDONLY);
    if (fd < 0)
        return -1;
    ssize_t n = read(fd, out, cap - 1);
    close(fd);
    if (n < 0)
        return -1;
    out[n] = 0;
    return (int)n;
}

static int dir_has(const char *path, const char *name)
{
    DIR *d = opendir(path);
    struct dirent *e;
    int found = 0;
    if (!d)
        return 0;
    while ((e = readdir(d)))
        if (!strcmp(e->d_name, name))
            found = 1;
    closedir(d);
    return found;
}

static void test_pid_files(void)
{
    char buf[1024];
    CHECK("wchan_zero", slurp("/proc/self/wchan", buf, sizeof buf) == 1 && !strcmp(buf, "0"), "buf=%s", buf);
    CHECK("cpuset_root", slurp("/proc/self/cpuset", buf, sizeof buf) == 2 && !strcmp(buf, "/\n"), "buf=%s", buf);
    CHECK("loginuid_unset", slurp("/proc/self/loginuid", buf, sizeof buf) > 0 && !strcmp(buf, "4294967295\n"), "buf=%s", buf);
    CHECK("timerslack_default", slurp("/proc/self/timerslack_ns", buf, sizeof buf) > 0 && atol(buf) == 50000, "buf=%s", buf);
    CHECK("syscall_running", slurp("/proc/self/syscall", buf, sizeof buf) > 0 && (!strncmp(buf, "running", 7) || buf[0] == '-'), "buf=%s", buf);
    CHECK("pid_dir_lists_extras", dir_has("/proc/self", "wchan") && dir_has("/proc/self", "cpuset") && dir_has("/proc/self", "loginuid") && dir_has("/proc/self", "timerslack_ns") && dir_has("/proc/self", "syscall") && dir_has("/proc/self", "sched"), "missing entry");
}

static void test_timerslack_follows_prctl(void)
{
    char buf[64];
    int rc = prctl(PR_SET_TIMERSLACK, 123456UL, 0, 0, 0);
    CHECK("timerslack_set", rc == 0 && slurp("/proc/self/timerslack_ns", buf, sizeof buf) > 0 && atol(buf) == 123456, "rc=%d buf=%s", rc, buf);
}

static void test_sched(void)
{
    char buf[1024], want[64];
    int n = slurp("/proc/self/sched", buf, sizeof buf);
    snprintf(want, sizeof want, "(%d, #threads: 1)", getpid());
    CHECK("sched_header", n > 0 && strstr(buf, want), "want=%s buf=%s", want, buf);
    CHECK("sched_fields", n > 0 && strstr(buf, "se.sum_exec_runtime") && strstr(buf, "nr_switches"), "buf=%s", buf);
}

static void test_interrupts(void)
{
    char buf[2048];
    int n = slurp("/proc/interrupts", buf, sizeof buf);
    CHECK("interrupts_header", n > 0 && strstr(buf, "CPU0"), "buf=%s", buf);
    char *loc = strstr(buf, "LOC:");
    long first = loc ? atol(loc + 4) : -1;
    CHECK("interrupts_timer_ticks", loc && first > 0 && strstr(loc, "Local timer interrupts"), "buf=%s", buf);
}

static void test_cpu_tree(void)
{
    char buf[256];
    CHECK("kernel_max", slurp("/sys/devices/system/cpu/kernel_max", buf, sizeof buf) > 0 && atoi(buf) >= 0, "buf=%s", buf);
    CHECK("cpu0_online", slurp("/sys/devices/system/cpu/cpu0/online", buf, sizeof buf) == 2 && !strcmp(buf, "1\n"), "buf=%s", buf);
    CHECK("cpu_dir_lists_kernel_max", dir_has("/sys/devices/system/cpu", "kernel_max") && dir_has("/sys/devices/system/cpu", "cpu0"), "missing entry");
    CHECK("cpu0_dir_lists_topology", dir_has("/sys/devices/system/cpu/cpu0", "topology") && dir_has("/sys/devices/system/cpu/cpu0", "online") && dir_has("/sys/devices/system/cpu/cpu0", "cache"), "missing entry");
    CHECK("topology_dir", dir_has("/sys/devices/system/cpu/cpu0/topology", "core_id") && dir_has("/sys/devices/system/cpu/cpu0/topology", "physical_package_id") && dir_has("/sys/devices/system/cpu/cpu0/topology", "thread_siblings_list") && dir_has("/sys/devices/system/cpu/cpu0/topology", "core_siblings_list"), "missing entry");
    CHECK("package_id_number", slurp("/sys/devices/system/cpu/cpu0/topology/physical_package_id", buf, sizeof buf) > 1 && atoi(buf) >= 0 && buf[strlen(buf) - 1] == '\n', "buf=%s", buf);
    CHECK("core_id_number", slurp("/sys/devices/system/cpu/cpu0/topology/core_id", buf, sizeof buf) > 1 && atoi(buf) >= 0 && buf[strlen(buf) - 1] == '\n', "buf=%s", buf);
    CHECK("thread_siblings_has_self", slurp("/sys/devices/system/cpu/cpu0/topology/thread_siblings_list", buf, sizeof buf) > 1 && buf[0] == '0', "buf=%s", buf);
    CHECK("core_siblings_has_self", slurp("/sys/devices/system/cpu/cpu0/topology/core_siblings_list", buf, sizeof buf) > 1 && buf[0] == '0', "buf=%s", buf);
}

static void test_cpu_tree_consistency(void)
{
    char present[64], packages[64], online[64];
    int a = slurp("/sys/devices/system/cpu/present", present, sizeof present);
    int b = slurp("/sys/devices/system/cpu/cpu0/topology/core_siblings_list", packages, sizeof packages);
    int c = slurp("/sys/devices/system/cpu/online", online, sizeof online);
    CHECK("core_siblings_within_present", a > 0 && b > 0 && c > 0 && atoi(strrchr(packages, '-') ? strrchr(packages, '-') + 1 : packages) <= atoi(strrchr(present, '-') ? strrchr(present, '-') + 1 : present), "present=%s packages=%s", present, packages);
}

static int list_has(const char *list, int cpu)
{
    const char *p = list;
    while (*p && *p != '\n') {
        char *end;
        long lo = strtol(p, &end, 10), hi = lo;
        if (end == p)
            return 0;
        if (*end == '-')
            hi = strtol(end + 1, &end, 10);
        if (cpu >= lo && cpu <= hi)
            return 1;
        p = *end == ',' ? end + 1 : end;
    }
    return 0;
}

static void test_every_cpu_lists_itself(void)
{
    char buf[256], path[160];
    long cpus = sysconf(_SC_NPROCESSORS_CONF);
    int bad = 0;
    for (int i = 0; i < cpus; i++) {
        snprintf(path, sizeof path, "/sys/devices/system/cpu/cpu%d/topology/thread_siblings_list", i);
        if (slurp(path, buf, sizeof buf) <= 0 || !list_has(buf, i))
            bad++;
        snprintf(path, sizeof path, "/sys/devices/system/cpu/cpu%d/topology/core_siblings_list", i);
        if (slurp(path, buf, sizeof buf) <= 0 || !list_has(buf, i))
            bad++;
    }
    CHECK("every_cpu_lists_itself", cpus >= 1 && bad == 0, "cpus=%ld bad=%d", cpus, bad);
}

int main(void)
{
    alarm(60);
    test_pid_files();
    test_timerslack_follows_prctl();
    test_sched();
    test_interrupts();
    test_cpu_tree();
    test_cpu_tree_consistency();
    test_every_cpu_lists_itself();
    return 0;
}
