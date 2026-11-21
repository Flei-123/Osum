#define TNAME "inotifymod"
#include "t.h"
#include <fcntl.h>
#include <poll.h>
#include <stdint.h>
#include <sys/inotify.h>

#define WORK_DIR "/tmp/inmod"
#define WORK_FILE "/tmp/inmod/f.txt"
#define MOVED_FILE "/tmp/inmod/g.txt"
#define EVENT_BUF 1024

struct seen {
    uint32_t mask;
    int wd;
    char name[24];
};

static int collect(int in, struct seen *out, int max)
{
    char buf[EVENT_BUF];
    ssize_t n = read(in, buf, sizeof buf);
    int count = 0;
    for (char *q = buf; n > 0 && q < buf + n && count < max;) {
        struct inotify_event *e = (struct inotify_event *)q;
        out[count].mask = e->mask;
        out[count].wd = e->wd;
        out[count].name[0] = 0;
        if (e->len)
            strncpy(out[count].name, e->name, sizeof out[count].name - 1);
        out[count].name[sizeof out[count].name - 1] = 0;
        count++;
        q += sizeof *e + e->len;
    }
    return count;
}

static void append(const char *path)
{
    int f = open(path, O_WRONLY | O_APPEND | O_CREAT, 0644);
    if (f >= 0) {
        (void)!write(f, "x", 1);
        close(f);
    }
}

static void drain(int in)
{
    struct seen s[16];
    collect(in, s, 16);
}

int main(void)
{
    (void)!mkdir(WORK_DIR, 0755);
    append(WORK_FILE);
    int in = inotify_init1(IN_NONBLOCK | IN_CLOEXEC);
    if (in < 0) {
        FAIL("file_watch_modify", "inotify_init1 errno %d", errno);
        return 0;
    }
    struct seen s[16];
    int fwd = inotify_add_watch(in, WORK_FILE, IN_MODIFY | IN_DELETE_SELF | IN_MOVE_SELF);
    append(WORK_FILE);
    struct pollfd p = { in, POLLIN, 0 };
    int ready = poll(&p, 1, 0);
    int n = collect(in, s, 16);
    CHECK("file_watch_poll_ready", ready == 1, "poll -> %d", ready);
    CHECK("file_watch_modify", n == 1 && s[0].mask == IN_MODIFY && s[0].wd == fwd && s[0].name[0] == 0, "n=%d mask %x name '%s'", n, n ? s[0].mask : 0, n ? s[0].name : "");
    errno = 0;
    char b[EVENT_BUF];
    CHECK("file_watch_idle_after_drain", read(in, b, sizeof b) == -1 && errno == EAGAIN, "events left");

    int rd = open(WORK_FILE, O_RDONLY);
    char rb[4];
    (void)!read(rd, rb, sizeof rb);
    close(rd);
    n = collect(in, s, 16);
    CHECK("read_open_is_silent", n == 0, "%d events from a read-only open", n);

    int wd2 = inotify_add_watch(in, WORK_DIR, IN_MODIFY | IN_CREATE);
    drain(in);
    append(WORK_FILE);
    n = collect(in, s, 16);
    int dir_hit = 0, file_hit = 0;
    for (int i = 0; i < n; i++) {
        if (s[i].wd == wd2 && s[i].mask == IN_MODIFY && !strcmp(s[i].name, "f.txt"))
            dir_hit = 1;
        if (s[i].wd == fwd && s[i].mask == IN_MODIFY && s[i].name[0] == 0)
            file_hit = 1;
    }
    CHECK("dir_watch_modify_names_child", dir_hit, "n=%d", n);
    CHECK("file_and_dir_both_notified", file_hit && dir_hit, "file %d dir %d", file_hit, dir_hit);

    drain(in);
    int f = open(WORK_FILE, O_WRONLY | O_APPEND);
    (void)!write(f, "a", 1);
    (void)!write(f, "b", 1);
    close(f);
    n = collect(in, s, 16);
    int modifies = 0;
    for (int i = 0; i < n; i++)
        if (s[i].mask == IN_MODIFY && s[i].wd == fwd)
            modifies++;
    CHECK("each_write_reports", modifies == 2, "%d modify events for two writes", modifies);

    drain(in);
    (void)!rename(WORK_FILE, MOVED_FILE);
    n = collect(in, s, 16);
    int moved_self = 0;
    for (int i = 0; i < n; i++)
        if (s[i].wd == fwd && s[i].mask == IN_MOVE_SELF)
            moved_self = 1;
    CHECK("move_self", moved_self, "n=%d", n);

    int gwd = inotify_add_watch(in, MOVED_FILE, IN_DELETE_SELF);
    drain(in);
    (void)!unlink(MOVED_FILE);
    n = collect(in, s, 16);
    int deleted_self = 0;
    for (int i = 0; i < n; i++)
        if (s[i].wd == gwd && s[i].mask == IN_DELETE_SELF)
            deleted_self = 1;
    CHECK("delete_self", deleted_self, "n=%d", n);

    inotify_rm_watch(in, fwd);
    inotify_rm_watch(in, wd2);
    inotify_rm_watch(in, gwd);
    close(in);
    append(WORK_FILE);
    (void)!unlink(WORK_FILE);
    (void)!rmdir(WORK_DIR);
    PASS("cleanup");
    return 0;
}
