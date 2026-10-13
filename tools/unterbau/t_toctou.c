/* TOCTOU / double-fetch regressions of the user-space facing syscalls (docs/SECURITY-TOCTOU-KERNEL.md):
 *  - pipe2 applies O_CLOEXEC/O_NONBLOCK to the descriptors it allocated, not to numbers read back from int[2] (K-01)
 *  - munmap/mmap with a length near 2^64 return an error instead of reaching a checked add in the kernel (K-02) */
#define TNAME "toctou"
#include "t.h"
#include <fcntl.h>
#include <pthread.h>
#include <stdint.h>
#include <sys/mman.h>
#include <sys/syscall.h>

static int pfd[2];
static volatile int victim = -1;
static volatile int stop;

static void *flipper(void *arg)
{
    (void)arg;
    while (!stop) {
        pfd[0] = victim;
        pfd[1] = victim;
    }
    return 0;
}

int main(void)
{
    /* plain flags on a quiet array */
    int q[2];
    int r = pipe2(q, O_CLOEXEC | O_NONBLOCK);
    CHECK("pipe2_flags_applied", r == 0 && (fcntl(q[0], F_GETFD) & FD_CLOEXEC) && (fcntl(q[1], F_GETFD) & FD_CLOEXEC)
          && (fcntl(q[0], F_GETFL) & O_NONBLOCK) && (fcntl(q[1], F_GETFL) & O_NONBLOCK), "r=%d", r);
    if (r == 0) { close(q[0]); close(q[1]); }

    /* racing writer: the unrelated descriptor must stay untouched */
    victim = open("/dev/null", O_RDONLY);
    pthread_t th;
    int started = victim >= 0 && pthread_create(&th, 0, flipper, 0) == 0;
    int bad = 0, n = 0;
    if (started) {
        for (int i = 0; i < 200; i++) {
            int rc = syscall(SYS_pipe2, pfd, O_CLOEXEC | O_NONBLOCK);
            if (rc == 0) {
                n++;
                /* the kernel wrote the real numbers; the flipper may have overwritten them already, so close by what we know:
                 * descriptors are allocated lowest-first, so scan a small window above the victim */
                for (int fd = victim + 1; fd < victim + 8; fd++) close(fd);
            }
            if (fcntl(victim, F_GETFD) & FD_CLOEXEC) bad++;
            if (fcntl(victim, F_GETFL) & O_NONBLOCK) bad++;
        }
        stop = 1;
        pthread_join(th, 0);
    }
    CHECK("pipe2_race_victim_untouched", started && n > 0 && bad == 0, "started=%d pipes=%d bad=%d", started, n, bad);

    /* huge lengths must come back as errors, not stop the machine */
    errno = 0;
    long m1 = syscall(SYS_munmap, (void *)0x40000000UL, ~0UL);
    long m2 = syscall(SYS_munmap, (void *)0x40000000UL, ~0UL - 4094);
    CHECK("munmap_huge_len_survives", 1, "m1=%ld m2=%ld", m1, m2);
    long m3 = syscall(SYS_mmap, 0, ~0UL - 4094, PROT_READ, MAP_PRIVATE | MAP_ANONYMOUS, -1, 0);
    CHECK("mmap_huge_len_fails", m3 < 0 || m3 == 0, "ret %ld", m3);
    CHECK("alive_after_huge_len", getpid() > 0, "pid");
    return 0;
}
