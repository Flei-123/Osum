/* Root files behind the VFS: private mmap of an image file and of a fresh file, ENOENT for create under a missing parent. */
#define TNAME "vfsroot"
#include "t.h"
#include <fcntl.h>
#include <sys/mman.h>
#include <sys/stat.h>

#define PG 4096
#define NP 32
#define PATH "/tmp/vfsroot.dat"

static unsigned char pat(long off)
{
    return (unsigned char)((off / PG) * 5 + (off % PG) % 241 + 1);
}

static int map_matches(const unsigned char *m, long limit)
{
    for (long off = 0; off < limit; off += 53)
        if (m[off] != pat(off)) return 0;
    return 1;
}

int main(void)
{
    int self = open("/bin/t_vfsroot", O_RDONLY);
    CHECKC("open_image_file", self >= 0);
    unsigned char *img = self >= 0 ? mmap(0, PG, PROT_READ, MAP_PRIVATE, self, 0) : MAP_FAILED;
    CHECKC("mmap_image_file", img != MAP_FAILED);
    CHECK("image_file_elf_magic", img != MAP_FAILED && img[0] == 0x7f && img[1] == 'E' && img[2] == 'L' && img[3] == 'F', "bad magic");

    int fd = open(PATH, O_RDWR | O_CREAT | O_TRUNC, 0600);
    CHECKC("create", fd >= 0);
    unsigned char page[PG];
    for (long p = 0; p < NP; p++) {
        for (long o = 0; o < PG; o++) page[o] = pat(p * PG + o);
        if (write(fd, page, PG) != PG) break;
    }
    unsigned char *m = mmap(0, NP * PG, PROT_READ, MAP_PRIVATE, fd, 0);
    CHECKC("mmap_new_file_lazy", m != MAP_FAILED);
    CHECK("new_file_content", m != MAP_FAILED && map_matches(m, NP * PG), "content differs");
    unsigned char *s = mmap(0, PG, PROT_READ | PROT_WRITE, MAP_PRIVATE, fd, 2 * PG);
    CHECKC("mmap_new_file_small", s != MAP_FAILED);
    CHECK("new_file_small_content", s != MAP_FAILED && s[0] == pat(2 * PG) && s[100] == pat(2 * PG + 100), "content differs");
    if (s != MAP_FAILED) s[0] ^= 0xff;
    CHECK("private_write_not_in_file", m != MAP_FAILED && m[2 * PG] == pat(2 * PG), "private write leaked");
    unlink(PATH);

    errno = 0;
    int r = mkdir("/tmp/vfsroot-absent/sub", 0700);
    CHECK("mkdir_missing_parent_enoent", r == -1 && errno == ENOENT, "r=%d errno=%d", r, errno);
    errno = 0;
    r = open("/tmp/vfsroot-absent/f", O_CREAT | O_WRONLY, 0600);
    CHECK("creat_missing_parent_enoent", r == -1 && errno == ENOENT, "r=%d errno=%d", r, errno);
    r = mkdir("/tmp/vfsroot-dir", 0700);
    CHECK("mkdir_then_child", r == 0 && mkdir("/tmp/vfsroot-dir/sub", 0700) == 0, "errno=%d", errno);
    rmdir("/tmp/vfsroot-dir/sub");
    rmdir("/tmp/vfsroot-dir");
    return 0;
}
