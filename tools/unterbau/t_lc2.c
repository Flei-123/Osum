#define TNAME "lc2"
#include "t.h"
#include <poll.h>
#include <signal.h>
#include <stdlib.h>
#include <sys/ipc.h>
#include <sys/shm.h>
#include <sys/syscall.h>
#include <sys/wait.h>
#include <time.h>

static volatile int ticks;
static volatile int thread_hits;

static void on_usr1(int sig)
{
    (void)sig;
    ticks++;
}

static void on_thread(union sigval v)
{
    (void)v;
    thread_hits++;
}

static void wait_ticks(int want, long limit_ms)
{
    struct timespec nap = {0, 5000000};
    for (long waited = 0; ticks < want && waited < limit_ms; waited += 5)
        nanosleep(&nap, 0);
}

static void check_timer_signal(void)
{
    struct sigaction sa = {.sa_handler = on_usr1};
    sigaction(SIGUSR1, &sa, 0);
    struct sigevent ev = {.sigev_notify = SIGEV_SIGNAL, .sigev_signo = SIGUSR1};
    timer_t t;
    errno = 0;
    CHECKC("timer_create", timer_create(CLOCK_MONOTONIC, &ev, &t) == 0);
    struct itimerspec one = {{0, 0}, {0, 30000000}};
    errno = 0;
    CHECKC("timer_settime", timer_settime(t, 0, &one, 0) == 0);
    struct itimerspec cur;
    CHECK("timer_gettime", timer_gettime(t, &cur) == 0 && cur.it_value.tv_nsec > 0 && cur.it_value.tv_nsec <= 40000000,
          "left %ld", cur.it_value.tv_nsec);
    ticks = 0;
    wait_ticks(1, 1000);
    CHECK("timer_oneshot_signal", ticks == 1, "ticks=%d", ticks);
    struct timespec nap = {0, 100000000};
    nanosleep(&nap, 0);
    CHECK("timer_oneshot_once", ticks == 1, "ticks=%d", ticks);
    struct itimerspec per = {{0, 20000000}, {0, 20000000}};
    ticks = 0;
    timer_settime(t, 0, &per, 0);
    wait_ticks(3, 1500);
    CHECK("timer_periodic", ticks >= 3, "ticks=%d", ticks);
    CHECK("timer_getoverrun", timer_getoverrun(t) >= 0, "errno=%d", errno);
    struct itimerspec off = {{0, 0}, {0, 0}};
    timer_settime(t, 0, &off, 0);
    nanosleep(&nap, 0);
    int frozen = ticks;
    nanosleep(&nap, 0);
    CHECK("timer_disarm", ticks == frozen, "ticks %d -> %d", frozen, ticks);
    CHECK("timer_delete", timer_delete(t) == 0, "errno=%d", errno);
    errno = 0;
    CHECK("timer_stale_id", timer_gettime(t, &cur) == -1 && errno == EINVAL, "errno=%d", errno);
}

static void check_timer_none_and_thread(void)
{
    struct sigevent none = {.sigev_notify = SIGEV_NONE};
    timer_t t;
    errno = 0;
    CHECKC("timer_none_create", timer_create(CLOCK_REALTIME, &none, &t) == 0);
    struct itimerspec one = {{0, 0}, {0, 20000000}};
    timer_settime(t, 0, &one, 0);
    struct timespec nap = {0, 80000000};
    nanosleep(&nap, 0);
    struct itimerspec cur;
    timer_gettime(t, &cur);
    CHECK("timer_none_expired", cur.it_value.tv_sec == 0 && cur.it_value.tv_nsec == 0, "left %ld", cur.it_value.tv_nsec);
    timer_delete(t);
    struct sigevent th = {.sigev_notify = SIGEV_THREAD, .sigev_notify_function = on_thread};
    errno = 0;
    CHECKC("timer_thread_create", timer_create(CLOCK_MONOTONIC, &th, &t) == 0);
    timer_settime(t, 0, &one, 0);
    for (int i = 0; i < 200 && !thread_hits; i++) {
        struct timespec w = {0, 10000000};
        nanosleep(&w, 0);
    }
    CHECK("timer_thread_callback", thread_hits >= 1, "hits=%d", thread_hits);
    timer_delete(t);
}

static pid_t spawn_sleeper(int *gate)
{
    pid_t pid = fork();
    if (pid == 0) {
        close(gate[1]);
        char c;
        (void)!read(gate[0], &c, 1);
        _exit(7);
    }
    return pid;
}

