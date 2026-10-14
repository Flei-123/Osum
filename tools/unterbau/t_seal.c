/* memfd F_SEAL_WRITE (K-07, r719): sealing must wait for writable mappings, and a sealed object can never be written again:
 *  - F_ADD_SEALS(F_SEAL_WRITE) with a writable shared mapping alive -> EBUSY; after munmap it works
 *  - a writable mmap after the seal -> EPERM; a read-only one works and sees the old content; mprotect(PROT_WRITE) on it fails
 *  - the writable-mapping count goes back on munmap and on a failed mmap; unknown seal bits -> EINVAL; F_SEAL_SEAL -> EPERM */
#define TNAME "seal"
#include "t.h"
#include <fcntl.h>
#include <stdint.h>
#include <sys/mman.h>
#include <sys/syscall.h>

#ifndef F_ADD_SEALS
#define F_ADD_SEALS 1033
#define F_GET_SEALS 1034
#endif
#define SEAL_SEAL 1
#define SEAL_SHRINK 2
#define SEAL_GROW 4
#define SEAL_WRITE 8

int main(void)
{
    int fd = (int)syscall(SYS_memfd_create, "seal", 2 /* MFD_ALLOW_SEALING */);
    CHECKC("memfd_create", fd >= 0);
    if (fd < 0) return 0;
    CHECKC("ftruncate", ftruncate(fd, 8192) == 0);

    unsigned char *w = mmap(0, 8192, PROT_READ | PROT_WRITE, MAP_SHARED, fd, 0);
    CHECKC("mmap_rw_before_seal", w != MAP_FAILED);
    if (w == MAP_FAILED) return 0;
    memset(w, 0x5A, 8192);

    errno = 0;
    int r = fcntl(fd, F_ADD_SEALS, SEAL_WRITE);
    CHECK("seal_write_busy_with_rw_mapping", r == -1 && errno == EBUSY, "r=%d errno=%d", r, errno);
    CHECK("seal_not_set_after_busy", (fcntl(fd, F_GET_SEALS) & SEAL_WRITE) == 0, "seals=%d", fcntl(fd, F_GET_SEALS));
    /* other seals are not held back by the writable mapping */
    r = fcntl(fd, F_ADD_SEALS, SEAL_SHRINK);
    CHECK("seal_shrink_ok_with_rw_mapping", r == 0 && (fcntl(fd, F_GET_SEALS) & SEAL_SHRINK), "r=%d errno=%d", r, errno);
    errno = 0;
    r = fcntl(fd, F_ADD_SEALS, 0x100);
    CHECK("seal_unknown_bit_einval", r == -1 && errno == EINVAL, "r=%d errno=%d", r, errno);

    /* a second writable mapping, then both go: the count must reach zero exactly */
    unsigned char *w2 = mmap(0, 4096, PROT_READ | PROT_WRITE, MAP_SHARED, fd, 0);
    CHECKC("mmap_rw_second", w2 != MAP_FAILED);
    munmap(w, 8192);
    errno = 0;
    r = fcntl(fd, F_ADD_SEALS, SEAL_WRITE);
    CHECK("seal_write_busy_with_one_left", r == -1 && errno == EBUSY, "r=%d errno=%d", r, errno);
    if (w2 != MAP_FAILED) munmap(w2, 4096);
    r = fcntl(fd, F_ADD_SEALS, SEAL_WRITE);
    CHECK("seal_write_ok_after_munmap", r == 0 && (fcntl(fd, F_GET_SEALS) & SEAL_WRITE), "r=%d errno=%d", r, errno);

    /* sealed: no writable mapping any more, a read-only one shows the content that was there at the seal */
    errno = 0;
    void *w3 = mmap(0, 4096, PROT_READ | PROT_WRITE, MAP_SHARED, fd, 0);
    CHECK("mmap_rw_after_seal_refused", w3 == MAP_FAILED && errno == EPERM, "p=%p errno=%d", w3, errno);
    unsigned char *ro = mmap(0, 8192, PROT_READ, MAP_SHARED, fd, 0);
    CHECK("mmap_ro_after_seal_ok", ro != MAP_FAILED, "errno=%d", errno);
    if (ro != MAP_FAILED) {
        CHECK("sealed_content_intact", ro[0] == 0x5A && ro[4095] == 0x5A && ro[8191] == 0x5A, "%02x %02x %02x", ro[0], ro[4095], ro[8191]);
        errno = 0;
        r = mprotect(ro, 4096, PROT_READ | PROT_WRITE);
        CHECK("mprotect_write_on_sealed_refused", r == -1, "r=%d", r);
        CHECK("sealed_content_intact_after_mprotect", ro[0] == 0x5A, "%02x", ro[0]);
        munmap(ro, 8192);
    }
    errno = 0;
    ssize_t wr = write(fd, "x", 1);
    CHECK("write_on_sealed_refused", wr == -1, "wr=%zd", wr);
    errno = 0;
    r = ftruncate(fd, 4096);
    CHECK("shrink_after_seal_refused", r == -1, "r=%d", r);

    /* F_SEAL_SEAL closes the door */
    r = fcntl(fd, F_ADD_SEALS, SEAL_SEAL);
    CHECK("seal_seal_ok", r == 0, "r=%d errno=%d", r, errno);
    errno = 0;
    r = fcntl(fd, F_ADD_SEALS, SEAL_GROW);
    CHECK("add_after_seal_seal_eperm", r == -1 && errno == EPERM, "r=%d errno=%d", r, errno);
    close(fd);

    /* a fresh object starts with no seals and no count (the slot of the first one may be reused) */
    int fd2 = (int)syscall(SYS_memfd_create, "seal2", 2);
    CHECKC("memfd_second", fd2 >= 0);
    if (fd2 >= 0) {
        ftruncate(fd2, 4096);
        CHECK("fresh_object_no_seals", fcntl(fd2, F_GET_SEALS) == 0, "seals=%d", fcntl(fd2, F_GET_SEALS));
        r = fcntl(fd2, F_ADD_SEALS, SEAL_WRITE);
        CHECK("fresh_object_seal_write_ok", r == 0, "r=%d errno=%d", r, errno);
        close(fd2);
    }

    /* the count survives a failed mapping: a too-large PROT_WRITE mmap must not leave a stale count behind */
    int fd3 = (int)syscall(SYS_memfd_create, "seal3", 2);
    if (fd3 >= 0) {
        ftruncate(fd3, 4096);
        void *bad = mmap(0, 1ul << 40, PROT_READ | PROT_WRITE, MAP_SHARED, fd3, 0);
        if (bad != MAP_FAILED) munmap(bad, 1ul << 40);
        r = fcntl(fd3, F_ADD_SEALS, SEAL_WRITE);
        CHECK("failed_mmap_leaves_no_count", r == 0, "r=%d errno=%d", r, errno);
        close(fd3);
    }
    return 0;
}
