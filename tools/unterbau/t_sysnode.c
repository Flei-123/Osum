#define TNAME "sysnode"
#include "t.h"
#include <dirent.h>
#include <fcntl.h>
#include <stdlib.h>
#include <sys/ioctl.h>
#include <sys/stat.h>

#define BUF_BYTES 4096
#define NS_COUNT 8
#define NS_GET_USERNS 0xb701
#define NS_GET_NSTYPE 0xb703
#define CLONE_NEWNS_FLAG 0x00020000
#define MIB (1024UL * 1024UL)

static const char *const ns_names[NS_COUNT] = { "cgroup", "ipc", "mnt", "net", "pid", "time", "user", "uts" };

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

static int popcount_hex(const char *text)
{
    int bits = 0;
    for (const char *c = text; *c && *c != '\n'; c++) {
        if (*c == ',')
            continue;
        int v = (*c <= '9') ? *c - '0' : *c - 'a' + 10;
        bits += __builtin_popcount(v);
    }
    return bits;
}

static int list_count(const char *list)
{
    int total = 0;
    const char *c = list;
    while (*c && *c != '\n') {
        char *end;
        long lo = strtol(c, &end, 10);
        long hi = lo;
        if (*end == '-')
            hi = strtol(end + 1, &end, 10);
        total += (int)(hi - lo + 1);
        c = (*end == ',') ? end + 1 : end;
        if (end == c && *end != ',' && *end != 0 && *end != '\n')
            break;
    }
    return total;
}

static void check_node(void)
{
    char map[BUF_BYTES], list[BUF_BYTES], present[BUF_BYTES];
    long m = slurp("/sys/devices/system/node/node0/cpumap", map);
    long l = slurp("/sys/devices/system/node/node0/cpulist", list);
    long p = slurp("/sys/devices/system/cpu/present", present);
    CHECK("node_cpumap_readable", m > 0, "len=%ld errno=%d", m, errno);
    CHECK("node_cpulist_readable", l > 0, "len=%ld errno=%d", l, errno);
    if (m <= 0 || l <= 0 || p <= 0)
        return;
    CHECK("node_cpumap_matches_present", popcount_hex(map) == list_count(present), "map '%s' present '%s'", map, present);
    CHECK("node_cpulist_matches_present", list_count(list) == list_count(present), "list '%s' present '%s'", list, present);
}

static void check_memory(void)
{
    char buf[BUF_BYTES], info[BUF_BYTES];
    long n = slurp("/sys/devices/system/memory/block_size_bytes", buf);
    CHECK("memory_block_size_readable", n > 0, "len=%ld errno=%d", n, errno);
    if (n <= 0)
        return;
    unsigned long size = strtoul(buf, NULL, 16);
    CHECK("memory_block_size_sane", size >= MIB && size % MIB == 0, "size %lu", size);
    int blocks = 0, all_online = 1;
    DIR *d = opendir("/sys/devices/system/memory");
    for (struct dirent *e; d && (e = readdir(d));) {
        if (strncmp(e->d_name, "memory", 6))
            continue;
        blocks++;
        char path[128], state[64];
        snprintf(path, sizeof path, "/sys/devices/system/memory/%s/state", e->d_name);
        if (slurp(path, state) <= 0 || strncmp(state, "online", 6))
            all_online = 0;
    }
    if (d)
        closedir(d);
    CHECK("memory_blocks_listed", blocks >= 1, "blocks=%d", blocks);
    CHECK("memory_blocks_online", all_online, "a block is not online");
    long m = slurp("/proc/meminfo", info);
    char *tag = m > 0 ? strstr(info, "MemTotal:") : NULL;
    unsigned long total_kb = tag ? strtoul(tag + 9, NULL, 10) : 0;
    unsigned long sum = size * (unsigned long)blocks;
    CHECK("memory_sum_matches_meminfo", total_kb != 0 && sum <= total_kb * 1024UL && sum + blocks * MIB > total_kb * 1024UL, "sum %lu total %lu kB", sum, total_kb);
}

static void check_ns(void)
{
    int found = 0, links = 0, readable = 1;
    DIR *d = opendir("/proc/self/ns");
    CHECK("ns_dir_opens", d != NULL, "errno=%d", errno);
    for (struct dirent *e; d && (e = readdir(d));) {
        if (e->d_name[0] == '.')
            continue;
        found++;
        char path[64], target[96];
        snprintf(path, sizeof path, "/proc/self/ns/%s", e->d_name);
        ssize_t n = readlink(path, target, sizeof target - 1);
        if (n <= 0) {
            readable = 0;
            continue;
        }
        target[n] = 0;
        size_t name_len = strlen(e->d_name);
        if (!strncmp(target, e->d_name, name_len) && target[name_len] == ':' && target[name_len + 1] == '[')
            links++;
    }
    if (d)
        closedir(d);
    CHECK("ns_entry_count", found == NS_COUNT, "found %d", found);
    CHECK("ns_readlink_format", readable && links == NS_COUNT, "links %d readable %d", links, readable);
    int named = 1;
    for (int i = 0; i < NS_COUNT; i++) {
        char path[64];
        struct stat st;
        snprintf(path, sizeof path, "/proc/self/ns/%s", ns_names[i]);
        if (lstat(path, &st) != 0 || !S_ISLNK(st.st_mode))
            named = 0;
    }
    CHECK("ns_lstat_is_link", named, "an ns entry is not a symlink");
    DIR *s = opendir("/proc/self");
    int has_ns = 0;
    for (struct dirent *e; s && (e = readdir(s));)
        if (!strcmp(e->d_name, "ns"))
            has_ns = 1;
    if (s)
        closedir(s);
    CHECK("ns_listed_in_pid_dir", has_ns, "readdir /proc/self lacks ns");
    struct stat a, b;
    char other[64];
    snprintf(other, sizeof other, "/proc/%d/ns/mnt", (int)getppid());
    int same = stat("/proc/self/ns/mnt", &a) == 0 && stat(other, &b) == 0 && a.st_ino == b.st_ino && a.st_ino != 0;
    CHECK("ns_same_inode_across_processes", same, "ino %lu vs %lu", (unsigned long)a.st_ino, (unsigned long)b.st_ino);
    int nsfd = open("/proc/self/ns/mnt", O_RDONLY);
    errno = 0;
    int type = nsfd >= 0 ? ioctl(nsfd, NS_GET_NSTYPE) : -1;
    CHECK("ns_ioctl_nstype", type == CLONE_NEWNS_FLAG, "type %x errno=%d fd=%d", type, errno, nsfd);
    errno = 0;
    int owner = nsfd >= 0 ? ioctl(nsfd, NS_GET_USERNS) : -1;
    CHECK("ns_ioctl_userns_eperm", owner == -1 && errno == EPERM, "rc %d errno=%d", owner, errno);
    if (nsfd >= 0)
        close(nsfd);
    errno = 0;
    char t[8];
    CHECK("ns_bad_name_enoent", readlink("/proc/self/ns/nope", t, sizeof t) < 0 && errno == ENOENT, "errno=%d", errno);
}

int main(void)
{
    check_node();
    check_memory();
    check_ns();
    return 0;
}
