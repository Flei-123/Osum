#define TNAME "memfdcycle"
#include "t.h"
#include <fcntl.h>
#include <pthread.h>
#include <stdint.h>
#include <sys/mman.h>
#include <sys/syscall.h>

#define CYCLES 300
#define MAP_LEN 766912
#define RING 8
#define SEALS 23
#define MFD_FLAGS 11
#define ROOM_TARGET 64
#define ROOM_MAX 100

struct item {
    int writable_fd;
    int readonly_fd;
    void *map;
};

struct outcome {
    int ok;
    int first_bad_cycle;
    int stage;
    int err;
};

static const struct item EMPTY_ITEM = { -1, -1, MAP_FAILED };

static int make_item(struct item *it)
{
    char path[48];
    *it = EMPTY_ITEM;
    it->writable_fd = (int)syscall(SYS_memfd_create, "cyc", MFD_FLAGS);
    if (it->writable_fd < 0) return 1;
    if (ftruncate(it->writable_fd, MAP_LEN) != 0) return 2;
    snprintf(path, sizeof path, "/proc/self/fd/%d", it->writable_fd);
    it->readonly_fd = open(path, O_RDONLY);
    if (it->readonly_fd < 0) return 3;
    fcntl(it->readonly_fd, F_SETFD, FD_CLOEXEC);
    it->map = mmap(0, MAP_LEN, PROT_READ, MAP_SHARED, it->readonly_fd, 0);
    if (it->map == MAP_FAILED) return 4;
    if (fcntl(it->writable_fd, F_ADD_SEALS, SEALS) != 0) return 5;
    return 0;
}

static void drop_item(struct item *it)
{
    if (it->map != MAP_FAILED) munmap(it->map, MAP_LEN);
    if (it->readonly_fd >= 0) close(it->readonly_fd);
    if (it->writable_fd >= 0) close(it->writable_fd);
    *it = EMPTY_ITEM;
}

static void note(struct outcome *o, int cycle, int stage)
{
    if (stage == 0) {
        o->ok++;
        return;
    }
    if (o->first_bad_cycle < 0) {
        o->first_bad_cycle = cycle;
        o->stage = stage;
        o->err = errno;
    }
}

static void begin(struct outcome *o)
{
    o->ok = 0;
    o->first_bad_cycle = -1;
    o->stage = 0;
    o->err = 0;
}

static void run_single(struct outcome *o)
{
    struct item it;
    begin(o);
    for (int i = 0; i < CYCLES; i++) {
        note(o, i, make_item(&it));
        drop_item(&it);
    }
}

static void run_ring(struct outcome *o)
{
    struct item ring[RING];
    for (int i = 0; i < RING; i++) ring[i] = EMPTY_ITEM;
    begin(o);
    for (int i = 0; i < CYCLES; i++) {
        struct item *slot = &ring[i % RING];
        drop_item(slot);
        note(o, i, make_item(slot));
    }
    for (int i = 0; i < RING; i++) drop_item(&ring[i]);
}

struct job {
    struct item *it;
    int stage;
};

static void *make_thread(void *arg)
{
    struct job *j = arg;
    j->stage = make_item(j->it);
    return 0;
}

static void *drop_thread(void *arg)
{
    struct job *j = arg;
    drop_item(j->it);
    return 0;
}

static void run_made_by_thread(struct outcome *o)
{
    struct item it = EMPTY_ITEM;
    struct job j = { &it, 0 };
    pthread_t t;
    begin(o);
    for (int i = 0; i < CYCLES; i++) {
        if (pthread_create(&t, 0, make_thread, &j) != 0) {
            note(o, i, 6);
            continue;
        }
        pthread_join(t, 0);
        note(o, i, j.stage);
        drop_item(&it);
    }
}

static void run_dropped_by_thread(struct outcome *o)
{
    struct item it = EMPTY_ITEM;
    struct job j = { &it, 0 };
    pthread_t t;
    begin(o);
    for (int i = 0; i < CYCLES; i++) {
        note(o, i, make_item(&it));
        if (pthread_create(&t, 0, drop_thread, &j) != 0) {
            drop_item(&it);
            continue;
        }
        pthread_join(t, 0);
    }
}

static int room_left(void)
{
    int fds[ROOM_MAX];
    int n = 0;
    while (n < ROOM_MAX) {
        fds[n] = (int)syscall(SYS_memfd_create, "room", MFD_FLAGS);
        if (fds[n] < 0) break;
        n++;
    }
    for (int i = 0; i < n; i++) close(fds[i]);
    return n;
}

static void report(const char *name, const struct outcome *o)
{
    CHECK(name, o->ok == CYCLES, "ok=%d of %d first_bad_cycle=%d stage=%d errno=%d", o->ok, CYCLES, o->first_bad_cycle, o->stage, o->err);
}

static void report_leak(const char *name, int base)
{
    int room = room_left();
    CHECK(name, room >= base, "base=%d room=%d", base, room);
}

int main(void)
{
    struct outcome o;
    int base = room_left();
    CHECK("table_room_at_start", base >= ROOM_TARGET, "room=%d", base);
    run_single(&o);
    report("single_thread_cycles", &o);
    report_leak("single_thread_no_leak", base);
    run_ring(&o);
    report("ring_cycles", &o);
    report_leak("ring_no_leak", base);
    run_made_by_thread(&o);
    report("made_by_exited_thread", &o);
    report_leak("made_by_exited_thread_no_leak", base);
    run_dropped_by_thread(&o);
    report("dropped_by_other_thread", &o);
    report_leak("dropped_by_other_thread_no_leak", base);
    return 0;
}
