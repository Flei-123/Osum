#define TNAME "flock"
#include "t.h"
#include <dirent.h>
#include <fcntl.h>
#include <stdint.h>
#include <stdlib.h>
#include <sys/stat.h>
#include <sys/wait.h>

#define SLOT_COUNT 64
#define DIR_PATH "/tmp/flk"
#define LOCK_FILE DIR_PATH "/lockfile"
#define ENTRY_COUNT 300
#define ABSENT_COUNT 200
#define FNV_OFFSET 1469598103934665603ULL
#define FNV_PRIME 1099511628211ULL

struct dir_state {
    int entries;
    uint64_t name_hash_sum;
    int found;
    int absent_hits;
};

static uint64_t fnv(const char *s)
{
    uint64_t h = FNV_OFFSET;
    while (*s)
        h = (h ^ (unsigned char)*s++) * FNV_PRIME;
    return h;
}

static void entry_path(char *buf, int i)
{
    snprintf(buf, 64, DIR_PATH "/e%04d", i);
}

static void absent_path(char *buf, int i)
{
    snprintf(buf, 64, DIR_PATH "/x%04d", i);
}

static void populate(void)
{
    char p[64];
    mkdir(DIR_PATH, 0755);
    for (int i = 0; i < ENTRY_COUNT; i++) {
        entry_path(p, i);
        int fd = open(p, O_CREAT | O_WRONLY | O_TRUNC, 0644);
        if (fd >= 0) {
            (void)!write(fd, p, strlen(p));
            close(fd);
        }
    }
}

static void unpopulate(void)
{
    char p[64];
    for (int i = 0; i < ENTRY_COUNT; i++) {
        entry_path(p, i);
        unlink(p);
    }
    unlink(LOCK_FILE);
    rmdir(DIR_PATH);
}

static struct dir_state snapshot(void)
{
    struct dir_state s = {0, 0, 0, 0};
    char p[64];
    struct stat st;
    DIR *d = opendir(DIR_PATH);
    if (d) {
        struct dirent *e;
        while ((e = readdir(d))) {
            if (e->d_name[0] != 'e')
                continue;
            s.entries++;
            s.name_hash_sum += fnv(e->d_name);
        }
        closedir(d);
    }
    for (int i = 0; i < ENTRY_COUNT; i++) {
        entry_path(p, i);
        if (stat(p, &st) == 0 && st.st_size == (off_t)strlen(p))
            s.found++;
    }
    for (int i = 0; i < ABSENT_COUNT; i++) {
        absent_path(p, i);
        if (stat(p, &st) == 0)
            s.absent_hits++;
    }
    return s;
}

static int same_state(struct dir_state a, struct dir_state b)
{
    return a.entries == b.entries && a.name_hash_sum == b.name_hash_sum && a.found == b.found && a.absent_hits == b.absent_hits;
}

static int set_lock(int fd, short type, off_t start, off_t len)
{
    struct flock fl = {.l_type = type, .l_whence = SEEK_SET, .l_start = start, .l_len = len};
    return fcntl(fd, F_SETLK, &fl);
}

static int child_expects(int fds[], int count, short type, off_t len, int parent_pid, int ranged)
{
    int wrong = 0;
    for (int i = 0; i < count; i++) {
        off_t start = ranged ? i : 0;
        struct flock fl = {.l_type = F_WRLCK, .l_whence = SEEK_SET, .l_start = start, .l_len = len};
        int fd = ranged ? fds[0] : fds[i];
        if (fcntl(fd, F_GETLK, &fl) != 0) {
            wrong++;
            continue;
        }
        if (type == F_UNLCK) {
            if (fl.l_type != F_UNLCK)
                wrong++;
            continue;
        }
        if (fl.l_type != type || fl.l_start != start || fl.l_len != len || fl.l_pid != parent_pid)
            wrong++;
    }
    return wrong;
}

static int ask_child(int fds[], int count, short type, off_t len, int ranged)
{
    int parent_pid = getpid();
    pid_t c = fork();
    if (c == 0)
        _exit(child_expects(fds, count, type, len, parent_pid, ranged));
    int status = 0;
    waitpid(c, &status, 0);
    return WIFEXITED(status) ? WEXITSTATUS(status) : 255;
}

