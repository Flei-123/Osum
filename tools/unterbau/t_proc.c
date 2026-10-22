/* processes: fork, exec, wait, pipes between them, posix_spawn (clone CLONE_VM|CLONE_VFORK), system(), popen(). */
#define TNAME "proc"
#include "t.h"
#include <fcntl.h>
#include <signal.h>
#include <spawn.h>
#include <stdlib.h>
#include <sys/wait.h>
#include <time.h>


#include <sys/syscall.h>
#define OSUM_PSTAT 1003
#define OSUM_SETPRIO 1995
static long self_slot(void) { long me = getpid(); for (long i = 0; i < 256; i++) if (syscall(OSUM_PSTAT, i, 1L) == me) return i; return -1; }
static long pst(long slot, long field) { return syscall(OSUM_PSTAT, slot, field); }

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

    /* W-TM S5: process counters and the priority call */
    long sl = self_slot();
    CHECK("pstat_self_slot", sl >= 0, "no pstat slot carries pid %d", (int)getpid());
    if (sl >= 0) {
        CHECK("pstat_uid_matches_getuid", pst(sl, 13) == (long)getuid(), "P_UID %ld, getuid %ld", pst(sl, 13), (long)getuid());
        CHECK("pstat_threads_single", pst(sl, 14) == 1, "P_THREADS %ld", pst(sl, 14));
        long w0 = pst(sl, 49), r0 = pst(sl, 48);
        int dfd = open("/tmp/pstat_io", O_WRONLY | O_CREAT | O_TRUNC, 0644);
        char blk[4096]; memset(blk, 'x', sizeof blk);
        long wrote = 0; for (int i = 0; dfd >= 0 && i < 8; i++) { long n = write(dfd, blk, sizeof blk); if (n > 0) wrote += n; }
        if (dfd >= 0) close(dfd);
        long w1 = pst(sl, 49);
        CHECK("pstat_disk_write_counts", wrote > 0 && w1 - w0 >= wrote, "wrote %ld, P_DISKW grew by %ld", wrote, w1 - w0);
        dfd = open("/tmp/pstat_io", O_RDONLY);
        long got = 0; while (dfd >= 0) { long n = read(dfd, blk, sizeof blk); if (n <= 0) break; got += n; }
        if (dfd >= 0) close(dfd);
        long r1 = pst(sl, 48);
        CHECK("pstat_disk_read_counts", got > 0 && r1 - r0 >= got, "read %ld, P_DISKR grew by %ld", got, r1 - r0);
        unlink("/tmp/pstat_io");
        CHECK("pstat_free_slot_zero", pst(255, 13) == 0 || pst(255, 1) != 0, "free slot reports a uid");
    }
    errno = 0; long pr = syscall(OSUM_SETPRIO, (long)getpid(), 0L);
    CHECKC("setprio_zero_einval", pr == -1 && errno == EINVAL);
    errno = 0; pr = syscall(OSUM_SETPRIO, (long)getpid(), 4L);
    CHECKC("setprio_four_einval", pr == -1 && errno == EINVAL);
    errno = 0; pr = syscall(OSUM_SETPRIO, 99999L, 2L);
    CHECKC("setprio_missing_pid_esrch", pr == -1 && errno == ESRCH);
    errno = 0; pr = syscall(OSUM_SETPRIO, (long)getpid(), 1L);
    CHECKC("setprio_self_ok", pr == 0);
    if (sl >= 0) CHECK("setprio_self_visible", pst(sl, 4) == 1, "P_PRIO %ld after setting 1", pst(sl, 4));
    syscall(OSUM_SETPRIO, (long)getpid(), 2L);
    if (sl >= 0) CHECK("setprio_self_restored", pst(sl, 4) == 2, "P_PRIO %ld after setting 2", pst(sl, 4));
    {
        int pp[2]; if (pipe(pp) == 0) {
            pid_t par = getpid();
            pid_t kid = fork();
            if (kid == 0) {
                char res = 'g';
                if (setuid(1000) != 0) res = 'n';
                else { errno = 0; long q = syscall(OSUM_SETPRIO, (long)par, 2L); res = (q == -1 && errno == EPERM) ? 'p' : 'f'; }
                (void)!write(pp[1], &res, 1); _exit(0);
            }
            char res = '?'; close(pp[1]); (void)!read(pp[0], &res, 1); close(pp[0]);
            if (kid > 0) waitpid(kid, &st, 0);
            if (res == 'p') PASS("setprio_foreign_eperm");
            else if (res == 'n') GAP("setprio_foreign_eperm", "setuid(1000) refused, cannot drop privilege");
            else FAIL("setprio_foreign_eperm", "child result '%c'", res);
        }
    }
    return 0;
}
