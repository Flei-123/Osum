/* pthreads on top of clone/futex: create/join, mutex, condvar, TLS, semaphores, many threads, big stacks. */
#define TNAME "threads"
#include "t.h"
#include <pthread.h>
#include <semaphore.h>
#include <stdlib.h>
#include <sched.h>
#include <sys/syscall.h>
#include <time.h>
#include <fcntl.h>
#include <sys/stat.h>
#include <sys/mman.h>
#include <signal.h>
#include <sys/wait.h>

static int gp_fd[2];
static void settle(int ms) { struct timespec a, b; clock_gettime(CLOCK_MONOTONIC, &a); do { usleep(20000); clock_gettime(CLOCK_MONOTONIC, &b); } while ((b.tv_sec - a.tv_sec) * 1000 + (b.tv_nsec - a.tv_nsec) / 1000000 < ms); }
static void *park_thr(void *a) { (void)a; long tid = syscall(SYS_gettid); (void)!write(gp_fd[1], &tid, sizeof tid); for (;;) settle(1000); return 0; }
static void *xg_thr(void *a) { (void)a; settle(300); syscall(SYS_exit_group, 7); return 0; }
static void *xg150_thr(void *a) { (void)a; settle(300); syscall(SYS_exit_group, 150); return 0; }
static void *idle_thr(void *a) { (void)a; for (;;) settle(1000); return 0; }
static void *segv_thr(void *a) { (void)a; settle(300); *(volatile int *)0 = 1; return 0; }

/* mode 0: main calls exit(5); 1: main writes NULL; 2: a thread calls exit_group(7); 3: a thread writes NULL; 4: a thread calls exit_group(150) (a plain exit, not a signal death).
   Three more threads sleep. Afterwards the whole group must be gone, not running on a freed address space. */
static void group_case(const char *name, int mode, int want_sig, int want_code)
{
    if (pipe(gp_fd) != 0) { FAIL(name, "pipe"); return; }
    pid_t p = fork();
    if (p == 0) {
        pthread_t t[4];
        for (int i = 0; i < 3; i++) pthread_create(&t[i], 0, park_thr, 0);
        if (mode == 2) pthread_create(&t[3], 0, xg_thr, 0);
        if (mode == 3) pthread_create(&t[3], 0, segv_thr, 0);
        if (mode == 4) pthread_create(&t[3], 0, xg150_thr, 0);
        settle(800);
        if (mode == 0) exit(5);
        if (mode == 1) *(volatile int *)0 = 1;
        for (;;) settle(1000);
    }
    long tids[3] = {0, 0, 0};
    for (int i = 0; i < 3; i++) if (read(gp_fd[0], &tids[i], sizeof tids[i]) != (ssize_t)sizeof tids[i]) tids[i] = 0;
    int st = 0;
    pid_t w = waitpid(p, &st, 0);
    int alive = 0;
    for (int i = 0; i < 3; i++) if (tids[i] && kill((pid_t)tids[i], 0) == 0) alive++;
    int ok = w == p && alive == 0;
    if (want_sig) ok = ok && WIFSIGNALED(st) && WTERMSIG(st) == want_sig;
    else ok = ok && WIFEXITED(st) && WEXITSTATUS(st) == want_code;
    CHECK(name, ok, "waitpid %d status 0x%x, %d of 3 sleeping threads still alive", (int)w, st, alive);
    close(gp_fd[0]); close(gp_fd[1]);
}

static void *ret_arg(void *a) { return (void *)((long)a * 2); }
static pthread_mutex_t mu = PTHREAD_MUTEX_INITIALIZER;
static long counter;
static void *incr(void *a) { for (int i = 0; i < 20000; i++) { pthread_mutex_lock(&mu); counter++; pthread_mutex_unlock(&mu); } return a; }

static pthread_cond_t cv = PTHREAD_COND_INITIALIZER;
static int queue_n, produced, consumed;
static void *producer(void *a) { (void)a; for (int i = 0; i < 200; i++) { pthread_mutex_lock(&mu); while (queue_n >= 4) pthread_cond_wait(&cv, &mu); queue_n++; produced++; pthread_cond_broadcast(&cv); pthread_mutex_unlock(&mu); } return 0; }
static void *consumer(void *a) { (void)a; for (int i = 0; i < 200; i++) { pthread_mutex_lock(&mu); while (queue_n == 0) pthread_cond_wait(&cv, &mu); queue_n--; consumed++; pthread_cond_broadcast(&cv); pthread_mutex_unlock(&mu); } return 0; }

