/* SPDX-License-Identifier: GPL-2.0-only
 * Empties the low frame window (first GiB) with private file pages (lazy file faults take their frames from the window only), so that
 * shared-memory objects can only be served from the frames above it. lowpress_eat(leave_frames) returns the number of pages held. */
#define _GNU_SOURCE
#include <fcntl.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mman.h>
#include <unistd.h>

#define LP_FILE_BYTES (8UL << 20)
#define LP_PAGE 4096UL
#define LP_CHECK_EVERY 128
#define LP_MAX_MAPS 400

static long lp_meminfo(const char *name)
{
    char buf[8192];
    int fd = open("/proc/meminfo", O_RDONLY);
    int n = fd < 0 ? 0 : read(fd, buf, sizeof buf - 1);
    if (fd >= 0) close(fd);
    buf[n > 0 ? n : 0] = 0;
    char *p = strstr(buf, name);
    return p ? strtol(p + strlen(name), 0, 10) : -1;
}

static long lp_free_low(void) { return lp_meminfo("FramesFreeLow:"); }

static long lowpress_eat(long leave_frames)
{
    long held = 0;
    int fd = open("/tmp/lowpress.dat", O_RDWR | O_CREAT | O_TRUNC, 0600);
    if (fd < 0 || ftruncate(fd, LP_FILE_BYTES) < 0) return -1;
    for (int m = 0; m < LP_MAX_MAPS; m++) {
        char *p = mmap(0, LP_FILE_BYTES, PROT_READ | PROT_WRITE, MAP_PRIVATE, fd, 0);
        if (p == MAP_FAILED) break;
        for (unsigned long off = 0; off < LP_FILE_BYTES; off += LP_PAGE) {
            if ((off / LP_PAGE) % LP_CHECK_EVERY == 0 && lp_free_low() <= leave_frames) return held;
            p[off] = 1;
            held++;
        }
    }
    return held;
}
