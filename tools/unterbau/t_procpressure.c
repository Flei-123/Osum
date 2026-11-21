#define TNAME "procpressure"
#include "t.h"
#include <dirent.h>
#include <fcntl.h>
#include <stdio.h>
#include <stdlib.h>
#include <sys/stat.h>

#define LINE_BYTES 256

static int parse_line(FILE *f, const char *kind)
{
    char line[LINE_BYTES];
    char word[8];
    float a10, a60, a300;
    unsigned long long total;
    if (!fgets(line, sizeof line, f))
        return 0;
    return sscanf(line, "%7s avg10=%f avg60=%f avg300=%f total=%llu", word, &a10, &a60, &a300, &total) == 5
        && strcmp(word, kind) == 0;
}

static void test_file(const char *name, const char *path)
{
    char check[48];
    FILE *f = fopen(path, "r");
    snprintf(check, sizeof check, "%s_opens", name);
    CHECK(check, f != 0, "errno=%d", errno);
    if (!f)
        return;
    int some = parse_line(f, "some");
    int full = parse_line(f, "full");
    fclose(f);
    snprintf(check, sizeof check, "%s_psi_format", name);
    CHECK(check, some && full, "some=%d full=%d", some, full);
    struct stat st;
    snprintf(check, sizeof check, "%s_stat_regular", name);
    CHECK(check, stat(path, &st) == 0 && S_ISREG(st.st_mode), "errno=%d", errno);
}

static int dir_has(const char *dir, const char *name)
{
    DIR *d = opendir(dir);
    int found = 0;
    struct dirent *e;
    while (d && (e = readdir(d)))
        if (strcmp(e->d_name, name) == 0)
            found++;
    if (d)
        closedir(d);
    return found;
}

int main(void)
{
    test_file("cpu", "/proc/pressure/cpu");
    test_file("memory", "/proc/pressure/memory");
    test_file("io", "/proc/pressure/io");
    struct stat st;
    CHECK("pressure_is_dir", stat("/proc/pressure", &st) == 0 && S_ISDIR(st.st_mode), "errno=%d", errno);
    CHECK("pressure_in_proc_listing", dir_has("/proc", "pressure") == 1, "count=%d", dir_has("/proc", "pressure"));
    CHECK("pressure_dir_lists_three", dir_has("/proc/pressure", "cpu") == 1 && dir_has("/proc/pressure", "memory") == 1 && dir_has("/proc/pressure", "io") == 1, "missing entry");
    CHECK("pressure_no_unknown_file", open("/proc/pressure/network", O_RDONLY) < 0, "opened");
    CHECK("proc_filesystems_readable", open("/proc/filesystems", O_RDONLY) >= 0, "errno=%d", errno);
    return 0;
}