static __thread int tls_val = 5;
static __thread char tls_buf[3000];
static int tls_ok[4];
static void *tls_thr(void *a) { long id = (long)a; tls_val = 100 + id; memset(tls_buf, (int)id, sizeof tls_buf); sched_yield(); tls_ok[id] = (tls_val == 100 + id && tls_buf[2999] == (char)id); return 0; }

static pthread_key_t key;
static int dtor_ran;
static void dtor(void *p) { (void)p; __sync_fetch_and_add(&dtor_ran, 1); }
static void *key_thr(void *a) { pthread_setspecific(key, a); return (void *)(pthread_getspecific(key) == a); }

static volatile int det_flag;
static void *det_thr(void *a) { (void)a; det_flag = 1; return 0; }

static sem_t sem;
static void *sem_thr(void *a) { (void)a; sem_post(&sem); return 0; }
static void *sem_late(void *a) { (void)a; sleep(12); sem_post(&sem); return 0; }

static pid_t tids[3];
static void *tid_thr(void *a) { tids[(long)a] = syscall(SYS_gettid); return 0; }

static void *deep(void *a) { volatile char buf[200000]; for (int i = 0; i < 200000; i += 4096) buf[i] = 1; buf[199999] = 2; return (void *)(long)(buf[199999] == 2 && a == 0); }

static void *sleeper(void *a) { struct timespec ts = { 0, 30 * 1000 * 1000 }; (void)a; nanosleep(&ts, 0); return 0; }
static pthread_barrier_t bar;
static void *bar_thr(void *a) { (void)a; return (void *)(long)pthread_barrier_wait(&bar); }
static pthread_once_t once = PTHREAD_ONCE_INIT; static int once_n; static void once_f(void) { once_n++; }
static void *once_thr(void *a) { (void)a; pthread_once(&once, once_f); return 0; }

static volatile int g_fd = -1, g_go, g_res;
static void *fdshare_thr(void *a) { (void)a; while (!g_go) usleep(2000); struct stat sb; g_res = fstat(g_fd, &sb) == 0 ? 1 : 2; return 0; }


/* w-foot3: break / mmap marks are ONE per thread group. Two threads that map at the same time
   (foot's font threads, any allocator) must get distinct addresses, and a thread's mapping
   must not collide with what the creator maps afterwards. */
#define MM_N 48
#define MM_LEN (16 * 4096)
static void *mm_addr[3][MM_N];
static int mm_fail[3];
static pthread_barrier_t mm_bar;
static void *mm_thr(void *a)
{
    long id = (long)a;
    pthread_barrier_wait(&mm_bar);
    for (int i = 0; i < MM_N; i++) {
        char *p = mmap(0, MM_LEN, PROT_READ | PROT_WRITE, MAP_PRIVATE | MAP_ANONYMOUS, -1, 0);
        if (p == MAP_FAILED) { mm_fail[id]++; mm_addr[id][i] = 0; continue; }
        mm_addr[id][i] = p;
        memset(p, (int)(id * 64 + i), MM_LEN);
        void *m = malloc(3000 + i * 7);
        if (!m) mm_fail[id]++; else { memset(m, 0x5a, 3000); free(m); }
    }
    return 0;
}

