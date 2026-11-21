#define TNAME "linuxany"
#include "t.h"
#include <fcntl.h>
#include <stdlib.h>
#include <sys/ioctl.h>
#include <sys/socket.h>
#include <sys/stat.h>
#include <sys/syscall.h>

#define NR_MOVE_PAGES 279
#define CREAT_PATH "/tmp/linuxany.creat"
#define PAGE_BYTES 4096

static long move_pages(long pid, unsigned long count, void **pages, int *nodes, int *status, long flags)
{
    errno = 0;
    return syscall(NR_MOVE_PAGES, pid, count, pages, nodes, status, flags);
}

static void test_creat(void)
{
    unlink(CREAT_PATH);
    int fd = creat(CREAT_PATH, 0644);
    CHECK("creat_new", fd >= 0, "errno=%d", errno);
    if (fd < 0)
        return;
    CHECK("creat_write", write(fd, "abc", 3) == 3, "errno=%d", errno);
    close(fd);
    struct stat st;
    CHECK("creat_size", stat(CREAT_PATH, &st) == 0 && st.st_size == 3, "size=%ld", (long)st.st_size);
    fd = creat(CREAT_PATH, 0644);
    CHECK("creat_truncates", fd >= 0 && fstat(fd, &st) == 0 && st.st_size == 0, "errno=%d", errno);
    if (fd >= 0)
        close(fd);
    unlink(CREAT_PATH);
    errno = 0;
    CHECK("creat_fault", syscall(85, 1L, 0644L) == -1 && errno == EFAULT, "errno=%d", errno);
}

static void test_move_pages(void)
{
    char *mem = aligned_alloc(PAGE_BYTES, 2 * PAGE_BYTES);
    mem[0] = 1;
    mem[PAGE_BYTES] = 1;
    void *pages[3] = { mem, mem + PAGE_BYTES, (void *)0x10 };
    int status[3] = { 99, 99, 99 };
    long r = move_pages(0, 3, pages, NULL, status, 0);
    CHECK("move_pages_query_ok", r == 0, "r=%ld errno=%d", r, errno);
    CHECK("move_pages_node0", status[0] == 0 && status[1] == 0, "s0=%d s1=%d", status[0], status[1]);
    CHECK("move_pages_unmapped", status[2] == -EFAULT, "s2=%d", status[2]);
    int nodes[3] = { 0, 1, 0 };
    r = move_pages(0, 3, pages, nodes, status, 2);
    CHECK("move_pages_move_ok", r == 0 && status[0] == 0, "r=%ld s0=%d", r, status[0]);
    CHECK("move_pages_no_node1", status[1] == -ENODEV, "s1=%d", status[1]);
    CHECK("move_pages_bad_flags", move_pages(0, 1, pages, NULL, status, 1) == -1 && errno == EINVAL, "errno=%d", errno);
    CHECK("move_pages_bad_pid", move_pages(99999, 1, pages, NULL, status, 0) == -1 && errno == ESRCH, "errno=%d", errno);
    CHECK("move_pages_self_pid", move_pages(getpid(), 1, pages, NULL, status, 0) == 0, "errno=%d", errno);
    CHECK("move_pages_bad_status", move_pages(0, 1, pages, NULL, (int *)1, 0) == -1 && errno == EFAULT, "errno=%d", errno);
    free(mem);
}

#define IOCTL_FIOASYNC 0x5452

static void test_fioasync(void)
{
    int pair[2];
    int on = 1;
    CHECK("fioasync_socketpair_open", socketpair(AF_UNIX, SOCK_STREAM, 0, pair) == 0, "errno=%d", errno);
    CHECK("fioasync_unix_socket", ioctl(pair[0], IOCTL_FIOASYNC, &on) == 0, "errno=%d", errno);
    on = 0;
    CHECK("fioasync_unix_socket_off", ioctl(pair[1], IOCTL_FIOASYNC, &on) == 0, "errno=%d", errno);
    int pipefd[2];
    CHECK("fioasync_pipe_open", pipe(pipefd) == 0, "errno=%d", errno);
    on = 1;
    CHECK("fioasync_pipe", ioctl(pipefd[0], IOCTL_FIOASYNC, &on) == 0, "errno=%d", errno);
    errno = 0;
    CHECK("fioasync_fault", ioctl(pair[0], IOCTL_FIOASYNC, (void *)1) == -1 && errno == EFAULT, "errno=%d", errno);
    errno = 0;
    CHECK("fioasync_badfd", ioctl(-1, IOCTL_FIOASYNC, &on) == -1 && errno == EBADF, "errno=%d", errno);
    close(pair[0]);
    close(pair[1]);
    close(pipefd[0]);
    close(pipefd[1]);
}

static int slurp(const char *path, char *buf, size_t len)
{
    int fd = open(path, O_RDONLY);
    if (fd < 0)
        return -1;
    ssize_t n = read(fd, buf, len - 1);
    close(fd);
    if (n < 0)
        return -1;
    buf[n] = 0;
    return (int)n;
}

static void proc_has(const char *name, const char *path, const char *needle)
{
    char buf[2048];
    int n = slurp(path, buf, sizeof buf);
    CHECK(name, n > 0 && strstr(buf, needle) != NULL, "n=%d errno=%d", n, errno);
}

static void test_proc(void)
{
    proc_has("proc_iomem", "/proc/iomem", "System RAM");
    proc_has("proc_ioports", "/proc/ioports", "PCI Bus");
    proc_has("proc_zoneinfo", "/proc/zoneinfo", "Node 0, zone");
    proc_has("proc_softirqs", "/proc/softirqs", "TIMER");
    proc_has("proc_buddyinfo", "/proc/buddyinfo", "Node 0, zone");
}

int main(void)
{
    test_creat();
    test_move_pages();
    test_fioasync();
    test_proc();
    return 0;
}
