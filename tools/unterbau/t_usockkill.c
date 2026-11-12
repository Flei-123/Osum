#define TNAME "usockkill"
#include "t.h"
#include <signal.h>
#include <stdlib.h>
#include <sys/socket.h>
#include <sys/wait.h>

#define ROUNDS 5
#define PAIRS_PER_CHILD 12
#define PROBE_MAX 64

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
    int fin = free_pairs();
    CHECK("final_no_leak", fin >= before, "before=%d final=%d", before, fin);
    return 0;
}