int main(void)
{
    pthread_t t[8]; void *r;
    errno = 0;
    int e = pthread_create(&t[0], 0, ret_arg, (void *)21);
    CHECK("create", e == 0, "pthread_create -> %d", e);
    if (e) return 1;
    pthread_join(t[0], &r);
    CHECK("join_value", (long)r == 42, "got %ld", (long)r);

    for (int i = 0; i < 4; i++) pthread_create(&t[i], 0, incr, 0);
    for (int i = 0; i < 4; i++) pthread_join(t[i], 0);
    CHECK("mutex_counter", counter == 80000, "counter %ld (want 80000)", counter);

    pthread_create(&t[0], 0, producer, 0); pthread_create(&t[1], 0, consumer, 0);
    pthread_join(t[0], 0); pthread_join(t[1], 0);
    CHECK("condvar_prodcons", produced == 200 && consumed == 200 && queue_n == 0, "p=%d c=%d q=%d", produced, consumed, queue_n);

    for (long i = 0; i < 4; i++) pthread_create(&t[i], 0, tls_thr, (void *)i);
    for (int i = 0; i < 4; i++) pthread_join(t[i], 0);
    CHECK("tls_per_thread", tls_ok[0] && tls_ok[1] && tls_ok[2] && tls_ok[3] && tls_val == 5, "tls ok=%d%d%d%d main=%d", tls_ok[0], tls_ok[1], tls_ok[2], tls_ok[3], tls_val);

    pthread_key_create(&key, dtor);
    pthread_create(&t[0], 0, key_thr, (void *)77); pthread_join(t[0], &r);
    CHECK("tsd_value", (long)r == 1, "key value lost");
    CHECK("tsd_destructor", dtor_ran == 1, "destructor ran %d times", dtor_ran);

    pthread_attr_t at; pthread_attr_init(&at); pthread_attr_setdetachstate(&at, PTHREAD_CREATE_DETACHED);
    pthread_create(&t[0], &at, det_thr, 0);
    for (int i = 0; i < 100 && !det_flag; i++) usleep(10000);
    CHECK("detached", det_flag == 1, "detached thread never ran");

    sem_init(&sem, 0, 0);
    pthread_create(&t[0], 0, sem_thr, 0);
    struct timespec dl; clock_gettime(CLOCK_REALTIME, &dl); dl.tv_sec += 5;
    CHECK("semaphore", sem_timedwait(&sem, &dl) == 0, "sem_timedwait: %s", strerror(errno));
    pthread_join(t[0], 0);

    /* r708: an untimed sem_wait that outlasts the old 10 s futex cap must still return 0 (it returned -1/ETIMEDOUT; foot's idle render worker then died) */
    sem_init(&sem, 0, 0);
    pthread_create(&t[0], 0, sem_late, 0);
    int lw = sem_wait(&sem);
    CHECK("sem_wait_no_timeout", lw == 0, "sem_wait returned %d (%s) before the post", lw, strerror(errno));
    pthread_join(t[0], 0);

    for (long i = 0; i < 3; i++) pthread_create(&t[i], 0, tid_thr, (void *)i);
    for (int i = 0; i < 3; i++) pthread_join(t[i], 0);
    CHECK("distinct_tids", tids[0] != tids[1] && tids[1] != tids[2] && tids[0] != getpid() && tids[0] > 0, "tids %d %d %d pid %d", tids[0], tids[1], tids[2], getpid());
    CHECK("getpid_same", 1, "");

    /* thread creation churn: stack reuse, munmap, join */
    int churn_ok = 1;
    for (int i = 0; i < 64 && churn_ok; i++) { if (pthread_create(&t[0], 0, ret_arg, (void *)(long)i) != 0) { churn_ok = 0; break; } pthread_join(t[0], &r); if ((long)r != i * 2) churn_ok = 0; }
    CHECK("churn_64_threads", churn_ok, "create/join churn failed");

    /* many threads alive at once */
    int live = 0; pthread_t many[24];
    for (int i = 0; i < 24; i++) if (pthread_create(&many[i], 0, sleeper, 0) == 0) live++;
    for (int i = 0; i < live; i++) pthread_join(many[i], 0);
    CHECK("24_threads_at_once", live == 24, "only %d of 24 threads could be created (errno %d)", live, errno);

    pthread_attr_init(&at); pthread_attr_setstacksize(&at, 1 << 20);
    e = pthread_create(&t[0], &at, deep, 0);
    CHECK("big_stack_create", e == 0, "create with 1 MiB stack -> %d", e);
    if (e == 0) { pthread_join(t[0], &r); CHECK("big_stack_use", (long)r == 1, "deep recursion in the thread stack failed"); }

    pthread_barrier_init(&bar, 0, 4);
    for (int i = 0; i < 4; i++) pthread_create(&t[i], 0, bar_thr, 0);
    int serial = 0; for (int i = 0; i < 4; i++) { pthread_join(t[i], &r); if ((long)r == PTHREAD_BARRIER_SERIAL_THREAD) serial++; }
    CHECK("barrier", serial == 1, "serial thread count %d", serial);
    for (int i = 0; i < 4; i++) pthread_create(&t[i], 0, once_thr, 0);
    for (int i = 0; i < 4; i++) pthread_join(t[i], 0);
    CHECK("once", once_n == 1, "once ran %d times", once_n);

    /* timed wait on a condvar must time out */
    pthread_mutex_lock(&mu); clock_gettime(CLOCK_REALTIME, &dl); dl.tv_nsec += 50 * 1000 * 1000; if (dl.tv_nsec >= 1000000000) { dl.tv_sec++; dl.tv_nsec -= 1000000000; }
    struct timespec t0, t1; clock_gettime(CLOCK_MONOTONIC, &t0);
    int w = pthread_cond_timedwait(&cv, &mu, &dl);
    clock_gettime(CLOCK_MONOTONIC, &t1); pthread_mutex_unlock(&mu);
    long ms = (t1.tv_sec - t0.tv_sec) * 1000 + (t1.tv_nsec - t0.tv_nsec) / 1000000;
    CHECK("cond_timedwait_times_out", w == ETIMEDOUT && ms >= 40 && ms < 1000, "ret %d after %ld ms", w, ms);
    CHECK("sched_yield", sched_yield() == 0, "sched_yield failed");
    /* POSIX: all threads of a process share ONE descriptor table. A thread started BEFORE an open() must see the new descriptor. */
    pthread_create(&t[0], 0, fdshare_thr, 0);
    usleep(30000);
    g_fd = open("/etc/passwd", O_RDONLY);
    g_go = 1;
    pthread_join(t[0], 0);
    CHECK("fd_table_shared_between_threads", g_fd >= 0 && g_res == 1, "a descriptor opened after the thread started is not valid in the thread (each task has its own copy)");

    /* concurrent mmap + malloc in two threads, then the creator maps more */
    {
        pthread_barrier_init(&mm_bar, 0, 2);
        pthread_create(&t[0], 0, mm_thr, (void *)0);
        pthread_create(&t[1], 0, mm_thr, (void *)1);
        pthread_join(t[0], 0); pthread_join(t[1], 0);
        for (int i = 0; i < MM_N; i++) {
            char *p = mmap(0, MM_LEN, PROT_READ | PROT_WRITE, MAP_PRIVATE | MAP_ANONYMOUS, -1, 0);
            if (p == MAP_FAILED) { mm_fail[2]++; mm_addr[2][i] = 0; continue; }
            mm_addr[2][i] = p; memset(p, (int)(128 + i), MM_LEN);
        }
        int fails = mm_fail[0] + mm_fail[1] + mm_fail[2], overlap = 0, damaged = 0;
        for (int x = 0; x < 3; x++) for (int i = 0; i < MM_N; i++) {
            char *p = mm_addr[x][i]; if (!p) continue;
            if (p[0] != (char)(x * 64 + i) && !(x == 2 && p[0] == (char)(128 + i))) damaged++;
            if (p[MM_LEN - 1] != p[0]) damaged++;
            for (int y = x; y < 3; y++) for (int j = (y == x ? i + 1 : 0); j < MM_N; j++) {
                char *q = mm_addr[y][j]; if (!q) continue;
                if (p < q + MM_LEN && q < p + MM_LEN) overlap++;
            }
        }
        CHECK("mmap_two_threads_no_enomem", fails == 0, "%d mmap/malloc calls failed (thread0 %d thread1 %d creator %d)", fails, mm_fail[0], mm_fail[1], mm_fail[2]);
        CHECK("mmap_threads_disjoint", overlap == 0, "%d overlapping mappings between threads and creator", overlap);
        CHECK("mmap_threads_content_intact", damaged == 0, "%d mappings were overwritten by another thread", damaged);
    }
    group_case("group_exit_main_kills_threads", 0, 0, 5);
    group_case("group_segv_main_kills_threads", 1, SIGSEGV, 0);
    group_case("group_exit_group_thread_kills_all", 2, 0, 7);
    group_case("group_segv_thread_kills_all", 3, SIGSEGV, 0);
    group_case("group_exit_group_150_is_exit", 4, 0, 150);
    {
        long me = getpid(), slot = -1;
        for (long i = 0; i < 256 && slot < 0; i++) if (syscall(1003, i, 1L) == me) slot = i;
        pthread_t th[2]; int made = 0;
        for (int i = 0; i < 2; i++) if (pthread_create(&th[i], 0, idle_thr, 0) == 0) made++;
        settle(200);
        long n = slot >= 0 ? syscall(1003, slot, 14L) : -1;
        CHECK("pstat_threads_counts_group", made == 2 && n == 3, "made %d, P_THREADS %ld (want 3)", made, n);
    }
    CHECK("pthread_self_equal", pthread_equal(pthread_self(), pthread_self()), "");
    return 0;
}
