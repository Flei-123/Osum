/* SPDX-License-Identifier: GPL-2.0-only
 * Shared-memory objects (memfd, MAP_SHARED of a file) are served from the frames ABOVE the first GiB when that window is empty:
 * memfd map + touch, read(2)/write(2) on a memfd, a forked child seeing the parent's pages, MAP_SHARED file fill + msync write-back. */
#define TNAME "shmhigh"
#include "t.h"
#include "lowpress.h"
#include <sys/syscall.h>
#include <sys/wait.h>

#define LEAVE_FRAMES 4096
#define MEMFD_BYTES (64UL << 20)
#define FILE_PAGES 64

static unsigned char pattern(unsigned long i) { return (unsigned char)((i * 131 + (i >> 8)) & 0xFF); }

static unsigned char out[3 * LP_PAGE + 100], in[sizeof out];
static unsigned char file_data[FILE_PAGES * LP_PAGE], back[sizeof file_data];

static ssize_t pwrite_all(int fd, const unsigned char *buf, size_t len, off_t off)
{
    size_t done = 0;
    while (done < len) {
        ssize_t n = pwrite(fd, buf + done, len - done, off + done);
        if (n <= 0) return n < 0 ? n : (ssize_t)done;
        done += n;
    }
    return done;
}

static ssize_t pread_all(int fd, unsigned char *buf, size_t len, off_t off)
{
    size_t done = 0;
    while (done < len) {
        ssize_t n = pread(fd, buf + done, len - done, off + done);
        if (n <= 0) return n < 0 ? n : (ssize_t)done;
        done += n;
    }
    return done;
}

static int memfd(void) { return syscall(SYS_memfd_create, "shmhigh", 0); }

static long shm_failures(void)
{
    return lp_meminfo("ShmFailMemfd:") + lp_meminfo("ShmFailTruncate:") + lp_meminfo("ShmFailMmap:");
}

int main(void)
{
    long total_kb = lp_meminfo("MemTotal:");
    long free_kb = lp_meminfo("MemFree:");
    long low0 = lp_free_low();
    CHECK("memory_above_window", total_kb > 2L * 1024 * 1024 && low0 > 0 && free_kb > 1024L * 1024, "total=%ldkB free=%ldkB low=%ld", total_kb, free_kb, low0);
    long held = lowpress_eat(LEAVE_FRAMES);
    long low1 = lp_free_low();
    long free1 = lp_meminfo("MemFree:");
    CHECK("window_emptied", low1 >= 0 && low1 <= 2 * LEAVE_FRAMES && free1 > 1024L * 1024, "held=%ld low=%ld free=%ldkB", held, low1, free1);
    long fails0 = shm_failures();

    int fd = memfd();
    errno = 0;
    int rc = fd < 0 ? -1 : ftruncate(fd, MEMFD_BYTES);
    CHECKC("memfd_truncate", rc == 0);
    unsigned char *m = (unsigned char *)mmap(0, MEMFD_BYTES, PROT_READ | PROT_WRITE, MAP_SHARED, fd, 0);
    CHECKC("memfd_map_when_window_empty", m != MAP_FAILED);
    if (m == MAP_FAILED) return 0;
    for (unsigned long i = 0; i < MEMFD_BYTES; i += LP_PAGE) m[i] = pattern(i);
    unsigned long bad = 0;
    for (unsigned long i = 0; i < MEMFD_BYTES; i += LP_PAGE) if (m[i] != pattern(i)) bad++;
    CHECK("memfd_pages_hold_data", bad == 0, "bad=%lu", bad);
    long free2 = lp_meminfo("MemFree:");
    CHECK("pages_come_from_above_window", free1 - free2 > (long)(MEMFD_BYTES >> 10) * 9 / 10 && lp_free_low() <= 2 * LEAVE_FRAMES, "free %ld -> %ldkB low=%ld", free1, free2, lp_free_low());

    pid_t child = fork();
    if (child == 0) {
        unsigned long cbad = 0;
        for (unsigned long i = 0; i < MEMFD_BYTES; i += LP_PAGE) if (m[i] != pattern(i)) cbad++;
        _exit(cbad == 0 ? 0 : 1);
    }
    int status = 0;
    waitpid(child, &status, 0);
    CHECK("fork_child_sees_pages", WIFEXITED(status) && WEXITSTATUS(status) == 0, "status=%d", status);

    int fd2 = memfd();
    for (unsigned long i = 0; i < sizeof out; i++) out[i] = pattern(i + 7);
    ssize_t wn = fd2 >= 0 ? pwrite_all(fd2, out, sizeof out, 1000) : -1;
    CHECK("memfd_write_syscall", wn == (ssize_t)sizeof out, "wrote=%zd want=%zu errno=%d", wn, sizeof out, errno);
    memset(in, 0, sizeof in);
    ssize_t rn = pread_all(fd2, in, sizeof in, 1000);
    CHECK("memfd_read_syscall", rn == (ssize_t)sizeof in, "read=%zd want=%zu errno=%d", rn, sizeof in, errno);
    CHECK("memfd_read_matches_write", memcmp(in, out, sizeof in) == 0, "mismatch");
    unsigned char *m2 = (unsigned char *)mmap(0, sizeof out + 1000, PROT_READ, MAP_SHARED, fd2, 0);
    CHECK("memfd_map_sees_write_syscall", m2 != MAP_FAILED && memcmp(m2 + 1000, out, sizeof out) == 0, "mismatch");

    int ff = open("/tmp/shmhigh.dat", O_RDWR | O_CREAT | O_TRUNC, 0600);
    for (unsigned long i = 0; i < sizeof file_data; i++) file_data[i] = pattern(i + 3);
    int wrote = ff >= 0 && write(ff, file_data, sizeof file_data) == (ssize_t)sizeof file_data;
    unsigned char *fm = wrote ? (unsigned char *)mmap(0, sizeof file_data, PROT_READ | PROT_WRITE, MAP_SHARED, ff, 0) : (unsigned char *)MAP_FAILED;
    CHECKC("file_map_shared_when_window_empty", fm != MAP_FAILED);
    if (fm != MAP_FAILED) {
        CHECK("file_map_filled_from_file", memcmp(fm, file_data, sizeof file_data) == 0, "mismatch");
        for (unsigned long i = 0; i < sizeof file_data; i += 512) fm[i] ^= 0xFF;
        CHECKC("file_msync", msync(fm, sizeof file_data, MS_SYNC) == 0);
        munmap(fm, sizeof file_data);
        long got = pread_all(ff, back, sizeof back, 0);
        unsigned long fbad = 0;
        for (unsigned long i = 0; got == (long)sizeof back && i < sizeof back; i++) {
            unsigned char want = file_data[i] ^ ((i % 512) == 0 ? 0xFF : 0);
            if (back[i] != want) fbad++;
        }
        CHECK("file_writeback_reaches_file", got == (long)sizeof back && fbad == 0, "got=%ld bad=%lu errno=%d", got, fbad, errno);
    }
    close(ff);
    unlink("/tmp/shmhigh.dat");

    CHECK("no_shm_failures_counted", shm_failures() == fails0, "before=%ld after=%ld", fails0, shm_failures());
    munmap(m, MEMFD_BYTES);
    close(fd);
    close(fd2);
    return 0;
}
