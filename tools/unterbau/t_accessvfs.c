#define TNAME "accessvfs"
#include "t.h"
#include <fcntl.h>
#include <sys/stat.h>

static int exists(const char *path)
{
    return access(path, F_OK) == 0;
}

int main(void)
{
    CHECK("proc_file_exists", exists("/proc/self/mountinfo"), "errno=%d", errno);
    CHECK("proc_file_readable", access("/proc/self/mountinfo", R_OK) == 0, "errno=%d", errno);
    CHECK("proc_dir_exists", exists("/proc/self/ns"), "errno=%d", errno);
    CHECK("sys_dir_exists", exists("/sys/devices/system/cpu"), "errno=%d", errno);
    CHECK("sys_memory_exists", exists("/sys/devices/system/memory"), "errno=%d", errno);
    errno = 0;
    CHECK("proc_missing_enoent", access("/proc/self/nope", F_OK) != 0 && errno == ENOENT, "errno=%d", errno);
    errno = 0;
    CHECK("sys_missing_enoent", access("/sys/devices/system/nope", F_OK) != 0 && errno == ENOENT, "errno=%d", errno);
    int dir = open("/proc/self", O_RDONLY | O_DIRECTORY);
    CHECK("faccessat_relative_to_dirfd", dir >= 0 && faccessat(dir, "mountinfo", F_OK, 0) == 0, "errno=%d", errno);
    if (dir >= 0)
        close(dir);
    CHECK("ofs_path_still_works", exists("/tmp") && access("/tmp", W_OK) == 0, "errno=%d", errno);
    errno = 0;
    CHECK("ofs_missing_enoent", access("/tmp/accessvfs-missing", F_OK) != 0 && errno == ENOENT, "errno=%d", errno);
    return 0;
}
