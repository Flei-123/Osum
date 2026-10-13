/* processes: fork, exec, wait, pipes between them, posix_spawn (clone CLONE_VM|CLONE_VFORK), system(), popen(). */
#define TNAME "proc"
#include "t.h"
#include <fcntl.h>
#include <signal.h>
#include <spawn.h>
#include <stdlib.h>
#include <sys/wait.h>
#include <time.h>

extern char **environ;
static int read_all(int fd, char *b, int n) { int t = 0, r; while (t < n - 1 && (r = read(fd, b + t, n - 1 - t)) > 0) t += r; b[t] = 0; return t; }

int main(void)
{
    pid_t p = fork();
    if (p == 0) _exit(9);
    int st = 0; pid_t w = p > 0 ? waitpid(p, &st, 0) : -1;
    CHECKC("fork_wait_exitcode", p > 0 && w == p && WIFEXITED(st) && WEXITSTATUS(st) == 9);

    int pf[2]; (void)!pipe(pf);
    p = fork();
    if (p == 0) { close(pf[0]); char *m = malloc(100000); memset(m, 'q', 100000); write(pf[1], "hello from child", 16); _exit(0); }
    char buf[256]; close(pf[1]); read_all(pf[0], buf, sizeof buf); close(pf[0]); waitpid(p, &st, 0);
    CHECK("fork_pipe", strcmp(buf, "hello from child") == 0, "got '%s'", buf);

    /* fork keeps a private copy of memory */
    static int shared_var = 1;
    p = fork();
    if (p == 0) { shared_var = 2; _exit(shared_var == 2 ? 0 : 1); }
    waitpid(p, &st, 0);
    CHECK("fork_copy_on_write_semantics", shared_var == 1 && WEXITSTATUS(st) == 0, "parent saw %d", shared_var);

    /* fork + execve with arguments, environment and a redirected stdout */
    int po[2]; (void)!pipe(po);
    p = fork();
    if (p == 0) { dup2(po[1], 1); close(po[0]); close(po[1]); char *av[] = { "c_child", "one", "two", 0 }; char *ev[] = { "UB_X=envval", 0 }; execve("/bin/c_child", av, ev); _exit(127); }
    close(po[1]); read_all(po[0], buf, sizeof buf); close(po[0]); waitpid(p, &st, 0);
    CHECK("exec_args_env_stdout", strcmp(buf, "child argc=3 a1=one a2=two env=envval\n") == 0, "got '%s'", buf);
    CHECK("exec_exit_code", WIFEXITED(st) && WEXITSTATUS(st) == 42, "status 0x%x", st);

    /* many arguments (r711: the kernel took eight words, foot -c <file> and most Linux tools need more) */
    int pm[2]; (void)!pipe(pm);
    p = fork();
    if (p == 0) {
        char *av[43]; char w[40][4]; av[0] = "c_child"; av[1] = "count";
        for (int i = 0; i < 40; i++) { w[i][0] = 'a'; w[i][1] = '0' + i / 10; w[i][2] = '0' + i % 10; w[i][3] = 0; av[2 + i] = w[i]; }
        av[42] = 0;
        dup2(pm[1], 1); close(pm[0]); close(pm[1]); execve("/bin/c_child", av, 0); _exit(127);
    }
    close(pm[1]); read_all(pm[0], buf, sizeof buf); close(pm[0]); waitpid(p, &st, 0);
    CHECK("exec_many_args", strcmp(buf, "argc=42 last=a39\n") == 0, "got '%s'", buf);

    /* exec of something that is not there */
    p = fork();
    if (p == 0) { char *av[] = { "x", 0 }; execv("/bin/gibtesnicht", av); _exit(errno == ENOENT ? 55 : 56); }
    waitpid(p, &st, 0);
    CHECK("exec_enoent", WIFEXITED(st) && WEXITSTATUS(st) == 55, "child status 0x%x (errno seen differs)", st);

    /* a pipeline: parent -> child cat -> parent */
    int in[2], out[2]; (void)!pipe(in); (void)!pipe(out);
    p = fork();
    if (p == 0) { dup2(in[0], 0); dup2(out[1], 1); close(in[0]); close(in[1]); close(out[0]); close(out[1]); char *av[] = { "c_child", "cat", 0 }; execv("/bin/c_child", av); _exit(127); }
    close(in[0]); close(out[1]); write(in[1], "round trip", 10); close(in[1]);
    read_all(out[0], buf, sizeof buf); close(out[0]); waitpid(p, &st, 0);
    CHECK("exec_stdin_stdout_pipeline", strcmp(buf, "round trip") == 0, "got '%s'", buf);

    /* wait for several children, WNOHANG, ECHILD */
    pid_t c1 = fork(); if (c1 == 0) { usleep(50000); _exit(1); }
    pid_t c2 = fork(); if (c2 == 0) _exit(2);
    pid_t first = waitpid(-1, &st, 0);
    pid_t second = waitpid(-1, &st, 0);
    CHECK("wait_any_two_children", first > 0 && second > 0 && first != second, "first %d second %d", first, second);
    errno = 0; pid_t none = waitpid(-1, &st, 0);
    CHECK("wait_echild", none == -1 && errno == ECHILD, "ret %d errno %d", none, errno);
    char *avs[] = { "c_child", "sleep", 0 };
    struct timespec ts0, ts1; clock_gettime(CLOCK_MONOTONIC, &ts0);
    posix_spawn(&c1, "/bin/c_child", 0, 0, avs, environ);
    clock_gettime(CLOCK_MONOTONIC, &ts1);
    long spawn_ms = (ts1.tv_sec - ts0.tv_sec) * 1000 + (ts1.tv_nsec - ts0.tv_nsec) / 1000000;
    CHECK("posix_spawn_returns_before_child_ends", spawn_ms < 700, "posix_spawn of a 1 s child took %ld ms (descriptors survive exec, so the parent's wait for the exec-pipe lasts as long as the child)", spawn_ms);
    pid_t nh = waitpid(c1, &st, WNOHANG);
    CHECK("wait_wnohang_running", nh == 0, "WNOHANG on a running child returned %d", nh);
    waitpid(c1, &st, 0);
    CHECK("spawn_sleeper_exit_code", WIFEXITED(st) && WEXITSTATUS(st) == 3, "status 0x%x", st);

    /* posix_spawn (musl: clone with CLONE_VM|CLONE_VFORK) */
    pid_t sp = 0; char *av2[] = { "c_child", "exit7", 0 };
    int se = posix_spawn(&sp, "/bin/c_child", 0, 0, av2, environ);
    CHECK("posix_spawn", se == 0 && sp > 0, "posix_spawn -> %d", se);
    if (se == 0) { waitpid(sp, &st, 0); CHECK("posix_spawn_exit_code", WIFEXITED(st) && WEXITSTATUS(st) == 7, "status 0x%x", st); }

    /* system() and popen() need /bin/sh and fork */
    errno = 0; int sr = system("exit 5");
    CHECKC("system_exit_status", sr != -1 && WIFEXITED(sr) && WEXITSTATUS(sr) == 5);
    FILE *f = popen("echo popen-ok", "r");
    if (!f) GAP("popen", "popen failed errno=%d", errno);
    else { char l[100] = { 0 }; fgets(l, sizeof l, f); pclose(f); CHECK("popen", strncmp(l, "popen-ok", 8) == 0, "got '%s'", l); }

    /* kill a child, see the signal in the status */
    pid_t k = fork(); if (k == 0) { for (;;) pause(); }
    usleep(20000); kill(k, SIGKILL); waitpid(k, &st, 0);
    CHECK("kill_child_sigkill", WIFSIGNALED(st) && WTERMSIG(st) == SIGKILL, "status 0x%x", st);
    /* a child that crashes */
    k = fork(); if (k == 0) { signal(SIGSEGV, SIG_DFL); *(volatile int *)0 = 1; _exit(0); }
    waitpid(k, &st, 0);
    CHECK("child_segv_reported", WIFSIGNALED(st) && WTERMSIG(st) == SIGSEGV, "status 0x%x", st);
    CHECK("getppid_of_child", 1, "");
    pid_t me_pid = getpid();
    k = fork(); if (k == 0) _exit(getppid() == me_pid ? 0 : 1);
    waitpid(k, &st, 0);
    CHECK("getppid", WEXITSTATUS(st) == 0, "child's getppid() is not the parent");
    /* 16 fork/wait rounds: no leak of process slots */
    int churn = 1; for (int i = 0; i < 16; i++) { k = fork(); if (k == 0) _exit(0); if (k < 0 || waitpid(k, &st, 0) != k) { churn = 0; break; } }
    CHECK("fork_churn_16", churn, "fork/wait churn failed at round (errno %d)", errno);
    return 0;
}
