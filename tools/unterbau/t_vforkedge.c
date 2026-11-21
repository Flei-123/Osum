#define TNAME "vforkedge"
#include "t.h"
#include <fcntl.h>
#include <poll.h>
#include <signal.h>
#include <stdlib.h>
#include <sys/mman.h>
#include <sys/wait.h>
#include <time.h>

#define HEAP_BYTES (256 << 10)
#define LEAK_ROUNDS 12
#define LEAK_LIMIT_KB 2048

static volatile int nested_flag;

static int reap(pid_t p)
{
    int st = 0;
    if (waitpid(p, &st, 0) != p) return -1;
    if (WIFSIGNALED(st)) return 128 + WTERMSIG(st);
    return WIFEXITED(st) ? WEXITSTATUS(st) : 200;
}

static void nap(long ms)
{
    struct timespec ts = { ms / 1000, (ms % 1000) * 1000000L };
    nanosleep(&ts, 0);
}

static int read_byte_within(int fd, int ms)
{
    struct pollfd pf = { fd, POLLIN, 0 };
    char c;
    if (poll(&pf, 1, ms) <= 0) return -1;
    return read(fd, &c, 1) == 1 ? (unsigned char)c : -1;
}

static long mem_free_kb(void)
{
    char buf[2048];
    int fd = open("/proc/meminfo", O_RDONLY);
    if (fd < 0) return -1;
    int n = read(fd, buf, sizeof buf - 1);
    close(fd);
    if (n <= 0) return -1;
    buf[n] = 0;
    char *p = strstr(buf, "MemFree:");
    return p ? atol(p + 8) : -1;
}

static int heap_intact(const char *heap)
{
    for (int i = 0; i < HEAP_BYTES; i += 4096)
        if (heap[i] != 0x6b) return 0;
    return 1;
}

static int scenario_nested_exit(void)
{
    nested_flag = 0;
    pid_t c = vfork();
    if (c == 0) {
        nested_flag = 1;
        pid_t d = vfork();
        if (d == 0) {
            nested_flag = 2;
            _exit(5);
        }
        nested_flag = nested_flag + 10;
        int st = 0;
        _exit(waitpid(d, &st, 0) == d && WIFEXITED(st) && WEXITSTATUS(st) == 5 ? 6 : 99);
    }
    if (reap(c) != 6) return 1;
    return nested_flag == 12 ? 0 : 2;
}

static int scenario_nested_exec_inner(void)
{
    char *heap = malloc(HEAP_BYTES);
    memset(heap, 0x6b, HEAP_BYTES);
    pid_t c = vfork();
    if (c == 0) {
        pid_t d = vfork();
        if (d == 0) {
            char *av[] = { "c_child", "exit7", 0 };
            execv("/bin/c_child", av);
            _exit(127);
        }
        int st = 0;
        _exit(waitpid(d, &st, 0) == d && WIFEXITED(st) && WEXITSTATUS(st) == 7 ? 8 : 98);
    }
    if (reap(c) != 8) return 1;
    return heap_intact(heap) ? 0 : 2;
}

static int scenario_nested_then_exec(void)
{
    char *heap = malloc(HEAP_BYTES);
    memset(heap, 0x6b, HEAP_BYTES);
    pid_t c = vfork();
    if (c == 0) {
        pid_t d = vfork();
        if (d == 0) _exit(0);
        waitpid(d, 0, 0);
        char *av[] = { "c_child", "exit7", 0 };
        execv("/bin/c_child", av);
        _exit(127);
    }
    if (reap(c) != 7) return 1;
    return heap_intact(heap) ? 0 : 2;
}

static int isolated(int (*scenario)(void))
{
    pid_t b = fork();
    if (b == 0) _exit(scenario());
    return reap(b);
}

static void kill_parent_once(int exec_after, int *child_marker)
{
    int pi[2];
    if (pipe(pi) != 0) return;
    pid_t b = fork();
    if (b == 0) {
        pid_t c = vfork();
        if (c == 0) {
            nap(120);
            if (exec_after) {
                char *av[] = { "c_child", "exit7", 0 };
                execv("/bin/c_child", av);
                _exit(127);
            }
            (void)!write(pi[1], "k", 1);
            _exit(33);
        }
        _exit(1);
    }
    nap(40);
    kill(b, SIGKILL);
    int st = 0;
    pid_t w = waitpid(b, &st, 0);
    if (child_marker) {
        child_marker[0] = w == b && WIFSIGNALED(st) && WTERMSIG(st) == SIGKILL;
        child_marker[1] = exec_after ? 1 : read_byte_within(pi[0], 3000) == 'k';
    }
    close(pi[0]);
    close(pi[1]);
    if (exec_after) nap(200);
}

static int leak_rounds(int exec_after)
{
    kill_parent_once(exec_after, 0);
    nap(300);
    long before = mem_free_kb();
    for (int i = 0; i < LEAK_ROUNDS; i++) kill_parent_once(exec_after, 0);
    nap(500);
    long after = mem_free_kb();
    return before < 0 || after < 0 || before - after <= LEAK_LIMIT_KB;
}

int main(void)
{
    int m[2] = { 0, 0 };
    kill_parent_once(0, m);
    CHECK("kill_parent_reaped", m[0], "not reaped as SIGKILL");
    CHECK("kill_parent_child_finishes", m[1], "vfork child did not finish");

    m[0] = m[1] = 0;
    kill_parent_once(1, m);
    CHECK("kill_parent_then_child_exec", m[0], "not reaped as SIGKILL");
    CHECK("kill_parent_no_leak_exit", leak_rounds(0), "free memory fell");
    CHECK("kill_parent_no_leak_exec", leak_rounds(1), "free memory fell");

    int pi[2];
    CHECK("pipe", pipe(pi) == 0, "errno=%d", errno);
    pid_t b = fork();
    if (b == 0) {
        pid_t c = vfork();
        if (c == 0) {
            pid_t me = getpid();
            (void)!write(pi[1], &me, sizeof me);
            pause();
            _exit(1);
        }
        int st = 0;
        _exit(waitpid(c, &st, 0) == c && WIFSIGNALED(st) && WTERMSIG(st) == SIGKILL ? 0 : 1);
    }
    pid_t victim = 0;
    struct pollfd pf = { pi[0], POLLIN, 0 };
    int got = poll(&pf, 1, 3000) > 0 ? (int)read(pi[0], &victim, sizeof victim) : -1;
    if (got == (int)sizeof victim) kill(victim, SIGKILL);
    else kill(b, SIGKILL);
    CHECK("child_killed_releases_parent", got == (int)sizeof victim && reap(b) == 0, "got=%d", got);

    CHECK("nested_exit", isolated(scenario_nested_exit) == 0, "scenario failed");
    CHECK("nested_exec_inner", isolated(scenario_nested_exec_inner) == 0, "scenario failed");
    CHECK("nested_then_exec", isolated(scenario_nested_then_exec) == 0, "scenario failed");

    long before = mem_free_kb();
    int bad = 0;
    for (int i = 0; i < LEAK_ROUNDS; i++) {
        bad += isolated(scenario_nested_exit) != 0;
        bad += isolated(scenario_nested_exec_inner) != 0;
        bad += isolated(scenario_nested_then_exec) != 0;
    }
    long after = mem_free_kb();
    CHECK("nested_loop", bad == 0, "bad=%d", bad);
    CHECK("nested_no_leak", before < 0 || after < 0 || before - after <= LEAK_LIMIT_KB, "free %ld -> %ld kB", before, after);
    return 0;
}
