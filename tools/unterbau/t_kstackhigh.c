/* SPDX-License-Identifier: GPL-2.0-only
 * Kernel stacks of user tasks come from frames above the first GiB: with the window nearly empty, many parked threads still start, each
 * costs far fewer low frames than a 33-frame kernel stack, and syscalls made on those stacks (file read, pipes) return right data. */
#define TNAME "kstackhigh"
#include "t.h"
#include "lowpress.h"
#include <pthread.h>
#include <sys/wait.h>

#define LEAVE_FRAMES 4096
#define THREADS 100
#define LOW_PER_THREAD_BUDGET 12
#define THREAD_STACK_BYTES (64 * 1024)
#define READ_BYTES (1 << 20)

static volatile int release_flag;
static volatile int started;
static volatile int read_ok;

static void *worker(void *arg)
{
    static __thread char local[8192];
    int fd = open("/tmp/lowpress.dat", O_RDONLY);
    long got = 0;
    if (fd >= 0) {
        long n;
        while (got < READ_BYTES && (n = read(fd, local, sizeof local)) > 0) got += n;
        close(fd);
    }
    __sync_fetch_and_add(&started, 1);
    if (got == READ_BYTES) __sync_fetch_and_add(&read_ok, 1);
    while (!release_flag) usleep(20000);
    return arg;
}

int main(void)
{
    long total_kb = lp_meminfo("MemTotal:");
    CHECK("memory_above_window", total_kb > 2L * 1024 * 1024 && lp_free_low() > 0, "total=%ldkB low=%ld", total_kb, lp_free_low());
    long held = lowpress_eat(LEAVE_FRAMES);
    long low0 = lp_free_low();
    CHECK("window_tight", held >= 0 && low0 <= LEAVE_FRAMES + 512, "held=%ld low=%ld", held, low0);

    pthread_attr_t attr;
    pthread_attr_init(&attr);
    pthread_attr_setstacksize(&attr, THREAD_STACK_BYTES);
    pthread_t t[THREADS];
    int created = 0;
    for (int i = 0; i < THREADS; i++)
        if (pthread_create(&t[i], &attr, worker, 0) == 0) created++;
    for (int spin = 0; spin < 500 && started < created; spin++) usleep(20000);
    long low1 = lp_free_low();
    CHECK("all_threads_created", created == THREADS, "created=%d", created);
    CHECK("all_threads_ran", started == created, "started=%d created=%d", started, created);
    CHECK("syscalls_on_high_stacks", read_ok == created, "read_ok=%d created=%d", read_ok, created);
    long per_thread = created ? (low0 - low1) / created : 0;
    CHECK("low_cost_per_thread", per_thread >= 0 && per_thread <= LOW_PER_THREAD_BUDGET, "per_thread=%ld low0=%ld low1=%ld", per_thread, low0, low1);

    release_flag = 1;
    int joined = 0;
    for (int i = 0; i < created; i++)
        if (pthread_join(t[i], 0) == 0) joined++;
    CHECK("all_joined", joined == created, "joined=%d", joined);
    usleep(200000);
    long low2 = lp_free_low();
    CHECK("frames_returned", low2 >= low1 + created, "low1=%ld low2=%ld", low1, low2);

    int kids = 0, good = 0;
    for (int i = 0; i < 24; i++) {
        pid_t p = fork();
        if (p == 0) _exit(i % 7);
        if (p > 0) {
            int st;
            kids++;
            if (waitpid(p, &st, 0) == p && WIFEXITED(st) && WEXITSTATUS(st) == i % 7) good++;
        }
    }
    CHECK("fork_exit_wait", kids == 24 && good == 24, "kids=%d good=%d", kids, good);
    unlink("/tmp/lowpress.dat");
    return 0;
}
