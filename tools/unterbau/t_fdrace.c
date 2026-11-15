#define TNAME "fdrace"
#include "t.h"
#include <fcntl.h>
#include <pthread.h>
#include <stdlib.h>
#include <sys/socket.h>
#include <sys/stat.h>
#include <sys/wait.h>
#include <time.h>

#define NW 4
#define SECONDS 4
#define DIR "/tmp/fdr"

static volatile int stop;
static volatile unsigned long rounds, bad_open, bad_held, bad_sock, bad_rename;

static void tag_of(char *buf, int kind, int id) { snprintf(buf, 16, "tag-%c-%02d", kind, id % 100); }

static int read_tag(int fd, const char *want)
{
    char got[16] = {0};
    return pread(fd, got, 9, 0) == 9 && memcmp(got, want, 9) == 0;
}

static void write_file(const char *path, const char *tag)
{
    int fd = open(path, O_WRONLY | O_CREAT | O_TRUNC, 0644);
    if (fd >= 0) { (void)!write(fd, tag, 9); close(fd); }
}

static int elapsed(struct timespec *t0)
{
    struct timespec t1;
    clock_gettime(CLOCK_MONOTONIC, &t1);
    return t1.tv_sec - t0->tv_sec >= SECONDS;
}

static int proc_worker(int id)
{
    char path[64], held_path[64], tag[16], held_tag[16];
    snprintf(path, sizeof path, DIR "/p%d", id);
    snprintf(held_path, sizeof held_path, DIR "/ph%d", id);
    tag_of(tag, 'p', id);
    tag_of(held_tag, 'h', id);
    write_file(path, tag);
    write_file(held_path, held_tag);
    int held = open(held_path, O_RDONLY);
    int bad = 0, n = 0;
    struct timespec t0;
    clock_gettime(CLOCK_MONOTONIC, &t0);
    while (!elapsed(&t0)) {
        int fd = open(path, O_RDONLY);
        if (fd < 0 || !read_tag(fd, tag)) bad++;
        if (fd >= 0) close(fd);
        if (held < 0 || !read_tag(held, held_tag)) bad++;
        n++;
    }
    return bad > 0 ? 1 : (n < 100 ? 2 : 0);
}

static void check_procs(void)
{
    pid_t pid[NW];
    int started = 0, bad = 0, idle = 0;
    for (int k = 0; k < NW; k++) {
        pid[k] = fork();
        if (pid[k] == 0) _exit(proc_worker(k));
        if (pid[k] > 0) started++;
    }
    for (int k = 0; k < NW; k++) {
        int st = 0;
        if (pid[k] <= 0 || waitpid(pid[k], &st, 0) != pid[k] || !WIFEXITED(st)) { bad++; continue; }
        if (WEXITSTATUS(st) == 1) bad++;
        if (WEXITSTATUS(st) == 2) idle++;
    }
    CHECK("procs_started", started == NW, "started=%d", started);
    CHECK("procs_own_files", bad == 0, "bad_procs=%d of %d", bad, NW);
    CHECK("procs_rounds", idle == 0, "idle_procs=%d", idle);
}

static void one_thread_round(int id, int held, const char *held_tag, int sv[2])
{
    char tmp[64], fin[64], tag[16];
    snprintf(tmp, sizeof tmp, DIR "/t%d.tmp", id);
    snprintf(fin, sizeof fin, DIR "/t%d", id);
    tag_of(tag, 't', id);
    write_file(tmp, tag);
    if (rename(tmp, fin) != 0) __sync_fetch_and_add(&bad_rename, 1);
    int fd = open(fin, O_RDONLY);
    if (fd < 0 || !read_tag(fd, tag)) __sync_fetch_and_add(&bad_open, 1);
    if (fd >= 0) close(fd);
    if (!read_tag(held, held_tag)) __sync_fetch_and_add(&bad_held, 1);
    char got[16] = {0};
    if (write(sv[0], tag, 9) != 9 || read(sv[1], got, 9) != 9 || memcmp(got, tag, 9) != 0) __sync_fetch_and_add(&bad_sock, 1);
    int s = socket(AF_UNIX, SOCK_STREAM, 0);
    if (s >= 0) close(s);
}

static void *thread_worker(void *arg)
{
    int id = (int)(long)arg + 10;
    char held_path[64], held_tag[16];
    snprintf(held_path, sizeof held_path, DIR "/th%d", id);
    tag_of(held_tag, 'h', id);
    write_file(held_path, held_tag);
    int held = open(held_path, O_RDONLY);
    int sv[2] = {-1, -1};
    if (socketpair(AF_UNIX, SOCK_STREAM, 0, sv) != 0) __sync_fetch_and_add(&bad_sock, 1);
    while (!stop) {
        one_thread_round(id, held, held_tag, sv);
        __sync_fetch_and_add(&rounds, 1);
    }
    return 0;
}

static void check_threads(void)
{
    pthread_t th[NW];
    int started = 0;
    for (long i = 0; i < NW; i++) if (pthread_create(&th[i], 0, thread_worker, (void *)i) == 0) started++;
    struct timespec t0;
    clock_gettime(CLOCK_MONOTONIC, &t0);
    while (!elapsed(&t0)) {
        struct timespec ts = {0, 100 * 1000 * 1000};
        nanosleep(&ts, 0);
    }
    stop = 1;
    for (int i = 0; i < started; i++) pthread_join(th[i], 0);
    struct stat st;
    CHECK("threads_started", started == NW, "started=%d", started);
    CHECK("threads_rounds", rounds > 100, "rounds=%lu", rounds);
    CHECK("threads_open_read", bad_open == 0, "bad=%lu of %lu", bad_open, rounds);
    CHECK("threads_held_fd", bad_held == 0, "bad=%lu of %lu", bad_held, rounds);
    CHECK("threads_socketpair", bad_sock == 0, "bad=%lu of %lu", bad_sock, rounds);
    CHECK("threads_rename", bad_rename == 0, "bad=%lu of %lu", bad_rename, rounds);
    CHECK("stdout_alive", fstat(1, &st) == 0 && write(1, "", 0) == 0, "errno=%d", errno);
}

int main(void)
{
    mkdir("/tmp", 0777);
    mkdir(DIR, 0777);
    check_procs();
    check_threads();
    return 0;
}
