#define TNAME "vfork"
#include "t.h"
#include <fcntl.h>
#include <spawn.h>
#include <stdlib.h>
#include <sys/mman.h>
#include <sys/wait.h>
#include <time.h>

extern char **environ;

static volatile int shared_flag;

static int reap(pid_t p)
{
    int st = 0;
    if (waitpid(p, &st, 0) != p) return -1;
    return WIFEXITED(st) ? WEXITSTATUS(st) : 200;
}

int main(void)
{
    pid_t parent = getpid();
    shared_flag = 1;
    pid_t p = vfork();
    if (p == 0) {
        shared_flag = 2;
        _exit(7);
    }
    CHECK("exit_status", p > 0 && reap(p) == 7, "pid=%d", (int)p);
    CHECK("shared_memory_visible", shared_flag == 2, "flag=%d", shared_flag);

    shared_flag = 0;
    p = vfork();
    if (p == 0) {
        struct timespec ts = { 0, 60 * 1000 * 1000 };
        nanosleep(&ts, 0);
        shared_flag = 9;
        _exit(0);
    }
    CHECK("parent_blocked_until_exit", shared_flag == 9, "flag=%d", shared_flag);
    reap(p);

    shared_flag = 0;
    p = vfork();
    if (p == 0) {
        char *av[] = { "c_child", "exit7", 0 };
        execv("/bin/c_child", av);
        _exit(127);
    }
    CHECK("exec_released_parent", p > 0, "pid=%d", (int)p);
    CHECK("exec_status", reap(p) == 7, "bad status");
    CHECK("parent_pid_stable", getpid() == parent, "pid changed");

    p = vfork();
    if (p == 0) {
        char *av[] = { "x", 0 };
        execv("/bin/does-not-exist", av);
        _exit(55);
    }
    CHECK("exec_failure_exit", reap(p) == 55, "bad status");

    int pi[2];
    CHECK("pipe", pipe(pi) == 0, "errno=%d", errno);
    p = vfork();
    if (p == 0) {
        dup2(pi[1], 1);
        close(pi[0]);
        close(pi[1]);
        char *av[] = { "c_child", "one", "two", 0 };
        execv("/bin/c_child", av);
        _exit(127);
    }
    close(pi[1]);
    char buf[128];
    int n = read(pi[0], buf, sizeof buf - 1);
    buf[n > 0 ? n : 0] = 0;
    CHECK("child_fds_isolated", n > 0 && strstr(buf, "a1=one") != 0, "got '%s'", buf);
    CHECK("pipe_status", reap(p) == 42, "bad status");
    close(pi[0]);

    int fd = open("/tmp/vf.dat", O_RDWR | O_CREAT | O_TRUNC, 0644);
    p = vfork();
    if (p == 0) {
        close(fd);
        _exit(0);
    }
    reap(p);
    CHECK("parent_fd_survives_child_close", write(fd, "x", 1) == 1, "errno=%d", errno);
    close(fd);
    unlink("/tmp/vf.dat");

    char *heap = malloc(1 << 20);
    memset(heap, 0x5a, 1 << 20);
    int bad = 0;
    for (int i = 0; i < 100; i++) {
        p = vfork();
        if (p == 0) {
            char *av[] = { "c_child", "exit7", 0 };
            execv("/bin/c_child", av);
            _exit(127);
        }
        if (reap(p) != 7) bad++;
    }
    for (int i = 0; i < (1 << 20); i += 4096) if (heap[i] != 0x5a) bad++;
    CHECK("loop_100_exec", bad == 0, "bad=%d", bad);

    p = vfork();
    if (p == 0) {
        void *m = mmap(0, 1 << 16, PROT_READ | PROT_WRITE, MAP_PRIVATE | MAP_ANONYMOUS, -1, 0);
        _exit(m == MAP_FAILED ? 3 : 0);
    }
    CHECK("child_mmap_ok", reap(p) == 0, "bad status");
    void *m2 = mmap(0, 1 << 16, PROT_READ | PROT_WRITE, MAP_PRIVATE | MAP_ANONYMOUS, -1, 0);
    CHECK("parent_mmap_after", m2 != MAP_FAILED, "errno=%d", errno);

    pid_t sp = 0;
    char *av2[] = { "c_child", "exit7", 0 };
    int rc = posix_spawn(&sp, "/bin/c_child", 0, 0, av2, environ);
    CHECK("posix_spawn", rc == 0 && reap(sp) == 7, "rc=%d", rc);

    p = vfork();
    if (p == 0) {
        shared_flag = (int)getppid();
        _exit(getpid() != parent ? 0 : 9);
    }
    CHECK("child_identity", reap(p) == 0 && shared_flag == (int)parent, "ppid=%d", shared_flag);
    return 0;
}
