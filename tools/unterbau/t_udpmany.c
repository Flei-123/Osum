#define TNAME "udpmany"
#include "t.h"
#include <arpa/inet.h>
#include <netinet/in.h>
#include <poll.h>
#include <pthread.h>
#include <signal.h>
#include <sys/socket.h>
#include <sys/wait.h>

#define SOCKET_WANTED 24
#define SOCKET_PROBE_MAX 64
#define WORKER_THREADS 16
#define ROUNDS_PER_WORKER 20
#define RESPONDER_PORT 5353
#define REPLY_WAIT_MS 200
#define QUERY_ATTEMPTS 10
#define PACKET_LEN 32
#define LEAK_ROUNDS 12
#define CHILD_SETTLE_US 20000

static struct sockaddr_in loopback(int port)
{
    struct sockaddr_in a;
    memset(&a, 0, sizeof a);
    a.sin_family = AF_INET;
    a.sin_port = htons(port);
    inet_pton(AF_INET, "127.0.0.1", &a.sin_addr);
    return a;
}

static int udp_bound(int port)
{
    int fd = socket(AF_INET, SOCK_DGRAM | SOCK_CLOEXEC | SOCK_NONBLOCK, 0);
    if (fd < 0)
        return -1;
    struct sockaddr_in a = loopback(port);
    if (bind(fd, (struct sockaddr *)&a, sizeof a) != 0) {
        close(fd);
        return -1;
    }
    return fd;
}

static int open_many(int *fds, int max)
{
    int n = 0;
    while (n < max) {
        int fd = udp_bound(0);
        if (fd < 0)
            break;
        fds[n++] = fd;
    }
    return n;
}

static void close_many(int *fds, int n)
{
    for (int i = 0; i < n; i++)
        close(fds[i]);
}

static int responder_fd;
static volatile int responder_stop;

static void *responder(void *arg)
{
    char buf[PACKET_LEN];
    (void)arg;
    while (!responder_stop) {
        struct pollfd p = { .fd = responder_fd, .events = POLLIN };
        if (poll(&p, 1, 50) <= 0)
            continue;
        struct sockaddr_in from;
        socklen_t fl = sizeof from;
        int n = recvfrom(responder_fd, buf, sizeof buf, 0, (struct sockaddr *)&from, &fl);
        if (n > 0)
            sendto(responder_fd, buf, n, 0, (struct sockaddr *)&from, fl);
    }
    return NULL;
}

static int one_query(void)
{
    int fd = udp_bound(0);
    if (fd < 0)
        return -1;
    char out[PACKET_LEN] = "dns-like-query";
    char in[PACKET_LEN];
    struct sockaddr_in dst = loopback(RESPONDER_PORT);
    int rc = -3;
    for (int attempt = 0; attempt < QUERY_ATTEMPTS && rc != 0; attempt++) {
        if (sendto(fd, out, sizeof out, 0, (struct sockaddr *)&dst, sizeof dst) != (ssize_t)sizeof out) {
            rc = -2;
            break;
        }
        struct pollfd p = { .fd = fd, .events = POLLIN };
        if (poll(&p, 1, REPLY_WAIT_MS) > 0 && recv(fd, in, sizeof in, 0) == (ssize_t)sizeof in)
            rc = 0;
    }
    close(fd);
    return rc;
}

static int worker_failures;
static int worker_first_error;

static void *worker(void *arg)
{
    (void)arg;
    for (int i = 0; i < ROUNDS_PER_WORKER; i++) {
        int rc = one_query();
        if (rc != 0) {
            __sync_fetch_and_add(&worker_failures, 1);
            __sync_val_compare_and_swap(&worker_first_error, 0, rc);
        }
    }
    return NULL;
}


enum child_end { END_EXIT, END_KILL, END_SEGV, END_EXIT_UNCLOSED, END_EXEC, END_VFORK_EXEC };

static char *self_path;

static void child_body(enum child_end end)
{
    if (end == END_EXIT_UNCLOSED) {
        int fd = udp_bound(0);
        (void)fd;
        _exit(0);
    }
    if (end == END_SEGV)
        *(volatile int *)0 = 1;
    if (end == END_KILL)
        pause();
    if (end == END_EXEC) {
        char *args[] = { self_path, "child", NULL };
        execv(self_path, args);
    }
    _exit(0);
}

static void leak_round(enum child_end end)
{
    int fd = end == END_EXIT_UNCLOSED ? -1 : udp_bound(0);
    pid_t pid = end == END_VFORK_EXEC ? vfork() : fork();
    if (pid == 0) {
        if (end == END_VFORK_EXEC) {
            char *args[] = { self_path, "child", NULL };
            execv(self_path, args);
            _exit(0);
        }
        child_body(end);
    }
    if (end == END_KILL) {
        usleep(CHILD_SETTLE_US);
        kill(pid, SIGKILL);
    }
    waitpid(pid, NULL, 0);
    if (fd >= 0)
        close(fd);
}

static void leak_check(const char *name, enum child_end end)
{
    int fds[SOCKET_PROBE_MAX];
    int before = open_many(fds, SOCKET_PROBE_MAX);
    close_many(fds, before);
    for (int i = 0; i < LEAK_ROUNDS; i++)
        leak_round(end);
    int after = open_many(fds, SOCKET_PROBE_MAX);
    close_many(fds, after);
    CHECK(name, after >= before, "%d handles before, %d after %d children", before, after, LEAK_ROUNDS);
}

int main(int argc, char **argv)
{
    if (argc > 1)
        return 0;
    self_path = argv[0];
    int fds[SOCKET_PROBE_MAX];
    int n = open_many(fds, SOCKET_PROBE_MAX);
    CHECK("open_24_at_once", n >= SOCKET_WANTED, "only %d udp sockets bound", n);
    close_many(fds, n);
    int again = open_many(fds, SOCKET_PROBE_MAX);
    CHECK("reuse_after_close", again == n, "first %d then %d", n, again);
    close_many(fds, again);

    leak_check("no_leak_child_exit", END_EXIT);
    leak_check("no_leak_child_killed", END_KILL);
    leak_check("no_leak_child_segv", END_SEGV);
    leak_check("no_leak_child_exit_unclosed", END_EXIT_UNCLOSED);
    leak_check("no_leak_child_exec", END_EXEC);
    leak_check("no_leak_child_vfork_exec", END_VFORK_EXEC);

    responder_fd = udp_bound(RESPONDER_PORT);
    if (responder_fd < 0) {
        FAIL("parallel_queries", "responder bind failed");
        return 0;
    }
    pthread_t rt;
    pthread_create(&rt, NULL, responder, NULL);
    pthread_t wt[WORKER_THREADS];
    for (int i = 0; i < WORKER_THREADS; i++)
        pthread_create(&wt[i], NULL, worker, NULL);
    for (int i = 0; i < WORKER_THREADS; i++)
        pthread_join(wt[i], NULL);
    responder_stop = 1;
    pthread_join(rt, NULL);
    CHECK("parallel_queries", worker_failures == 0, "%d of %d queries failed, first error %d",
        worker_failures, WORKER_THREADS * ROUNDS_PER_WORKER, worker_first_error);
    close(responder_fd);
    int final_count = open_many(fds, SOCKET_PROBE_MAX);
    close_many(fds, final_count);
    CHECK("no_leak_after_threads", final_count >= n, "%d handles at start, %d after the thread storm", n, final_count);
    return 0;
}
