/* the table sizes of the kernel against what a browser needs: descriptors, threads, processes, address space, stack, pipe. */
#define TNAME "limits"
#include "t.h"
#include <fcntl.h>
#include <pthread.h>
#include <signal.h>
#include <stdlib.h>
#include <sys/mman.h>
#include <sys/wait.h>

static void *sleeper(void *a) { (void)a; sleep(2); return 0; }
static int depth_reached, depth_fd;
static int recurse(int n) { volatile char pad[4000]; pad[0] = (char)n; pad[3999] = (char)n; depth_reached = n; if (n % 50 == 0) (void)!write(depth_fd, &n, sizeof n); if (n < 3000) return recurse(n + 1) + pad[0]; return pad[3999]; }

int main(void)
{
    /* descriptors per process */
    int fds[2048], n = 0; errno = 0;
    for (; n < 2048; n++) { fds[n] = open("/etc/passwd", O_RDONLY); if (fds[n] < 0) break; }
    int e = errno;
    for (int i = 0; i < n; i++) close(fds[i]);
    t_emit("fds_per_process", n >= 256 ? "PASS" : "FAIL", "%d descriptors open at once (errno %d); a browser wants >= 256", n, e);

    /* threads alive at once */
    pthread_t th[200]; int t = 0;
    for (; t < 200; t++) if (pthread_create(&th[t], 0, sleeper, 0)) break;
    int te = errno;
    for (int i = 0; i < t; i++) pthread_join(th[i], 0);
    t_emit("threads_at_once", t >= 64 ? "PASS" : "FAIL", "%d threads alive at once (errno %d); a browser wants >= 64", t, te);

    /* processes alive at once */
    pid_t pids[100]; int p = 0;
    for (; p < 100; p++) { pids[p] = fork(); if (pids[p] == 0) { sleep(3); _exit(0); } if (pids[p] < 0) break; }
    for (int i = 0; i < p; i++) { kill(pids[i], SIGKILL); }
    for (int i = 0; i < p; i++) waitpid(pids[i], 0, 0);
    t_emit("processes_at_once", p >= 16 ? "PASS" : "FAIL", "%d processes alive at once; a browser wants >= 16", p);

    /* committed memory */
    size_t got = 0; void *chunks[600]; int c = 0;
    for (; c < 600; c++) { chunks[c] = mmap(0, 1 << 20, PROT_READ | PROT_WRITE, MAP_PRIVATE | MAP_ANONYMOUS, -1, 0); if (chunks[c] == MAP_FAILED) break; got += 1 << 20; }
    for (int i = 0; i < c; i++) munmap(chunks[i], 1 << 20);
    t_emit("committed_mib", got >= (256u << 20) ? "PASS" : "FAIL", "%zu MiB of anonymous memory in 1 MiB maps; a browser wants >= 256 MiB of address space", got >> 20);

    /* reserved address space */
    size_t res = 0; void *rs[64]; int r = 0;
    for (; r < 64; r++) { rs[r] = mmap(0, 256u << 20, PROT_NONE, MAP_PRIVATE | MAP_ANONYMOUS | MAP_NORESERVE, -1, 0); if (rs[r] == MAP_FAILED) break; res += 256u << 20; }
    for (int i = 0; i < r; i++) munmap(rs[i], 256u << 20);
    t_emit("reserved_mib", res >= (4096ul << 20) ? "PASS" : "FAIL", "%zu MiB of PROT_NONE reservations; JS engines and allocators reserve GiB", res >> 20);

    /* main thread stack: recursion with 4 KB frames */
    depth_reached = 0;
    int dp[2]; (void)!pipe(dp); depth_fd = dp[1];
    pid_t k = fork();
    if (k == 0) { close(dp[0]); recurse(0); _exit(0); }
    close(dp[1]);
    int st; waitpid(k, &st, 0);
    { int v; while (read(dp[0], &v, sizeof v) == (ssize_t)sizeof v) depth_reached = v; }
    t_emit("stack_depth_4k_frames", depth_reached >= 2000 ? "PASS" : "FAIL", "recursion depth %d x 4 KB (%d KB of stack) before the stack ended; a browser wants 8 MiB", depth_reached, depth_reached * 4);

    /* thread stack default and a pipe's capacity */
    int pp[2]; (void)!pipe2(pp, O_NONBLOCK); size_t cap = 0; char blk[512]; memset(blk, 1, sizeof blk);
    for (;;) { ssize_t w = write(pp[1], blk, sizeof blk); if (w <= 0) break; cap += w; if (cap > (1 << 20)) break; }
    t_emit("pipe_capacity", cap >= 65536 ? "PASS" : "FAIL", "%zu bytes fit into a pipe before the writer must wait; Linux: 65536", cap);

    /* a large file write and read back */
    int fd = open("/tmp/ub_big.dat", O_RDWR | O_CREAT | O_TRUNC, 0600); size_t wr = 0; char *big = malloc(1 << 20); memset(big, 7, 1 << 20);
    for (int i = 0; i < 8 && fd >= 0; i++) { ssize_t w = write(fd, big, 1 << 20); if (w <= 0) break; wr += w; }
    t_emit("file_8mib_write", wr == (8u << 20) ? "PASS" : "FAIL", "%zu of 8 MiB written to /tmp (errno %d)", wr, errno);
    close(fd); unlink("/tmp/ub_big.dat");
    return 0;
}
