/* SPDX-License-Identifier: GPL-2.0-only
 * Eats the low frame window (first GiB, where kernel tables and shared-memory demand pages come from) through mapped memfds,
 * leaves <MiB> free in it and holds the rest in a background child. Usage: shmpress <leave-free-MiB> */
#define _GNU_SOURCE
#include <fcntl.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mman.h>
#include <sys/syscall.h>
#include <unistd.h>

#define OBJ_BYTES (32UL << 20)
#define PAGE 4096UL
#define CHECK_EVERY 256
#define MAX_OBJECTS 400

static long free_low_frames(void)
{
    char buf[4096];
    int fd = open("/proc/meminfo", O_RDONLY);
    int n = fd < 0 ? 0 : read(fd, buf, sizeof buf - 1);
    if (fd >= 0) close(fd);
    buf[n > 0 ? n : 0] = 0;
    char *p = strstr(buf, "FramesFreeLow:");
    return p ? strtol(p + 14, 0, 10) : -1;
}

int main(int argc, char **argv)
{
    long leave = (argc > 1 ? atol(argv[1]) : 64) << 8;
    long held = 0;
    for (int o = 0; o < MAX_OBJECTS; o++) {
        int fd = syscall(SYS_memfd_create, "shmpress", 0);
        if (fd < 0 || ftruncate(fd, OBJ_BYTES) < 0) break;
        char *m = mmap(0, OBJ_BYTES, PROT_READ | PROT_WRITE, MAP_SHARED, fd, 0);
        if (m == MAP_FAILED) break;
        for (unsigned long off = 0; off < OBJ_BYTES; off += PAGE) {
            if ((off / PAGE) % CHECK_EVERY == 0 && free_low_frames() <= leave) goto done;
            m[off] = 1;
            held++;
        }
    }
done:
    printf("shmpress: held %ld MiB, free low %ld MiB\n", held >> 8, free_low_frames() >> 8);
    fflush(stdout);
    if (fork() == 0) for (;;) pause();
    return 0;
}
