/* fsync/fdatasync on files and directories under /tmp are volatile like on tmpfs (no device flush); other paths still flush. */
#define TNAME "tmpsync"
#include "t.h"
#include <fcntl.h>
#include <stdlib.h>

#define TMP_FILE "/tmp/tmpsync.dat"
#define DISK_FILE "/root/tmpsync.dat"
#define CHUNK 8192

static long bench_value(const char *key)
{
    static char buf[16384];
    int fd = open("/proc/bench", O_RDONLY);
    ssize_t n = fd >= 0 ? read(fd, buf, sizeof buf - 1) : 0;
    if (fd >= 0)
        close(fd);
    buf[n > 0 ? n : 0] = 0;
    char *p = strstr(buf, key);
    return p ? atol(p + strlen(key) + 1) : -1;
}

static long flushes(void)
{
    return bench_value("blk.ahci_flush_cmds");
}

static int write_chunk(int fd, char fill)
{
    char *data = malloc(CHUNK);
    memset(data, fill, CHUNK);
    ssize_t n = write(fd, data, CHUNK);
    free(data);
    return n == CHUNK;
}

int main(void)
{
    long ahci_cmds = bench_value("blk.ahci_cmds");
    long start = flushes();
    sync();
    long synced = flushes();

    int fd = open(TMP_FILE, O_RDWR | O_CREAT | O_TRUNC, 0600);
    CHECKC("tmp_create", fd >= 0);
    if (fd < 0)
        return 1;
    CHECK("tmp_write", write_chunk(fd, 'T'), "short write");
    CHECK("tmp_fsync_ok", fsync(fd) == 0, "errno=%d", errno);
    CHECK("tmp_fdatasync_ok", fdatasync(fd) == 0, "errno=%d", errno);
    int dir = open("/tmp", O_RDONLY | O_DIRECTORY);
    CHECK("tmp_dir_fsync_ok", dir >= 0 && fsync(dir) == 0, "errno=%d", errno);
    long after_tmp = flushes();
    if (start < 0 || after_tmp < 0)
        GAP("tmp_no_flush", "no blk.ahci_flush_cmds in /proc/bench");
    else
        CHECK("tmp_no_flush", after_tmp == synced, "flushes %ld -> %ld", synced, after_tmp);

    char back[CHUNK];
    CHECK("tmp_data_intact", pread(fd, back, CHUNK, 0) == CHUNK && back[0] == 'T' && back[CHUNK - 1] == 'T', "read back differs");
    close(fd);
    if (dir >= 0)
        close(dir);
    unlink(TMP_FILE);

    int disk = open(DISK_FILE, O_RDWR | O_CREAT | O_TRUNC, 0600);
    if (disk < 0) {
        GAP("disk_flush", "cannot create %s: errno=%d", DISK_FILE, errno);
        return 0;
    }
    write_chunk(disk, 'D');
    CHECK("disk_fsync_ok", fsync(disk) == 0, "errno=%d", errno);
    long after_disk = flushes();
    if (ahci_cmds <= 0 || after_disk < 0)
        GAP("disk_flush", "root disk is not on AHCI");
    else
        CHECK("disk_flush", after_disk > after_tmp, "flushes %ld -> %ld", after_tmp, after_disk);
    close(disk);
    unlink(DISK_FILE);
    return 0;
}
