#define _GNU_SOURCE
#include <stdio.h>
#include <string.h>
#include <stdlib.h>
#include <unistd.h>
#include <sys/wait.h>

#define OUT_MAX 16384

struct run_result {
    int status;
    char out[OUT_MAX];
    int len;
};

static void run_cmd(char *const argv[], struct run_result *r)
{
    int fds[2];
    memset(r, 0, sizeof *r);
    if (pipe(fds) < 0)
        return;
    pid_t pid = fork();
    if (pid == 0) {
        dup2(fds[1], 1);
        dup2(fds[1], 2);
        close(fds[0]);
        close(fds[1]);
        execv(argv[0], argv);
        _exit(126);
    }
    close(fds[1]);
    int n;
    while ((n = read(fds[0], r->out + r->len, OUT_MAX - 1 - r->len)) > 0)
        r->len += n;
    close(fds[0]);
    waitpid(pid, &r->status, 0);
}

static void report(const char *name, int ok, const char *detail)
{
    printf("PC %s %s %s\n", name, ok ? "PASS" : "FAIL", ok ? "" : detail);
    fflush(stdout);
}

static int exited_with(struct run_result *r, int code)
{
    return WIFEXITED(r->status) && WEXITSTATUS(r->status) == code;
}

static void dump(const char *name, struct run_result *r)
{
    printf("PC-OUT %s status=%d len=%d\n%s\nPC-END\n", name, r->status, r->len, r->out);
    fflush(stdout);
}

static void check_case(const char *name, char *const argv[], const char *const needles[], int verbose)
{
    struct run_result r;
    run_cmd(argv, &r);
    if (verbose)
        dump(name, &r);
    int ok = exited_with(&r, 0);
    const char *miss = ok ? "" : "exit status";
    for (int i = 0; ok && needles[i]; i++)
        if (!strstr(r.out, needles[i])) {
            ok = 0;
            miss = needles[i];
        }
    report(name, ok, miss);
}

int main(int argc, char **argv)
{
    int verbose = argc > 1 && !strcmp(argv[1], "-v");
    if (argc > 2 && !strcmp(argv[1], "-r")) {
        struct run_result r;
        run_cmd(argv + 2, &r);
        dump("run", &r);
        return 0;
    }
    char *const true_run[] = {"/bin/strace", "/bin/true", NULL};
    const char *const true_need[] = {"execve(", "exit_group(0)", "+++ exited with 0 +++", NULL};
    check_case("strace_true", true_run, true_need, verbose);
    char *const follow_run[] = {"/bin/strace", "-f", "/bin/forker", NULL};
    const char *const follow_need[] = {"[pid", "execve(\"/bin/true\"", "+++ exited with 0 +++", NULL};
    check_case("strace_follow_fork", follow_run, follow_need, verbose);
    char *const static_run[] = {"/bin/strace", "/bin/true_static", NULL};
    const char *const static_need[] = {"execve(", "exit_group(0)", "+++ exited with 0 +++", NULL};
    check_case("strace_static", static_run, static_need, verbose);
    char *const spie_run[] = {"/bin/strace", "/bin/true_spie", NULL};
    check_case("strace_static_pie", spie_run, static_need, verbose);
    char *const filter_run[] = {"/bin/strace", "-f", "-e", "trace=execve", "/bin/forker", NULL};
    const char *const filter_need[] = {"execve(\"/bin/true\"", "+++ exited with 0 +++", NULL};
    check_case("strace_filter", filter_run, filter_need, verbose);
    char *const count_run[] = {"/bin/strace", "-c", "/bin/true", NULL};
    const char *const count_need[] = {"% time", "total", NULL};
    check_case("strace_count", count_run, count_need, verbose);
    char *const direct_static[] = {"/bin/true_static", NULL};
    char *const direct_spie[] = {"/bin/true_spie", NULL};
    const char *const none[] = {NULL};
    check_case("exec_static_direct", direct_static, none, verbose);
    check_case("exec_static_pie_direct", direct_spie, none, verbose);
    return 0;
}
