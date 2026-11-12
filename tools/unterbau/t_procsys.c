#define TNAME "procsys"
#include "t.h"
#include <dirent.h>
#include <fcntl.h>
#include <unistd.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/utsname.h>

static int read_text(const char *path, char *out, size_t cap)
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

static void test_uname_match(void)
{
    struct utsname u;
    char buf[128];
    uname(&u);
    CHECK("hostname_is_uname", read_text("/proc/sys/kernel/hostname", buf, sizeof buf) > 0 && strncmp(buf, u.nodename, strlen(u.nodename)) == 0 && buf[strlen(u.nodename)] == '\n', "buf=%s", buf);
    CHECK("osrelease_is_uname", read_text("/proc/sys/kernel/osrelease", buf, sizeof buf) > 0 && strncmp(buf, u.release, strlen(u.release)) == 0, "buf=%s", buf);
    CHECK("ostype_is_uname", read_text("/proc/sys/kernel/ostype", buf, sizeof buf) > 0 && strncmp(buf, u.sysname, strlen(u.sysname)) == 0, "buf=%s", buf);
    CHECK("version_is_uname", read_text("/proc/sys/kernel/version", buf, sizeof buf) > 0 && strncmp(buf, u.version, strlen(u.version)) == 0, "buf=%s", buf);
}

static void test_limits(void)
{
    char buf[128];
    CHECK("ngroups_max", read_text("/proc/sys/kernel/ngroups_max", buf, sizeof buf) > 0 && atoi(buf) == 16, "buf=%s", buf);
    CHECK("pipe_max_size", read_text("/proc/sys/fs/pipe-max-size", buf, sizeof buf) > 0 && atoi(buf) == 65536, "buf=%s", buf);
    int fd = open("/proc/sys/fs/nr_open", O_RDONLY);
    CHECK("nr_open_bounds_fd", fd >= 0 && read_text("/proc/sys/fs/nr_open", buf, sizeof buf) > 0 && atoi(buf) == 512, "buf=%s", buf);
    if (fd >= 0)
        close(fd);
    int a = 0, z = 0, m = 0;
    CHECK("file_nr_format", read_text("/proc/sys/fs/file-nr", buf, sizeof buf) > 0 && sscanf(buf, "%d %d %d", &a, &z, &m) == 3 && a > 0 && m == 1024, "buf=%s", buf);
    CHECK("port_range", read_text("/proc/sys/net/ipv4/ip_local_port_range", buf, sizeof buf) > 0 && sscanf(buf, "%d %d", &a, &z) == 2 && a == 40000 && z == 44095, "buf=%s", buf);
}

static void test_boot_id(void)
{
    char a[64], b[64];
    int na = read_text("/proc/sys/kernel/random/boot_id", a, sizeof a);
    int nb = read_text("/proc/sys/kernel/random/boot_id", b, sizeof b);
    CHECK("boot_id_stable_uuid", na == 37 && nb == 37 && memcmp(a, b, 37) == 0 && a[8] == '-' && a[14] == '4', "a=%s", a);
}

static void test_dirs(void)
{
    DIR *d = opendir("/proc/sys/kernel");
    int host = 0, pty = 0, n = 0;
    struct dirent *e;
    while (d && (e = readdir(d))) {
        n++;
        if (!strcmp(e->d_name, "hostname"))
            host = 1;
        if (!strcmp(e->d_name, "pty"))
            pty = 1;
    }
    if (d)
        closedir(d);
    CHECK("readdir_kernel", host && pty && n > 10, "host=%d pty=%d n=%d", host, pty, n);
    char buf[64];
    CHECK("nested_file", read_text("/proc/sys/kernel/yama/ptrace_scope", buf, sizeof buf) > 0 && atoi(buf) == 0, "buf=%s", buf);
    CHECK("missing_is_enoent", read_text("/proc/sys/kernel/nope", buf, sizeof buf) < 0 && errno == ENOENT, "errno=%d", errno);
}

int main(void)
{
    alarm(60);
    test_uname_match();
    test_limits();
    test_boot_id();
    test_dirs();
    return 0;
}
