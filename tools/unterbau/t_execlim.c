#define TNAME "execlim"
#include "t.h"
#include <fcntl.h>
#include <stdlib.h>
#include <sys/stat.h>
#include <sys/syscall.h>
#include <sys/wait.h>

#define CHILD "/bin/c_child"
#define NATIVE_ECHO "/bin/echo"
#define SYS_OSUM_EXEC 1001
#define SCRIPT "/tmp/sb_t"
#define SCRIPT_OUTER "/tmp/sb_o"
#define SPAWN_FAILED 127
#define OUT_CAP 400000
#define NATIVE_MAX_ARGS 254
#define EXEC_MAX_ARGS 256

static char *fill(size_t len, int index)
{
    char *a = malloc(len + 1);
    memset(a, 'a' + index % 26, len);
    a[len] = 0;
    return a;
}

static void write_script(const char *path, const char *interp)
{
    int fd = open(path, O_WRONLY | O_CREAT | O_TRUNC, 0755);
    if (fd < 0)
        return;
    dprintf(fd, "#!%s\n", interp);
    close(fd);
    chmod(path, 0755);
}

static int run(int native, const char *path, char **av, int ac, char *out, size_t cap, int *err)
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
        char *ev[] = { "UB_X=envval", 0 };
        long r = native ? syscall(SYS_OSUM_EXEC, path, av, (long)ac) : (execve(path, av, ev), -1);
        int e = errno;
        if (r < 0)
            (void)!write(pe[1], &e, sizeof e);
        _exit(r < 0 ? SPAWN_FAILED : 0);
    }
    close(po[1]);
    close(pe[1]);
    size_t n = 0;
    ssize_t r;
    while (n < cap - 1 && (r = read(po[0], out + n, cap - 1 - n)) > 0)
        n += r;
    out[n] = 0;
    if (read(pe[0], err, sizeof *err) != (ssize_t)sizeof *err)
        *err = 0;
    close(po[0]);
    close(pe[0]);
    waitpid(p, &st, 0);
    return WIFEXITED(st) ? WEXITSTATUS(st) : -1;
}

static void script_shape(const char *name, const char *script, int lead, int count, size_t len, int want_err)
{
    static char out[OUT_CAP];
    char **av = calloc(count + 2, sizeof *av);
    int err;
    size_t total = strlen(script) + (lead > 3 ? strlen(SCRIPT) : 0);
    av[0] = (char *)script;
    for (int i = 0; i < count; i++) {
        av[1 + i] = fill(len, lead + i);
        total += len;
    }
    char want[160];
    int bad = (int)total;
    for (int i = 0; i < count; i++)
        bad -= (int)len;
    snprintf(want, sizeof want, "verify argc=%d total=%zu bad=%d env=envval\n", lead + count, total, bad);
    int rc = run(0, script, av, count + 1, out, sizeof out, &err);
    if (want_err)
        CHECK(name, rc == SPAWN_FAILED && err == want_err, "rc=%d err=%d", rc, err);
    else
        CHECK(name, rc == 0 && strncmp(out, want, strlen(want)) == 0, "rc=%d err=%d got '%.100s' want '%s'", rc, err, out, want);
    for (int i = 0; i < count; i++)
        free(av[1 + i]);
    free(av);
}

static void native_shape(const char *name, int count, size_t len, int want_err)
{
    static char out[OUT_CAP];
    static char want[OUT_CAP];
    char **av = calloc(count + 2, sizeof *av);
    int err;
    size_t at = 0;
    av[0] = NATIVE_ECHO;
    for (int i = 1; i < count; i++) {
        av[i] = fill(len, i);
        if (at + len + 2 < sizeof want) {
            if (i > 1)
                want[at++] = ' ';
            memcpy(want + at, av[i], len);
            at += len;
        }
    }
    want[at++] = '\n';
    want[at] = 0;
    int rc = run(1, NATIVE_ECHO, av, count, out, sizeof out, &err);
    if (want_err)
        CHECK(name, rc == SPAWN_FAILED && err == want_err, "rc=%d err=%d", rc, err);
    else
        CHECK(name, rc == 0 && strcmp(out, want) == 0, "rc=%d err=%d outlen=%zu wantlen=%zu", rc, err, strlen(out), strlen(want));
    for (int i = 1; i < count; i++)
        free(av[i]);
    free(av);
}

static int make_deep_link(char *link, size_t cap)
{
    char dir[400] = "/tmp";
    for (int i = 0; i < 15; i++) {
        size_t n = strlen(dir);
        snprintf(dir + n, sizeof dir - n, "/d%011d", i);
        if (mkdir(dir, 0755) != 0 && errno != EEXIST)
            return -1;
    }
    snprintf(link, cap, "%s/child", dir);
    unlink(link);
    return symlink(CHILD, link);
}

int main(void)
{
    char deep[500], line[600];
    write_script(SCRIPT, CHILD " verify");
    script_shape("sb_small", SCRIPT, 3, 2, 10, 0);
    script_shape("sb_args_many", SCRIPT, 3, 200, 600, 0);
    script_shape("sb_arg_long", SCRIPT, 3, 1, 100000, 0);
    script_shape("sb_argc_max", SCRIPT, 3, EXEC_MAX_ARGS - 3, 8, 0);
    script_shape("sb_argc_over", SCRIPT, 3, EXEC_MAX_ARGS - 2, 8, E2BIG);
    script_shape("sb_total_over", SCRIPT, 3, 2, 81907, E2BIG);
    write_script(SCRIPT_OUTER, SCRIPT);
    script_shape("sb_chain_big", SCRIPT_OUTER, 4, 2, 70000, 0);
    if (make_deep_link(deep, sizeof deep) == 0) {
        snprintf(line, sizeof line, "%s verify", deep);
        write_script(SCRIPT, line);
        script_shape("sb_interp_long", SCRIPT, 3, 3, 40, 0);
    } else {
        GAP("sb_interp_long", "cannot create deep path errno=%d", errno);
    }
    native_shape("nat_small", 3, 10, 0);
    native_shape("nat_args_many", 200, 20, 0);
    native_shape("nat_arg_4k", 2, 4096, 0);
    native_shape("nat_arg_100k", 2, 100000, 0);
    native_shape("nat_argc_max", NATIVE_MAX_ARGS, 8, 0);
    native_shape("nat_argc_over", NATIVE_MAX_ARGS + 1, 8, E2BIG);
    native_shape("nat_total_over", 4, 60000, E2BIG);
    return 0;
}
