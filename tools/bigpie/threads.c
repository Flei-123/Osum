#define _GNU_SOURCE
#include <dlfcn.h>
#include <errno.h>
#include <fcntl.h>
#include <gnu/libc-version.h>
#include <netdb.h>
#include <pthread.h>
#include <sched.h>
#include <semaphore.h>
#include <stddef.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/auxv.h>
#include <sys/socket.h>
#include <sys/un.h>
#include <time.h>
#include <unistd.h>

static void res(const char *name, int ok, const char *detail)
{
    printf("G3 %s %s %s\n", name, ok ? "ok" : "FAIL", detail);
    fflush(stdout);
}

static __thread int tls_counter = 3;
static pthread_mutex_t pi_lock;
static long pi_total;

static void *worker(void *arg)
{
    long id = (long)arg;
    tls_counter += (int)id;
    for (int i = 0; i < 200; i++) {
        pthread_mutex_lock(&pi_lock);
        pi_total++;
        pthread_mutex_unlock(&pi_lock);
    }
    return (void *)(long)tls_counter;
}

static int abs_server;
static void *abs_accept(void *arg)
{
    int c = accept(abs_server, 0, 0);
    char b[8] = {0};
    if (c >= 0) {
        ssize_t n = read(c, b, sizeof b);
        if (n == 4) (void)!write(c, "okay", 4);
        close(c);
    }
    return 0;
}

int main(void)
{
    char d[96];
    snprintf(d, sizeof d, "glibc %s", gnu_get_libc_version());
    res("version", 1, d);

    pthread_mutexattr_t at;
    pthread_mutexattr_init(&at);
    int pe = pthread_mutexattr_setprotocol(&at, PTHREAD_PRIO_INHERIT);
    pthread_mutex_init(&pi_lock, &at);
    pthread_t th[6];
    int created = 0;
    for (long i = 0; i < 6; i++)
        if (pthread_create(&th[i], 0, worker, (void *)i) == 0) created++;
    long sum = 0;
    for (int i = 0; i < created; i++) {
        void *rv = 0;
        pthread_join(th[i], &rv);
        sum += (long)rv;
    }
    snprintf(d, sizeof d, "created %d total %ld sum %ld proto %d", created, pi_total, sum, pe);
    res("threads_pi_mutex", created == 6 && pi_total == 1200 && sum == 6 * 3 + 15 && pe == 0, d);
    res("tls_main_untouched", tls_counter == 3, "");

    pthread_mutex_t m = PTHREAD_MUTEX_INITIALIZER;
    pthread_cond_t cv = PTHREAD_COND_INITIALIZER;
    struct timespec ts;
    clock_gettime(CLOCK_REALTIME, &ts);
    ts.tv_nsec += 80 * 1000000;
    if (ts.tv_nsec >= 1000000000) { ts.tv_sec++; ts.tv_nsec -= 1000000000; }
    pthread_mutex_lock(&m);
    int cr = pthread_cond_timedwait(&cv, &m, &ts);
    pthread_mutex_unlock(&m);
    res("cond_timedwait_timeout", cr == ETIMEDOUT, "");

    struct sockaddr_un a;
    memset(&a, 0, sizeof a);
    a.sun_family = AF_UNIX;
    memcpy(a.sun_path + 1, "g3-abstract", 11);
    socklen_t al = offsetof(struct sockaddr_un, sun_path) + 1 + 11;
    abs_server = socket(AF_UNIX, SOCK_STREAM | SOCK_CLOEXEC, 0);
    int b = bind(abs_server, (struct sockaddr *)&a, al);
    int l = listen(abs_server, 2);
    pthread_t at2;
    pthread_create(&at2, 0, abs_accept, 0);
    int cl = socket(AF_UNIX, SOCK_STREAM, 0);
    int c = connect(cl, (struct sockaddr *)&a, al);
    char rb[8] = {0};
    ssize_t w = write(cl, "ping", 4);
    ssize_t r = read(cl, rb, sizeof rb);
    pthread_join(at2, 0);
    snprintf(d, sizeof d, "b %d l %d c %d w %zd r %zd", b, l, c, w, r);
    res("abstract_unix", b == 0 && l == 0 && c == 0 && w == 4 && r == 4 && !memcmp(rb, "okay", 4), d);

    struct addrinfo hints, *ai = 0;
    memset(&hints, 0, sizeof hints);
    hints.ai_family = AF_INET;
    hints.ai_socktype = SOCK_STREAM;
    int gi = getaddrinfo("localhost", "80", &hints, &ai);
    snprintf(d, sizeof d, "rc %d (%s)", gi, gi ? gai_strerror(gi) : "ok");
    res("getaddrinfo_localhost", gi == 0 && ai != 0, d);
    if (ai) freeaddrinfo(ai);

    cpu_set_t cs;
    CPU_ZERO(&cs);
    int sa = sched_getaffinity(0, sizeof cs, &cs);
    long onln = sysconf(_SC_NPROCESSORS_ONLN);
    snprintf(d, sizeof d, "aff %d cpus %d online %ld", sa, CPU_COUNT(&cs), onln);
    res("cpu_count", sa == 0 && CPU_COUNT(&cs) >= 1 && onln >= 1, d);

    FILE *f = fopen("/sys/fs/cgroup/cpu.max", "r");
    res("cgroup_cpu_max", f != 0 || errno == ENOENT, f ? "present" : "absent");
    if (f) fclose(f);
    f = fopen("/proc/self/cgroup", "r");
    res("proc_self_cgroup", f != 0 || errno == ENOENT, f ? "present" : "absent");
    if (f) fclose(f);

    void *h = dlopen("libm.so.6", RTLD_NOW);
    double (*sq)(double) = h ? (double (*)(double))dlsym(h, "sqrt") : 0;
    res("dlopen_libm", h != 0 && sq != 0 && sq(144.0) == 12.0, "");

    unsigned long rnd = getauxval(AT_RANDOM);
    res("auxv_random", rnd != 0, "");

    char *big = malloc(64u << 20);
    if (big) { memset(big, 7, 64u << 20); }
    res("malloc_64m", big != 0 && big[(64u << 20) - 1] == 7, "");
    free(big);

    sem_t sm;
    sem_init(&sm, 0, 0);
    struct timespec t2;
    clock_gettime(CLOCK_REALTIME, &t2);
    t2.tv_nsec += 30 * 1000000;
    if (t2.tv_nsec >= 1000000000) { t2.tv_sec++; t2.tv_nsec -= 1000000000; }
    int sw = sem_timedwait(&sm, &t2);
    res("sem_timedwait", sw == -1 && errno == ETIMEDOUT, "");

    printf("G3 END\n");
    return 0;
}
