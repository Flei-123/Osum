#define TNAME "procmount"
#include "t.h"
#include <dirent.h>
#include <fcntl.h>
#include <stdlib.h>

#define BUF_BYTES 8192
#define MOUNTINFO_FIELDS_BEFORE_SEPARATOR 6

static long slurp(const char *path, char *buf)
{
    int fd = open(path, O_RDONLY);
    if (fd < 0)
        return -1;
    long total = 0;
    for (;;) {
        long n = read(fd, buf + total, BUF_BYTES - 1 - total);
        if (n <= 0)
            break;
        total += n;
    }
    close(fd);
    buf[total] = 0;
    return total;
}

static int line_ok(const char *line)
{
    int id, parent, major, minor;
    char root[64], mp[64], opts[64];
    int used = 0;
    if (sscanf(line, "%d %d %d:%d %63s %63s %63s%n", &id, &parent, &major, &minor, root, mp, opts, &used) != 7)
        return 0;
    const char *sep = strstr(line + used, " - ");
    if (!sep)
        return 0;
    char fstype[32], source[64], super[64];
    return sscanf(sep + 3, "%31s %63s %63s", fstype, source, super) == 3;
}

static int count_lines(char *buf, int *all_ok)
{
    int n = 0;
    *all_ok = 1;
    for (char *l = strtok(buf, "\n"); l; l = strtok(NULL, "\n")) {
        n++;
        if (!line_ok(l))
            *all_ok = 0;
    }
    return n;
}

static int has_mount_point(const char *info, const char *mp)
{
    char needle[80];
    snprintf(needle, sizeof needle, " %s ", mp);
    return strstr(info, needle) != NULL;
}

int main(void)
{
    static char info[BUF_BYTES], copy[BUF_BYTES], mounts[BUF_BYTES], by_pid[BUF_BYTES];
    long n = slurp("/proc/self/mountinfo", info);
    CHECK("mountinfo_readable", n > 0, "len=%ld errno=%d", n, errno);
    if (n <= 0)
        return 0;
    strcpy(copy, info);
    int all_ok;
    int lines = count_lines(copy, &all_ok);
    CHECK("mountinfo_lines", lines >= 1, "lines=%d", lines);
    CHECK("mountinfo_format", all_ok, "a line does not parse: %s", info);
    CHECK("mountinfo_has_root", has_mount_point(info, "/"), "no / entry");
    CHECK("mountinfo_has_proc", strstr(info, " - proc ") != NULL, "no proc entry");

    char path[64];
    snprintf(path, sizeof path, "/proc/%d/mountinfo", (int)getpid());
    long m = slurp(path, by_pid);
    CHECK("mountinfo_by_pid", m == n && !strcmp(info, by_pid), "len %ld vs %ld", m, n);

    long k = slurp("/proc/self/mounts", mounts);
    CHECK("mounts_readable", k > 0, "len=%ld", k);
    CHECK("mounts_no_double_space", k > 0 && !strstr(mounts, "  "), "double space in /proc/self/mounts");
    int consistent = 1;
    char *save = NULL;
    for (char *l = strtok_r(mounts, "\n", &save); l; l = strtok_r(NULL, "\n", &save)) {
        char src[64], mp[64];
        if (sscanf(l, "%63s %63s", src, mp) == 2 && !has_mount_point(info, mp))
            consistent = 0;
    }
    CHECK("mounts_match_mountinfo", consistent, "a mount point of /proc/self/mounts is missing in mountinfo");

    DIR *d = opendir("/proc/self");
    int listed = 0;
    for (struct dirent *e; d && (e = readdir(d));)
        if (!strcmp(e->d_name, "mountinfo"))
            listed = 1;
    if (d)
        closedir(d);
    CHECK("mountinfo_listed", listed, "readdir /proc/self lacks mountinfo");

    DIR *t = opendir("/proc/self/task");
    int task_ok = t != NULL;
    if (t)
        closedir(t);
    CHECK("task_dir_still_works", task_ok, "errno=%d", errno);
    return 0;
}
