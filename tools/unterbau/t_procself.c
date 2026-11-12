#define TNAME "procself"
#include "t.h"
#include <fcntl.h>
#include <unistd.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <elf.h>

extern char **environ;

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

static void test_environ(void)
{
    char buf[4096];
    int n = slurp("/proc/self/environ", buf, sizeof buf);
    int found = 0;
    for (int i = 0; i < n; i += strlen(buf + i) + 1)
        if (!strcmp(buf + i, environ[0]))
            found = 1;
    CHECK("environ_has_first", n > 0 && environ[0] && found, "n=%d", n);
}

static void test_comm_statm(void)
{
    char buf[256];
    CHECK("comm_newline", slurp("/proc/self/comm", buf, sizeof buf) > 1 && buf[strlen(buf) - 1] == '\n', "comm=%s", buf);
    long size = 0, res = 0;
    CHECK("statm_fields", slurp("/proc/self/statm", buf, sizeof buf) > 0 && sscanf(buf, "%ld %ld", &size, &res) == 2 && size > 0 && res > 0, "buf=%s", buf);
    CHECK("oom_score_adj_zero", slurp("/proc/self/oom_score_adj", buf, sizeof buf) > 0 && atoi(buf) == 0, "buf=%s", buf);
    CHECK("oom_score_num", slurp("/proc/self/oom_score", buf, sizeof buf) > 0 && atoi(buf) >= 0, "buf=%s", buf);
    CHECK("personality_zero", slurp("/proc/self/personality", buf, sizeof buf) == 9 && !strcmp(buf, "00000000\n"), "buf=%s", buf);
}

static void test_auxv(void)
{
    Elf64_auxv_t av[64];
    int fd = open("/proc/self/auxv", O_RDONLY);
    ssize_t n = fd < 0 ? -1 : read(fd, av, sizeof av);
    if (fd >= 0)
        close(fd);
    int pagesz = 0, last_null = 0;
    for (ssize_t i = 0; i * (ssize_t)sizeof av[0] < n; i++) {
        if (av[i].a_type == AT_PAGESZ && av[i].a_un.a_val == 4096)
            pagesz = 1;
        last_null = av[i].a_type == AT_NULL;
    }
    CHECK("auxv_pagesz_null", n > 0 && pagesz && last_null, "n=%zd", n);
}

static void test_io_mounts_rollup(void)
{
    char buf[4096];
    CHECK("io_fields", slurp("/proc/self/io", buf, sizeof buf) > 0 && strstr(buf, "rchar:") && strstr(buf, "write_bytes:"), "buf=%s", buf);
    CHECK("mounts_root", slurp("/proc/self/mounts", buf, sizeof buf) > 0 && strstr(buf, " / "), "buf=%s", buf);
    CHECK("rollup_rss", slurp("/proc/self/smaps_rollup", buf, sizeof buf) > 0 && strstr(buf, "[rollup]") && strstr(buf, "Rss:"), "buf=%s", buf);
}

int main(void)
{
    alarm(60);
    test_environ();
    test_comm_statm();
    test_auxv();
    test_io_mounts_rollup();
    return 0;
}
