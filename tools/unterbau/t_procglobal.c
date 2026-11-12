#define TNAME "procglobal"
#include "t.h"
#include <fcntl.h>
#include <unistd.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

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

static void test_text_files(void)
{
    char buf[4096];
    CHECK("filesystems_proc", slurp("/proc/filesystems", buf, sizeof buf) > 0 && strstr(buf, "nodev\tproc\n") && strstr(buf, "\text4\n"), "buf=%s", buf);
    CHECK("cmdline_newline", slurp("/proc/cmdline", buf, sizeof buf) >= 1 && buf[strlen(buf) - 1] == '\n', "buf=%s", buf);
    CHECK("swaps_header", slurp("/proc/swaps", buf, sizeof buf) > 0 && !strncmp(buf, "Filename", 8), "buf=%s", buf);
    CHECK("devices_sections", slurp("/proc/devices", buf, sizeof buf) > 0 && strstr(buf, "Character devices:") && strstr(buf, "Block devices:"), "buf=%s", buf);
}

static void test_vmstat(void)
{
    char buf[1024];
    long free_pages = -1;
    char *p;
    int n = slurp("/proc/vmstat", buf, sizeof buf);
    p = strstr(buf, "nr_free_pages ");
    if (p)
        free_pages = atol(p + 14);
    CHECK("vmstat_free_pages", n > 0 && free_pages > 0 && strstr(buf, "pgpgin ") && strstr(buf, "pswpout "), "buf=%s", buf);
}

static void test_disks(void)
{
    char buf[4096];
    CHECK("partitions_header", slurp("/proc/partitions", buf, sizeof buf) > 0 && !strncmp(buf, "major minor  #blocks  name\n\n", 28), "buf=%s", buf);
    int n = slurp("/proc/diskstats", buf, sizeof buf);
    int major = 0, minor = 0;
    char name[32] = "";
    unsigned long rd = 0;
    CHECK("diskstats_row", n > 0 && sscanf(buf, "%d %d %31s %lu", &major, &minor, name, &rd) == 4 && major > 0, "buf=%s", buf);
}

static void test_dir(void)
{
    char buf[64];
    CHECK("missing_is_enoent", slurp("/proc/nope_file", buf, sizeof buf) < 0, "errno=%d", errno);
}

int main(void)
{
    alarm(60);
    test_text_files();
    test_vmstat();
    test_disks();
    test_dir();
    return 0;
}
