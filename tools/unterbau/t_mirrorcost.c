/* SPDX-License-Identifier: GPL-2.0-only
 * cost of pdmirror.mirror with 0, 1 and 20 low-page-directory processes (PIE measurer, static non-PIE holders). */
#define TNAME "mirrorcost"
#include "t.h"
#include <fcntl.h>
#include <stdlib.h>
#include <time.h>
#include <sys/wait.h>

#define HOLD_MAX 20
#define MIRROR_PATH "/proc/sys/debug/pdmirror_stress"
#define CALLS 10

static int hold_in[HOLD_MAX];
static pid_t hold_pid[HOLD_MAX];
static int held;

static long long now_ns(void)
{
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return (long long)ts.tv_sec * 1000000000LL + ts.tv_nsec;
}

static int hold_one(void)
{
    int in[2], out[2];
    if (pipe(in) || pipe(out)) return -1;
    pid_t c = fork();
    if (c == 0) {
        dup2(in[0], 0);
        dup2(out[1], 1);
        for (int fd = 3; fd < 64; fd++) close(fd);
        char *args[] = { "/bin/c_lowhold", NULL };
        execv(args[0], args);
        _exit(77);
    }
    if (c < 0) return -1;
    char r;
    if (read(out[0], &r, 1) != 1) return -1;
    close(in[0]); close(out[0]); close(out[1]);
    hold_in[held] = in[1];
    hold_pid[held] = c;
    held++;
    return 0;
}

static void hold_to(int n)
{
    while (held < n && hold_one() == 0) {}
}

static void release_all(void)
{
    for (int i = 0; i < held; i++) { close(hold_in[i]); waitpid(hold_pid[i], NULL, 0); }
    held = 0;
}

static long long per_call_ns(void)
{
    char buf[32];
    long long best = -1;
    for (int k = 0; k < CALLS; k++) {
        int fd = open(MIRROR_PATH, O_RDONLY);
        if (fd < 0) return -1;
        long long t0 = now_ns();
        ssize_t n = read(fd, buf, sizeof buf - 1);
        long long dt = now_ns() - t0;
        close(fd);
        if (n <= 0) return -2;
        buf[n] = 0;
        long rounds = atol(buf);
        if (rounds <= 0) return -3;
        long long each = dt / rounds;
        if (best < 0 || each < best) best = each;
    }
    return best;
}

int main(void)
{
    long long c0 = per_call_ns();
    if (c0 < 0) { GAP("hook", "no %s (%lld)", MIRROR_PATH, c0); return 0; }
    hold_to(1);
    long long c1 = per_call_ns();
    hold_to(HOLD_MAX);
    long long c20 = per_call_ns();
    CHECK("holders_started", held == HOLD_MAX, "held %d", held);
    CHECK("cost_zero_owners_ns", c0 >= 0 && c0 < 2000, "%lld ns per mirror call", c0);
    CHECK("cost_one_owner_ns", c1 >= 0 && c1 < 20000, "%lld ns per mirror call", c1);
    CHECK("cost_twenty_owners_ns", c20 >= 0 && c20 < 40000, "%lld ns per mirror call", c20);
    CHECK("zero_cheaper_than_owned", c0 <= c1 && c0 <= c20, "c0 %lld c1 %lld c20 %lld", c0, c1, c20);
    PASS("measured_ns", "owners0=%lld owners1=%lld owners20=%lld", c0, c1, c20);
    release_all();
    long long after = per_call_ns();
    CHECK("cost_back_to_zero_ns", after >= 0 && after < 2000, "%lld ns per mirror call", after);
    return 0;
}
