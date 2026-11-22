#define TNAME "execbig"
#include "t.h"
#include <fcntl.h>
#include <stdlib.h>
#include <sys/wait.h>

#define CHILD "/bin/c_child"
#define OUT_BYTES 256
#define MAX_ARG_BYTES 131072
#define MAX_ARGS 4096

static char *make_arg(size_t len, int index)
{
    char *a = malloc(len + 1);
    memset(a, 'a' + index % 26, len);
    a[len] = 0;
    return a;
}

static int run_child(char **av, char **ev, char *out, int *err)
{
    int po[2], pe[2];
    int st = 0;
    out[0] = 0;
    *err = 0;
    if (pipe(po) != 0 || pipe2(pe, O_CLOEXEC) != 0)
        return -1;
    pid_t p = fork();
    if (p == 0) {
        dup2(po[1], 1);
        close(po[0]);
        close(po[1]);
        execve(CHILD, av, ev);
        int e = errno;
        (void)!write(pe[1], &e, sizeof e);
        _exit(127);
    }
    close(po[1]);
    close(pe[1]);
    int n = 0, r;
    while (n < OUT_BYTES - 1 && (r = read(po[0], out + n, OUT_BYTES - 1 - n)) > 0)
        n += r;
    out[n] = 0;
    if (read(pe[0], err, sizeof *err) != (ssize_t)sizeof *err)
        *err = 0;
    close(po[0]);
    close(pe[0]);
    waitpid(p, &st, 0);
    return WIFEXITED(st) ? WEXITSTATUS(st) : -1;
}

static void run_shape(const char *name, int count, size_t len, const char *want, int want_err)
{
    char out[OUT_BYTES];
    char **av = calloc(count + 3, sizeof *av);
    int err;
    av[0] = "c_child";
    av[1] = "verify";
    for (int i = 0; i < count; i++)
        av[2 + i] = make_arg(len, 2 + i);
    char *ev[] = { "UB_X=envval", 0 };
    int rc = run_child(av, ev, out, &err);
    if (want_err) {
        CHECK(name, rc == 127 && err == want_err, "rc=%d err=%d", rc, err);
    } else {
        CHECK(name, rc == 0 && strcmp(out, want) == 0, "rc=%d err=%d got '%s'", rc, err, out);
    }
    for (int i = 0; i < count; i++)
        free(av[2 + i]);
    free(av);
}

int main(void)
{
    run_shape("arg_4k", 1, 4096, "verify argc=3 total=4096 bad=0 env=envval\n", 0);
    run_shape("arg_100k", 1, 100000, "verify argc=3 total=100000 bad=0 env=envval\n", 0);
    run_shape("arg_max", 1, MAX_ARG_BYTES - 1, "verify argc=3 total=131071 bad=0 env=envval\n", 0);
    run_shape("arg_over_max", 1, MAX_ARG_BYTES, "", E2BIG);
    run_shape("args_many_small", 200, 600, "verify argc=202 total=120000 bad=0 env=envval\n", 0);
    run_shape("args_total_ok", 2, 70000, "verify argc=4 total=140000 bad=0 env=envval\n", 0);
    run_shape("args_total_over", 3, 60000, "", E2BIG);
    run_shape("args_count_max", MAX_ARGS - 2, 8, "verify argc=4096 total=32752 bad=0 env=envval\n", 0);
    run_shape("args_count_over", MAX_ARGS, 8, "", E2BIG);
    run_shape("args_count_1000", 1000, 20, "verify argc=1002 total=20000 bad=0 env=envval\n", 0);
    run_shape("args_count_100", 100, 20, "verify argc=102 total=2000 bad=0 env=envval\n", 0);
    return 0;
}
