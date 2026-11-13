#define TNAME "fanotify"
#include "t.h"
#include <fcntl.h>
#include <poll.h>
#include <stdint.h>
#include <sys/epoll.h>
#include <sys/stat.h>
#include <sys/syscall.h>
#include <sys/wait.h>

#ifndef SYS_fanotify_init
#define SYS_fanotify_init 300
#define SYS_fanotify_mark 301
#endif
#define FAN_NONBLOCK 0x2
#define FAN_CLASS_CONTENT 0x4
#define FAN_MODIFY 0x2
#define FAN_CLOSE_WRITE 0x8
#define FAN_CLOSE_NOWRITE 0x10
#define FAN_OPEN 0x20
#define FAN_CREATE 0x100
#define FAN_DELETE 0x200
#define FAN_ONDIR 0x40000000
#define FAN_EVENT_ON_CHILD 0x08000000
#define FAN_OPEN_PERM 0x10000
#define FAN_MARK_ADD 0x1
#define FAN_MARK_REMOVE 0x2
#define FAN_MARK_MOUNT 0x10
#define FAN_MARK_FLUSH 0x80
#define FAN_NOFD (-1)
#define FANOTIFY_METADATA_VERSION 3
#define AT_FDCWD_RAW (-100)
#define DIR_PATH "/tmp/fan_dir"
#define FILE_A "/tmp/fan_a"
#define FILE_B "/tmp/fan_dir/b"
#define FILE_C "/tmp/fan_dir/c"

struct fan_event {
    uint32_t event_len;
    uint8_t vers;
    uint8_t reserved;
    uint16_t metadata_len;
    uint64_t mask;
    int32_t fd;
    int32_t pid;
};

static int fan_init(unsigned flags, unsigned open_flags)
{
    return (int)syscall(SYS_fanotify_init, flags, open_flags);
}

static int fan_mark(int fd, unsigned flags, uint64_t mask, const char *path)
{
    return (int)syscall(SYS_fanotify_mark, fd, flags, mask, AT_FDCWD_RAW, path);
}

static int next_event(int fd, struct fan_event *ev)
{
    struct pollfd p = { fd, POLLIN, 0 };
    if (poll(&p, 1, 2000) <= 0)
        return -1;
    return read(fd, ev, sizeof *ev) == (ssize_t)sizeof *ev ? 0 : -2;
}

static int drain(int fd)
{
    struct fan_event ev;
    int n = 0;
    while (read(fd, &ev, sizeof ev) == (ssize_t)sizeof ev) {
        if (ev.fd >= 0)
            close(ev.fd);
        n++;
    }
    return n;
}

static int expect_event(int fd, uint64_t mask, int want_fd)
{
    struct fan_event ev;
    if (next_event(fd, &ev) != 0)
        return 0;
    int ok = (ev.mask & mask) == mask && ((ev.fd >= 0) == want_fd);
    if (ev.fd >= 0)
        close(ev.fd);
    return ok;
}

static void make_file(const char *path, const char *text)
{
    int fd = open(path, O_WRONLY | O_CREAT | O_TRUNC, 0600);
    if (fd >= 0) {
        (void)!write(fd, text, strlen(text));
        close(fd);
    }
}