static void check_pidfd(void)
{
    errno = 0;
    CHECK("pidfd_open_bad_pid", syscall(434, 0, 0) == -1 && errno == EINVAL, "errno=%d", errno);
    errno = 0;
    CHECK("pidfd_open_no_process", syscall(434, 900000, 0) == -1 && errno == ESRCH, "errno=%d", errno);
    int gate[2];
    if (pipe(gate))
        return;
    pid_t pid = spawn_sleeper(gate);
    errno = 0;
    int pfd = syscall(434, pid, 0);
    CHECKC("pidfd_open", pfd >= 0);
    if (pfd < 0)
        return;
    struct pollfd p = {pfd, POLLIN, 0};
    CHECK("pidfd_not_ready_alive", poll(&p, 1, 0) == 0, "revents=%d", p.revents);
    errno = 0;
    CHECK("pidfd_send_signal_probe", syscall(424, pfd, 0, 0, 0) == 0, "errno=%d", errno);
    int dup = syscall(438, pfd, gate[1], 0);
    CHECK("pidfd_getfd", dup >= 0 || errno == ENOSYS, "errno=%d", errno);
    if (dup >= 0) {
        CHECK("pidfd_getfd_same_object", write(gate[1], "x", 1) == 1 && write(dup, "y", 1) == 1, "errno=%d", errno);
        close(dup);
    }
    p.revents = 0;
    int r = poll(&p, 1, 3000);
    CHECK("pidfd_ready_on_exit", r == 1 && (p.revents & POLLIN), "r=%d revents=%d", r, p.revents);
    errno = 0;
    CHECK("pidfd_signal_zombie_gone", syscall(424, pfd, SIGTERM, 0, 0) == -1 && errno == ESRCH, "errno=%d", errno);
    int st = 0;
    CHECK("pidfd_reaped_status", waitpid(pid, &st, 0) == pid && WIFEXITED(st) && WEXITSTATUS(st) == 7, "st=%d", st);
    close(pfd);
    int none[2];
    if (pipe(none))
        return;
    pid_t victim = fork();
    if (victim == 0) {
        for (;;)
            pause();
    }
    int vfd = syscall(434, victim, 0);
    CHECK("pidfd_send_signal_kill", vfd >= 0 && syscall(424, vfd, SIGKILL, 0, 0) == 0, "errno=%d", errno);
    if (vfd < 0)
        kill(victim, SIGKILL);
    waitpid(victim, &st, 0);
    CHECK("pidfd_killed_status", WIFSIGNALED(st) && WTERMSIG(st) == SIGKILL, "st=%d", st);
    close(vfd);
    close(gate[0]);
    close(gate[1]);
    close(none[0]);
    close(none[1]);
}

static void check_shm(void)
{
    errno = 0;
    int id = shmget(IPC_PRIVATE, 8192, IPC_CREAT | 0600);
    CHECKC("shmget", id >= 0);
    if (id < 0)
        return;
    char *a = shmat(id, 0, 0);
    CHECKC("shmat", a != (void *)-1);
    if (a == (void *)-1)
        return;
    memset(a, 0, 8192);
    strcpy(a, "hello");
    a[8191] = 'z';
    struct shmid_ds ds;
    CHECK("shmctl_stat", shmctl(id, IPC_STAT, &ds) == 0 && ds.shm_segsz == 8192 && ds.shm_nattch == 1, "size %lu nattch %lu",
          (unsigned long)ds.shm_segsz, (unsigned long)ds.shm_nattch);
    pid_t pid = fork();
    if (pid == 0) {
        char *b = shmat(id, 0, 0);
        if (b == (void *)-1)
            _exit(2);
        int ok = strcmp(b, "hello") == 0 && b[8191] == 'z';
        strcpy(b, "child");
        shmdt(b);
        _exit(ok ? 0 : 3);
    }
    int st = 0;
    waitpid(pid, &st, 0);
    CHECK("shm_child_saw_parent", WIFEXITED(st) && WEXITSTATUS(st) == 0, "st=%d", st);
    CHECK("shm_parent_sees_child", strcmp(a, "child") == 0, "got %s", a);
    key_t key = 0x5eed1c20;
    int kid = shmget(key, 4096, IPC_CREAT | IPC_EXCL | 0600);
    errno = 0;
    CHECK("shmget_excl", kid >= 0 && shmget(key, 4096, IPC_CREAT | IPC_EXCL | 0600) == -1 && errno == EEXIST, "errno=%d", errno);
    CHECK("shmget_find", shmget(key, 0, 0) == kid, "kid=%d got=%d", kid, shmget(key, 0, 0));
    char *ro = shmat(kid, 0, SHM_RDONLY);
    CHECK("shmat_rdonly", ro != (void *)-1 && ro[0] == 0, "errno=%d", errno);
    if (ro != (void *)-1)
        shmdt(ro);
    CHECK("shmdt", shmdt(a) == 0, "errno=%d", errno);
    errno = 0;
    CHECK("shmdt_twice", shmdt(a) == -1 && errno == EINVAL, "errno=%d", errno);
    CHECK("shmctl_rmid", shmctl(id, IPC_RMID, 0) == 0 && shmctl(kid, IPC_RMID, 0) == 0, "errno=%d", errno);
    errno = 0;
    CHECK("shm_stale_id", shmat(id, 0, 0) == (void *)-1 && errno == EINVAL, "errno=%d", errno);
}

int main(void)
{
    alarm(90);
    check_shm();
    check_pidfd();
    check_timer_signal();
    check_timer_none_and_thread();
    return 0;
}
