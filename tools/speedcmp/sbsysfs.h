#include <sys/statfs.h>

#define SBS_THP_PATH "/sys/kernel/mm/transparent_hugepage/hpage_pmd_size"
#define SBS_CPU_PATH "/sys/devices/system/cpu/online"

static void run_stat_sysfs(long n)
{
    struct stat st;
    for (long i = 0; i < n; i++) {
        stat(SBS_THP_PATH, &st);
        stat(SBS_CPU_PATH, &st);
    }
}

static void run_statfs_root(long n)
{
    struct statfs sf;
    for (long i = 0; i < n; i++)
        statfs("/", &sf);
}

static void sbs_run_all(void)
{
    measure("stat_sysfs", run_stat_sysfs, 200, 1, 2);
    measure("statfs_root", run_statfs_root, 200, 1, 1);
}
