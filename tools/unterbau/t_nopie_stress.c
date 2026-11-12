/* SPDX-License-Identifier: GPL-2.0-only
 * static non-PIE: parallel fork/exec/exit of low-window processes while the kernel re-mirrors page-directory entries. */
#define TNAME "nopie_stress"
#include "t.h"
#include <fcntl.h>
#include <stdint.h>
#include <stdlib.h>
#include <sys/wait.h>

#define WORKERS 6
#define ROUNDS 25
#define MIRROR_PATH "/proc/sys/debug/pdmirror_stress"

static int cells[2048] = { 1 };
static char *argv0;

static long mirror_once(void)
{
    char buf[32];
    int fd = open(MIRROR_PATH, O_RDONLY);
    if (fd < 0) return -1;
    ssize_t n = read(fd, buf, sizeof buf - 1);
    close(fd);
    if (n <= 0) return -2;
    buf[n] = 0;
    return atol(buf);
}

static int worker(int id)
{
    int bad = 0;
    for (int r = 0; r < ROUNDS; r++) {
        cells[id] = r + 1;
        pid_t c = fork();
        if (c == 0) {
            cells[id] += 100;
            mirror_once();
            if (r % 3 == 0) {
                char *args[] = { argv0, "child", NULL };
                execv(argv0, args);
                _exit(77);
            }
            _exit(cells[id] == r + 101 ? 0 : 9);
        }
        if (c < 0) { bad++; continue; }
        int st = 0;
        pid_t w = waitpid(c, &st, 0);
        if (w != c || !WIFEXITED(st) || WEXITSTATUS(st) != (r % 3 == 0 ? 5 : 0)) bad++;
        if (cells[id] != r + 1) bad++;
        if (mirror_once() < 0) bad++;
    }
    return bad;
}

int main(int argc, char **argv)
{
    if (argc > 1 && strcmp(argv[1], "child") == 0) return 5;
    argv0 = argv[0];
    long probe = mirror_once();
    if (probe < 0) { GAP("mirror_hook", "no %s (%ld)", MIRROR_PATH, probe); return 0; }
    CHECK("mirror_hook", probe > 0, "rounds %ld", probe);
    CHECK("link_address", (uintptr_t)cells >= 0x400000 && (uintptr_t)cells < 0x1000000, "at %p", (void *)cells);

    pid_t pids[WORKERS];
    for (int i = 0; i < WORKERS; i++) {
        pids[i] = fork();
        if (pids[i] == 0) _exit(worker(i));
    }
    int total_bad = 0, finished = 0;
    for (int i = 0; i < WORKERS; i++) {
        int st = 0;
        if (pids[i] > 0 && waitpid(pids[i], &st, 0) == pids[i] && WIFEXITED(st)) {
            finished++;
            total_bad += WEXITSTATUS(st);
        }
    }
    CHECK("workers_finished", finished == WORKERS, "finished %d of %d", finished, WORKERS);
    CHECK("no_bad_rounds", total_bad == 0, "bad %d", total_bad);

    int burst_bad = 0;
    for (int i = 0; i < 40; i++) {
        pid_t c = fork();
        if (c == 0) { mirror_once(); _exit(3); }
        int st = 0;
        if (c < 0 || waitpid(c, &st, 0) != c || !WIFEXITED(st) || WEXITSTATUS(st) != 3) burst_bad++;
    }
    CHECK("sequential_burst", burst_bad == 0, "bad %d", burst_bad);
    CHECK("parent_data_intact", cells[0] == 1 && mirror_once() > 0, "cell %d", cells[0]);
    return 0;
}
