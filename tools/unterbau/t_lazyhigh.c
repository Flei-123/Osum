/* SPDX-License-Identifier: GPL-2.0-only
 * With the first GiB nearly empty, lazy private file pages (read and copy-on-write), page tables of sparse mappings and a forked copy
 * of them are served from frames above it: the data is right and the low window is not drained. */
#define TNAME "lazyhigh"
#include "t.h"
#include "lowpress.h"
#include <sys/wait.h>

#define LEAVE_FRAMES 4096
#define FILE_PAGES 4096
#define SPARSE_SLOTS 192
#define SLOT_BYTES (2UL << 20)
#define LOW_BUDGET 512

static unsigned char pattern(unsigned long i) { return (unsigned char)((i * 61 + (i >> 7) + 5) & 0xFF); }

static unsigned long verify_pages(const unsigned char *p, unsigned long pages)
{
    unsigned long bad = 0;
    for (unsigned long pg = 0; pg < pages; pg++)
        if (p[pg * LP_PAGE] != pattern(pg) || p[pg * LP_PAGE + LP_PAGE - 1] != pattern(pg + 1)) bad++;
    return bad;
}

int main(void)
{
    long total_kb = lp_meminfo("MemTotal:");
    CHECK("memory_above_window", total_kb > 2L * 1024 * 1024 && lp_free_low() > 0, "total=%ldkB low=%ld", total_kb, lp_free_low());
    lowpress_eat(LEAVE_FRAMES);
    long low0 = lp_free_low();
    CHECK("window_emptied", low0 <= 2 * LEAVE_FRAMES, "low=%ld", low0);

    int fd = open("/tmp/lazyhigh.dat", O_RDWR | O_CREAT | O_TRUNC, 0600);
    unsigned char page[LP_PAGE];
    int wrote = fd >= 0;
    for (unsigned long pg = 0; wrote && pg < FILE_PAGES; pg++) {
        memset(page, 0, sizeof page);
        page[0] = pattern(pg);
        page[LP_PAGE - 1] = pattern(pg + 1);
        wrote = write(fd, page, sizeof page) == (ssize_t)sizeof page;
    }
    CHECK("file_written", wrote, "errno=%d", errno);
    unsigned char *m = (unsigned char *)mmap(0, FILE_PAGES * LP_PAGE, PROT_READ | PROT_WRITE, MAP_PRIVATE, fd, 0);
    CHECKC("file_map_private", m != MAP_FAILED);
    if (m == MAP_FAILED) return 0;

    long before = lp_free_low();
    unsigned long bad = verify_pages(m, FILE_PAGES);
    long used = before - lp_free_low();
    CHECK("private_read_content", bad == 0, "bad=%lu", bad);
    CHECK("private_read_spares_window", used < LOW_BUDGET, "low frames used=%ld", used);

    before = lp_free_low();
    for (unsigned long pg = 0; pg < FILE_PAGES; pg++) m[pg * LP_PAGE + 1] = 0xA5;
    used = before - lp_free_low();
    unsigned long cow_bad = verify_pages(m, FILE_PAGES);
    for (unsigned long pg = 0; pg < FILE_PAGES; pg++) if (m[pg * LP_PAGE + 1] != 0xA5) cow_bad++;
    CHECK("private_write_content", cow_bad == 0, "bad=%lu", cow_bad);
    CHECK("private_write_spares_window", used < LOW_BUDGET, "low frames used=%ld", used);
    unsigned char probe[2] = {1, 1};
    CHECK("private_write_not_in_file", pread(fd, probe, 1, 1) == 1 && probe[0] == 0, "file byte=%d", probe[0]);

    before = lp_free_low();
    unsigned char *s = (unsigned char *)mmap(0, SPARSE_SLOTS * SLOT_BYTES, PROT_READ | PROT_WRITE, MAP_PRIVATE | MAP_ANONYMOUS | MAP_NORESERVE, -1, 0);
    CHECKC("sparse_map", s != MAP_FAILED);
    if (s != MAP_FAILED) {
        for (unsigned long k = 0; k < SPARSE_SLOTS; k++) s[k * SLOT_BYTES + 12345] = pattern(k);
        unsigned long sbad = 0;
        for (unsigned long k = 0; k < SPARSE_SLOTS; k++) if (s[k * SLOT_BYTES + 12345] != pattern(k)) sbad++;
        used = before - lp_free_low();
        CHECK("sparse_content", sbad == 0, "bad=%lu", sbad);
        CHECK("page_tables_spare_window", used < LOW_BUDGET, "low frames used=%ld", used);

        pid_t child = fork();
        if (child == 0) {
            unsigned long cbad = verify_pages(m, FILE_PAGES);
            for (unsigned long k = 0; k < SPARSE_SLOTS; k++) if (s[k * SLOT_BYTES + 12345] != pattern(k)) cbad++;
            for (unsigned long k = 0; k < SPARSE_SLOTS; k++) s[k * SLOT_BYTES + 12345] = 0;
            _exit(cbad == 0 ? 0 : 1);
        }
        int status = 0;
        waitpid(child, &status, 0);
        CHECK("fork_child_sees_pages", WIFEXITED(status) && WEXITSTATUS(status) == 0, "status=%d", status);
        unsigned long pbad = 0;
        for (unsigned long k = 0; k < SPARSE_SLOTS; k++) if (s[k * SLOT_BYTES + 12345] != pattern(k)) pbad++;
        CHECK("fork_child_write_private", pbad == 0, "bad=%lu", pbad);
        munmap(s, SPARSE_SLOTS * SLOT_BYTES);
    }
    CHECK("window_still_tight", lp_free_low() <= 2 * LEAVE_FRAMES, "low=%ld", lp_free_low());
    munmap(m, FILE_PAGES * LP_PAGE);
    close(fd);
    unlink("/tmp/lazyhigh.dat");
    return 0;
}