int main(void)
{
    mkdir(DIR_PATH, 0700);
    make_file(FILE_A, "hello");
    errno = 0;
    int g = fan_init(FAN_NONBLOCK, O_RDONLY);
    CHECKC("init", g >= 0);
    if (g < 0)
        return 0;

    errno = 0;
    CHECK("init_bad_flags", fan_init(0x80000000u, O_RDONLY) == -1 && errno == EINVAL, "errno=%d", errno);
    errno = 0;
    CHECK("init_content_class_refused", fan_init(FAN_CLASS_CONTENT, O_RDONLY) == -1 && errno == EINVAL, "errno=%d", errno);
    errno = 0;
    CHECK("mark_bad_fd", fan_mark(999, FAN_MARK_ADD, FAN_OPEN, FILE_A) == -1 && errno == EBADF, "errno=%d", errno);
    errno = 0;
    CHECK("mark_not_a_group", fan_mark(1, FAN_MARK_ADD, FAN_OPEN, FILE_A) == -1 && errno == EINVAL, "errno=%d", errno);
    errno = 0;
    CHECK("mark_no_operation", fan_mark(g, 0, FAN_OPEN, FILE_A) == -1 && errno == EINVAL, "errno=%d", errno);
    errno = 0;
    CHECK("mark_zero_mask", fan_mark(g, FAN_MARK_ADD, 0, FILE_A) == -1 && errno == EINVAL, "errno=%d", errno);
    errno = 0;
    CHECK("mark_permission_event_refused", fan_mark(g, FAN_MARK_ADD, FAN_OPEN_PERM, FILE_A) == -1 && errno == EINVAL, "errno=%d", errno);
    errno = 0;
    CHECK("mark_missing_path", fan_mark(g, FAN_MARK_ADD, FAN_OPEN, "/tmp/fan_missing") == -1 && errno == ENOENT, "errno=%d", errno);
    errno = 0;
    CHECK("mark_remove_unknown", fan_mark(g, FAN_MARK_REMOVE, FAN_OPEN, FILE_A) == -1 && errno == ENOENT, "errno=%d", errno);

    struct fan_event ev;
    errno = 0;
    CHECK("read_empty_eagain", read(g, &ev, sizeof ev) == -1 && errno == EAGAIN, "errno=%d", errno);
    errno = 0;
    CHECK("read_short_buffer", read(g, &ev, 8) == -1 && errno == EINVAL, "errno=%d", errno);

    errno = 0;
    CHECKC("mark_file", fan_mark(g, FAN_MARK_ADD, FAN_OPEN | FAN_CLOSE_WRITE | FAN_CLOSE_NOWRITE | FAN_MODIFY, FILE_A) == 0);
    struct pollfd idle = { g, POLLIN, 0 };
    CHECK("poll_idle", poll(&idle, 1, 0) == 0, "revents=0x%x", idle.revents);

    int fd = open(FILE_A, O_RDWR);
    CHECKC("open_target", fd >= 0);
    struct pollfd busy = { g, POLLIN, 0 };
    CHECK("poll_ready_after_open", poll(&busy, 1, 1000) == 1 && (busy.revents & POLLIN), "revents=0x%x", busy.revents);
    int got = next_event(g, &ev);
    CHECK("open_event_read", got == 0, "got=%d", got);
    CHECK("open_event_metadata", got == 0 && ev.event_len == sizeof ev && ev.vers == FANOTIFY_METADATA_VERSION && ev.metadata_len == sizeof ev, "len=%u vers=%u meta=%u", ev.event_len, ev.vers, ev.metadata_len);
    CHECK("open_event_mask", got == 0 && ev.mask == FAN_OPEN, "mask=0x%llx", (unsigned long long)ev.mask);
    CHECK("open_event_pid", got == 0 && ev.pid == getpid(), "pid=%d want %d", ev.pid, (int)getpid());
    char text[16] = {0};
    CHECK("open_event_fd_reads_file", got == 0 && ev.fd >= 0 && pread(ev.fd, text, 5, 0) == 5 && memcmp(text, "hello", 5) == 0, "fd=%d text=%s", ev.fd, text);
    if (got == 0 && ev.fd >= 0)
        close(ev.fd);

    (void)!write(fd, "xy", 2);
    CHECK("modify_event", expect_event(g, FAN_MODIFY, 1), "no modify event");
    close(fd);
    CHECK("close_write_event", expect_event(g, FAN_CLOSE_WRITE, 1), "no close-write event");
    CHECK("queue_empty_after_reads", drain(g) == 0, "extra events queued");

    fd = open(FILE_A, O_RDONLY);
    int opened = expect_event(g, FAN_OPEN, 1);
    close(fd);
    CHECK("close_nowrite_event", opened && expect_event(g, FAN_CLOSE_NOWRITE, 1), "no close-nowrite event");

    errno = 0;
    CHECKC("mark_dir_entries", fan_mark(g, FAN_MARK_ADD, FAN_CREATE | FAN_DELETE, DIR_PATH) == 0);
    make_file(FILE_B, "b");
    int created = expect_event(g, FAN_CREATE, 0);
    CHECK("create_event_without_fd", created, "no create event");
    drain(g);
    unlink(FILE_B);
    CHECK("delete_event_without_fd", expect_event(g, FAN_DELETE, 0), "no delete event");
    drain(g);

    errno = 0;
    CHECKC("mark_dir_on_child", fan_mark(g, FAN_MARK_ADD, FAN_OPEN | FAN_EVENT_ON_CHILD, DIR_PATH) == 0);
    make_file(FILE_C, "c");
    drain(g);
    fd = open(FILE_C, O_RDONLY);
    CHECK("child_open_event", expect_event(g, FAN_OPEN, 1), "no child open event");
    close(fd);
    drain(g);

    CHECK("mark_remove_known", fan_mark(g, FAN_MARK_REMOVE, FAN_OPEN | FAN_CLOSE_WRITE | FAN_CLOSE_NOWRITE | FAN_MODIFY, FILE_A) == 0, "errno=%d", errno);
    fd = open(FILE_A, O_RDONLY);
    close(fd);
    CHECK("removed_mark_is_silent", drain(g) == 0, "events after remove");

    CHECK("mark_flush", fan_mark(g, FAN_MARK_FLUSH, 0, 0) == 0, "errno=%d", errno);
    fd = open(FILE_C, O_RDONLY);
    close(fd);
    make_file(FILE_B, "b");
    unlink(FILE_B);
    CHECK("flushed_marks_are_silent", drain(g) == 0, "events after flush");

    errno = 0;
    CHECKC("mark_mount", fan_mark(g, FAN_MARK_ADD | FAN_MARK_MOUNT, FAN_OPEN, "/") == 0);
    fd = open(FILE_A, O_RDONLY);
    CHECK("mount_mark_open_event", expect_event(g, FAN_OPEN, 1), "no event under mount mark");
    close(fd);
    drain(g);
    fan_mark(g, FAN_MARK_FLUSH | FAN_MARK_MOUNT, 0, 0);

    errno = 0;
    CHECKC("mark_file_again", fan_mark(g, FAN_MARK_ADD, FAN_OPEN, FILE_A) == 0);
    int ep = epoll_create1(0);
    struct epoll_event ee = { EPOLLIN, { .fd = g } };
    CHECK("epoll_add", ep >= 0 && epoll_ctl(ep, EPOLL_CTL_ADD, g, &ee) == 0, "errno=%d", errno);
    fd = open(FILE_A, O_RDONLY);
    struct epoll_event out;
    CHECK("epoll_wait_ready", epoll_wait(ep, &out, 1, 1000) == 1 && out.data.fd == g, "no epoll event");
    close(fd);
    close(ep);
    drain(g);

    for (int i = 0; i < 40; i++) {
        fd = open(FILE_A, O_RDONLY);
        close(fd);
        fd = open(FILE_A, O_RDWR);
        close(fd);
    }
    int flood = drain(g);
    CHECK("queue_overflow_is_bounded", flood > 0 && flood <= 30, "flood=%d", flood);

    pid_t pid = fork();
    if (pid == 0) {
        _exit(setuid(1000) == 0 && fan_init(0, O_RDONLY) == -1 && errno == EPERM ? 0 : 1);
    }
    int st = 0;
    waitpid(pid, &st, 0);
    CHECK("unprivileged_init_refused", WIFEXITED(st) && WEXITSTATUS(st) == 0, "status=0x%x", st);

    close(g);
    fd = open(FILE_A, O_RDONLY);
    CHECKC("open_after_group_closed", fd >= 0);
    close(fd);
    unlink(FILE_A);
    unlink(FILE_C);
    rmdir(DIR_PATH);
    return 0;
}
