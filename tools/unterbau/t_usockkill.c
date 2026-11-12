#define TNAME "usockkill"
#include "t.h"
#include <signal.h>
#include <stdlib.h>
#include <sys/socket.h>
#include <sys/wait.h>

#define ROUNDS 5
#define PAIRS_PER_CHILD 12
#define PROBE_MAX 192
#define SOCKET_LIMIT 128
#define LIMIT_MIN_REACH 100

static int probe_fds[PROBE_MAX * 2];

static int free_pairs(void)
{
    int n = 0;
    while (n < PROBE_MAX) {
        int sv[2];
        if (socketpair(AF_UNIX, SOCK_STREAM, 0, sv) != 0) break;
        probe_fds[n * 2] = sv[0];
        probe_fds[n * 2 + 1] = sv[1];
        n++;
    }
    for (int i = 0; i < n * 2; i++) close(probe_fds[i]);
    return n;
}

static int grab_singles(int *fds, int max, int *last_errno)
{
    int n = 0;
    *last_errno = 0;
    while (n < max) {
        int fd = socket(AF_UNIX, SOCK_STREAM, 0);
        if (fd < 0) {
            *last_errno = errno;
            break;
        }
        fds[n++] = fd;
    }
    return n;
}

static void release(int *fds, int n)
{
    for (int i = 0; i < n; i++) close(fds[i]);
}

static void check_limit(void)
{
    int fds[PROBE_MAX * 2];
    int err = 0;
    int first = grab_singles(fds, PROBE_MAX * 2, &err);
    int first_err = err;
    release(fds, first);
    int second = grab_singles(fds, PROBE_MAX * 2, &err);
    release(fds, second);
    CHECK("limit_reaches_beyond_old_cap", first >= LIMIT_MIN_REACH, "reached=%d", first);
    CHECK("limit_at_new_cap", first <= SOCKET_LIMIT, "reached=%d limit=%d", first, SOCKET_LIMIT);
    CHECK("limit_error_is_enfile", first_err == ENFILE, "errno=%d", first_err);
    CHECK("limit_no_leak_on_release", second == first, "first=%d second=%d", first, second);
}

static void grab_pairs(int count)
{
    for (int i = 0; i < count; i++) {
        int sv[2];
        if (socketpair(AF_UNIX, SOCK_STREAM, 0, sv) != 0) break;
    }
}

static void die_by_sigkill(void) { kill(getpid(), SIGKILL); for (;;) pause(); }
static void die_by_segv(void) { *(volatile int *)0 = 1; _exit(3); }
static void die_by_exit(void) { _exit(0); }
static void die_by_abort(void) { abort(); }

static int run_children(void (*die)(void))
{
    int clean = 1;
    for (int r = 0; r < ROUNDS; r++) {
        pid_t pid = fork();
        if (pid < 0) return 0;
        if (pid == 0) {
            grab_pairs(PAIRS_PER_CHILD);
            die();
        }
        int st = 0;
        if (waitpid(pid, &st, 0) != pid) clean = 0;
    }
    return clean;
}

static int killed_from_outside(void)
{
    int clean = 1;
    for (int r = 0; r < ROUNDS; r++) {
        int gate[2];
        if (pipe(gate) != 0) return 0;
        pid_t pid = fork();
        if (pid < 0) return 0;
        if (pid == 0) {
            close(gate[0]);
            grab_pairs(PAIRS_PER_CHILD);
            (void)!write(gate[1], "r", 1);
            for (;;) pause();
        }
        close(gate[1]);
        char c;
        if (read(gate[0], &c, 1) != 1) clean = 0;
        close(gate[0]);
        kill(pid, SIGKILL);
        int st = 0;
        if (waitpid(pid, &st, 0) != pid) clean = 0;
    }
    return clean;
}

static int shared_end_survives(void)
{
    int sv[2];
    if (socketpair(AF_UNIX, SOCK_STREAM, 0, sv) != 0) return 0;
    pid_t pid = fork();
    if (pid < 0) return 0;
    if (pid == 0) {
        close(sv[0]);
        (void)!write(sv[1], "x", 1);
        die_by_sigkill();
    }
    close(sv[1]);
    int st = 0;
    waitpid(pid, &st, 0);
    char c = 0;
    int got = (int)read(sv[0], &c, 1);
    char d = 0;
    int eof = (int)read(sv[0], &d, 1);
    close(sv[0]);
    return got == 1 && c == 'x' && eof == 0;
}

static void check_mode(const char *name, void (*die)(void), int before)
{
    int ran = run_children(die);
    int after = free_pairs();
    CHECK(name, ran && after >= before, "before=%d after=%d ran=%d", before, after, ran);
}

int main(void)
{
    int before = free_pairs();
    CHECK("baseline_room", before >= PAIRS_PER_CHILD, "pairs=%d", before);
    check_mode("exit_frees", die_by_exit, before);
    check_mode("sigkill_self_frees", die_by_sigkill, before);
    check_mode("segv_frees", die_by_segv, before);
    check_mode("abort_frees", die_by_abort, before);
    int ok = killed_from_outside();
    int after = free_pairs();
    CHECK("kill_from_outside_frees", ok && after >= before, "before=%d after=%d ran=%d", before, after, ok);
    CHECK("shared_end_survives", shared_end_survives(), "");
    check_limit();
    int fin = free_pairs();
    CHECK("final_no_leak", fin >= before, "before=%d final=%d", before, fin);
    return 0;
}
