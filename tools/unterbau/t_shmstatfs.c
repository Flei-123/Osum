#define TNAME "shmstatfs"
#include "t.h"
#include <fcntl.h>
#include <sys/mman.h>
#include <sys/statfs.h>

#define TMPFS_MAGIC 0x01021994
#define SHM_ROOT "/dev/shm"
#define SHM_FILE "/dev/shm/ss_probe"
#define SHM_MISSING "/dev/shm/ss_missing"

int main(void)
{
    struct statfs st;
    errno = 0;
    CHECK("root_is_tmpfs", statfs(SHM_ROOT, &st) == 0 && st.f_type == TMPFS_MAGIC, "errno=%d type=0x%lx", errno, (unsigned long)st.f_type);
    CHECK("root_has_blocks", st.f_blocks > 0 && st.f_bsize > 0, "blocks=%lu bsize=%ld", (unsigned long)st.f_blocks, (long)st.f_bsize);
    int fd = shm_open("/ss_probe", O_CREAT | O_RDWR, 0600);
    CHECKC("shm_open", fd >= 0);
    if (fd < 0) return 0;
    errno = 0;
    CHECK("file_is_tmpfs", statfs(SHM_FILE, &st) == 0 && st.f_type == TMPFS_MAGIC, "errno=%d type=0x%lx", errno, (unsigned long)st.f_type);
    errno = 0;
    CHECK("fd_is_tmpfs", fstatfs(fd, &st) == 0 && st.f_type == TMPFS_MAGIC, "errno=%d type=0x%lx", errno, (unsigned long)st.f_type);
    errno = 0;
    CHECK("missing_enoent", statfs(SHM_MISSING, &st) == -1 && errno == ENOENT, "errno=%d", errno);
    errno = 0;
    CHECK("tmp_not_tmpfs", statfs("/tmp", &st) == 0 && st.f_type != TMPFS_MAGIC, "errno=%d type=0x%lx", errno, (unsigned long)st.f_type);
    close(fd);
    shm_unlink("/ss_probe");
    return 0;
}
