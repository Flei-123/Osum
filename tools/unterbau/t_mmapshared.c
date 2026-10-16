/* mmap(MAP_SHARED, PROT_WRITE) of a regular file (LCSH, docs/LINUX-COMPAT-OPEN.md #5): shared pages per file, write-back by
 * msync / munmap / exit. This is what SQLite's -shm file and Firefox shared data files need. */
#define TNAME "mmapshared"
#include "t.h"
#include <fcntl.h>
#include <stdlib.h>
#include <sys/mman.h>
#include <sys/stat.h>
#include <sys/wait.h>

#define PG 4096
#define PATH "/tmp/fsh.dat"

static unsigned char at(const char *p, long off)
{
    unsigned char c = 0xEE;
    int fd = open(p, O_RDONLY);
    if (fd >= 0) { if (pread(fd, &c, 1, off) != 1) c = 0xEF; close(fd); }
    return c;
}

int main(void)
{
    unlink(PATH);
    int fd = open(PATH, O_RDWR | O_CREAT | O_TRUNC, 0644);
    if (fd < 0) { FAIL("setup", "open errno=%d", errno); return 0; }
    static unsigned char pat[3 * PG];
    for (int i = 0; i < (int)sizeof pat; i++) pat[i] = (unsigned char)(i * 7 + 3);
    if (write(fd, pat, sizeof pat) != (ssize_t)sizeof pat) { FAIL("setup", "write errno=%d", errno); return 0; }

    /* 1. a shared writable mapping of the file */
    unsigned char *m = mmap(0, 3 * PG, PROT_READ | PROT_WRITE, MAP_SHARED, fd, 0);
    CHECKC("map", m != MAP_FAILED);
    if (m == MAP_FAILED) return 0;
    CHECK("contents", memcmp(m, pat, sizeof pat) == 0, "mapping shows wrong bytes");

    /* 2. a store goes to the file at msync */
    m[10] = 55; m[PG + 20] = 66; m[2 * PG + 30] = 77;
    CHECK("msync_call", msync(m, 3 * PG, MS_SYNC) == 0, "errno=%d", errno);
    CHECK("msync_writeback", at(PATH, 10) == 55 && at(PATH, PG + 20) == 66 && at(PATH, 2 * PG + 30) == 77,
          "file has %d %d %d", at(PATH, 10), at(PATH, PG + 20), at(PATH, 2 * PG + 30));
    CHECK("untouched_bytes_kept", at(PATH, 11) == pat[11] && at(PATH, PG + 21) == pat[PG + 21], "bytes around a store changed");

    /* 3. a second mapping of the same file sees the stores at once (no msync in between) */
    unsigned char *m2 = mmap(0, 3 * PG, PROT_READ | PROT_WRITE, MAP_SHARED, fd, 0);
    CHECKC("second_map", m2 != MAP_FAILED);
    if (m2 != MAP_FAILED) {
        CHECK("second_sees_first", m2[10] == 55, "got %d", m2[10]);
        m2[100] = 11;
        CHECK("first_sees_second", m[100] == 11, "got %d", m[100]);
        CHECK("same_pages", m2 != m, "same address twice");
    }

    /* 4. a forked child: a mapping it makes itself is the same object; its end writes back */
    pid_t c = fork();
    if (c == 0) {
        int cfd = open(PATH, O_RDWR);
        unsigned char *cm = cfd < 0 ? MAP_FAILED : mmap(0, 3 * PG, PROT_READ | PROT_WRITE, MAP_SHARED, cfd, 0);
        if (cm == MAP_FAILED) _exit(2);
        if (cm[100] != 11) _exit(3);              /* sees the parent's store */
        cm[PG + 200] = 123;                       /* no msync, no munmap: the end of the process writes back */
        _exit(0);
    }
    int st = 0;
    waitpid(c, &st, 0);
    CHECK("child_ran", WIFEXITED(st) && WEXITSTATUS(st) == 0, "child status %d (2 = map, 3 = stale view)", WIFEXITED(st) ? WEXITSTATUS(st) : -1);
    CHECK("parent_sees_child", m[PG + 200] == 123, "got %d", m[PG + 200]);
    CHECK("exit_writeback", at(PATH, PG + 200) == 123, "file has %d", at(PATH, PG + 200));

    /* 5. munmap writes back, also while another mapping of the object lives on */
    if (m2 != MAP_FAILED) {
        m2[300] = 99;
        CHECK("munmap_call", munmap(m2, 3 * PG) == 0, "errno=%d", errno);
        CHECK("munmap_writeback", at(PATH, 300) == 99, "file has %d", at(PATH, 300));
        CHECK("other_mapping_lives", m[300] == 99 && m[10] == 55, "first mapping broken after the munmap of the second");
    }

    /* 6. the last munmap frees the object; a new mapping reads the file again */
    m[400] = 44;
    CHECK("munmap_last", munmap(m, 3 * PG) == 0, "errno=%d", errno);
    CHECK("last_writeback", at(PATH, 400) == 44, "file has %d", at(PATH, 400));
    m = mmap(0, 3 * PG, PROT_READ | PROT_WRITE, MAP_SHARED, fd, 0);
    CHECKC("remap", m != MAP_FAILED);
    if (m != MAP_FAILED) {
        CHECK("remap_contents", m[10] == 55 && m[300] == 99 && m[400] == 44 && m[PG + 200] == 123, "remapped bytes %d %d %d %d", m[10], m[300], m[400], m[PG + 200]);
        munmap(m, 3 * PG);
    }

    /* 7. a mapping at a file offset: file page 1, 2 pages */
    unsigned char *mo = mmap(0, 2 * PG, PROT_READ | PROT_WRITE, MAP_SHARED, fd, PG);
    CHECKC("offset_map", mo != MAP_FAILED);
    if (mo != MAP_FAILED) {
        CHECK("offset_contents", mo[5] == pat[PG + 5] && mo[PG + 5] == pat[2 * PG + 5], "offset mapping shows wrong bytes");
        mo[PG + 6] = 31;
        msync(mo, 2 * PG, MS_SYNC);
        CHECK("offset_writeback", at(PATH, 2 * PG + 6) == 31 && at(PATH, 6) == pat[6], "file has %d at page 2, %d at page 0", at(PATH, 2 * PG + 6), at(PATH, 6));
        munmap(mo, 2 * PG);
    }

    /* 8. the file does not grow by a store past its end, and the tail of the page reads zero */
    int fd2 = open("/tmp/fsh2.dat", O_RDWR | O_CREAT | O_TRUNC, 0644);
    if (fd2 >= 0) {
        (void)!write(fd2, pat, 5000);
        unsigned char *me = mmap(0, 2 * PG, PROT_READ | PROT_WRITE, MAP_SHARED, fd2, 0);
        CHECKC("short_file_map", me != MAP_FAILED);
        if (me != MAP_FAILED) {
            CHECK("short_tail_zero", me[5000] == 0 && me[PG + 100] == 0, "bytes past the end are not zero");
            me[6000] = 1; me[4999] = 9;
            msync(me, 2 * PG, MS_SYNC);
            struct stat sb;
            fstat(fd2, &sb);
            CHECK("short_size_kept", sb.st_size == 5000, "size is %ld", (long)sb.st_size);
            CHECK("short_inside_written", at("/tmp/fsh2.dat", 4999) == 9, "file has %d", at("/tmp/fsh2.dat", 4999));
            munmap(me, 2 * PG);
        }
        close(fd2);
        unlink("/tmp/fsh2.dat");
    }

    /* 9. rights: a file opened read-only cannot get a writable shared mapping (EACCES); a read-only shared mapping works */
    int rfd = open(PATH, O_RDONLY);
    if (rfd >= 0) {
        void *x = mmap(0, PG, PROT_READ | PROT_WRITE, MAP_SHARED, rfd, 0);
        CHECK("ro_fd_writable_refused", x == MAP_FAILED && errno == EACCES, "result %p errno=%d", x, errno);
        unsigned char *rm = mmap(0, PG, PROT_READ, MAP_SHARED, rfd, 0);
        CHECKC("ro_shared_read", rm != MAP_FAILED);
        if (rm != MAP_FAILED) { CHECK("ro_shared_contents", rm[10] == 55, "got %d", rm[10]); munmap(rm, PG); }
        close(rfd);
    }

    /* 10. the only mapper ends without munmap: the end of the process writes back */
    c = fork();
    if (c == 0) {
        int cfd = open(PATH, O_RDWR);
        unsigned char *cm = cfd < 0 ? MAP_FAILED : mmap(0, PG, PROT_READ | PROT_WRITE, MAP_SHARED, cfd, 0);
        if (cm == MAP_FAILED) _exit(2);
        cm[500] = 222;
        _exit(0);
    }
    waitpid(c, &st, 0);
    CHECK("only_mapper_exit_writeback", WIFEXITED(st) && WEXITSTATUS(st) == 0 && at(PATH, 500) == 222, "child status %d, file has %d", WIFEXITED(st) ? WEXITSTATUS(st) : -1, at(PATH, 500));

    /* 11. many map/unmap rounds do not leak the object table (16 paged objects) */
    int okrounds = 0;
    for (int r = 0; r < 40; r++) {
        unsigned char *x = mmap(0, PG, PROT_READ | PROT_WRITE, MAP_SHARED, fd, 0);
        if (x == MAP_FAILED) break;
        x[600] = (unsigned char)r;
        if (munmap(x, PG) != 0) break;
        if (at(PATH, 600) != (unsigned char)r) break;
        okrounds++;
    }
    CHECK("rounds_no_leak", okrounds == 40, "only %d of 40 rounds worked", okrounds);

    /* 12. what is NOT supported answers honestly: more than 1 MiB, MAP_FIXED */
    void *big = mmap(0, 2 * 1024 * 1024, PROT_READ | PROT_WRITE, MAP_SHARED, fd, 0);
    CHECK("too_big_refused", big == MAP_FAILED, "a 2 MiB shared file mapping was accepted");
    close(fd);
    unlink(PATH);
    return 0;
}