static void lock_all(int fds[], int count, short type, int ranged, int *failures)
{
    for (int i = 0; i < count; i++) {
        int fd = ranged ? fds[0] : fds[i];
        off_t start = ranged ? i : 0;
        if (set_lock(fd, type, start, 1) != 0)
            (*failures)++;
    }
}

static void unlock_all(int fds[], int count, int ranged)
{
    for (int i = 0; i < count; i++)
        set_lock(ranged ? fds[0] : fds[i], F_UNLCK, ranged ? i : 0, 1);
}

int main(void)
{
    populate();
    struct dir_state before = snapshot();
    CHECK("dir_before", before.entries == ENTRY_COUNT && before.found == ENTRY_COUNT && before.absent_hits == 0,
        "entries=%d found=%d absent_hits=%d", before.entries, before.found, before.absent_hits);

    int fds[SLOT_COUNT];
    int opened = 0;
    int one = open(LOCK_FILE, O_CREAT | O_RDWR, 0644);
    for (int i = 0; i < SLOT_COUNT; i++) {
        fds[i] = one;
        opened += one >= 0;
    }
    int failures = 0;
    lock_all(fds, SLOT_COUNT, F_WRLCK, 1, &failures);
    CHECK("ranges_all_set", opened == SLOT_COUNT && failures == 0, "failures=%d", failures);
    errno = 0;
    int over = set_lock(one, F_WRLCK, SLOT_COUNT, 1);
    CHECK("table_full_enolck", over == -1 && errno == ENOLCK, "r=%d errno=%d", over, errno);
    int wrong = ask_child(fds, SLOT_COUNT, F_WRLCK, 1, 1);
    CHECK("ranges_each_slot_readback", wrong == 0, "%d of %d slots read back wrong", wrong, SLOT_COUNT);
    failures = 0;
    lock_all(fds, SLOT_COUNT, F_RDLCK, 1, &failures);
    wrong = ask_child(fds, SLOT_COUNT, F_RDLCK, 1, 1);
    CHECK("ranges_convert_to_read", failures == 0 && wrong == 0, "failures=%d wrong=%d", failures, wrong);
    unlock_all(fds, SLOT_COUNT, 1);
    wrong = ask_child(fds, SLOT_COUNT, F_UNLCK, 1, 1);
    CHECK("ranges_unlock_all", wrong == 0, "%d slots still locked", wrong);

    struct dir_state mid = snapshot();
    CHECK("dir_after_ranges", same_state(before, mid), "entries=%d found=%d absent_hits=%d", mid.entries, mid.found, mid.absent_hits);

    int many[SLOT_COUNT];
    int opened_many = 0;
    for (int i = 0; i < SLOT_COUNT; i++) {
        char p[64];
        snprintf(p, sizeof p, DIR_PATH "/lockfile%d", i);
        many[i] = open(p, O_CREAT | O_RDWR, 0644);
        opened_many += many[i] >= 0;
    }
    failures = 0;
    lock_all(many, SLOT_COUNT, F_WRLCK, 0, &failures);
    CHECK("files_all_set", opened_many == SLOT_COUNT && failures == 0, "opened=%d failures=%d", opened_many, failures);
    wrong = ask_child(many, SLOT_COUNT, F_WRLCK, 1, 0);
    CHECK("files_each_slot_readback", wrong == 0, "%d of %d slots read back wrong", wrong, SLOT_COUNT);
    unlock_all(many, SLOT_COUNT, 0);
    wrong = ask_child(many, SLOT_COUNT, F_UNLCK, 1, 0);
    CHECK("files_unlock_all", wrong == 0, "%d files still locked", wrong);
    failures = 0;
    lock_all(many, SLOT_COUNT, F_WRLCK, 0, &failures);
    CHECK("slots_reusable", failures == 0, "failures=%d", failures);
    unlock_all(many, SLOT_COUNT, 0);

    struct dir_state after = snapshot();
    CHECK("dir_after_files", same_state(before, after), "entries=%d found=%d absent_hits=%d", after.entries, after.found, after.absent_hits);
    CHECK("dir_checksum_stable", before.name_hash_sum == after.name_hash_sum, "%llx vs %llx",
        (unsigned long long)before.name_hash_sum, (unsigned long long)after.name_hash_sum);

    for (int i = 0; i < SLOT_COUNT; i++) {
        char p[64];
        close(many[i]);
        snprintf(p, sizeof p, DIR_PATH "/lockfile%d", i);
        unlink(p);
    }
    close(one);
    unpopulate();
    return 0;
}
