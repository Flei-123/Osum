/* the file operations git, sed -i and python do all day: temp file + rename over, 0444 create, vfork */
#define TNAME "fsops"
#include "t.h"
#include <fcntl.h>
#include <stdlib.h>
#include <sys/stat.h>
#include <sys/wait.h>

static int put(const char *p, const char *text)
{
    int fd = open(p, O_WRONLY | O_CREAT | O_TRUNC, 0644);
    if (fd < 0) return -1;
    int n = write(fd, text, strlen(text));
    close(fd);
    return n;
}
static int slurp(const char *p, char *buf, int cap)
{
    int fd = open(p, O_RDONLY);
    if (fd < 0) return -1;
    int n = read(fd, buf, cap - 1);
    close(fd);
    if (n >= 0) buf[n] = 0;
    return n;
}

int main(void)
{
    char b[128];
    mkdir("/tmp/fo", 0755);
    /* rename over an existing file replaces it (POSIX); sed -i / git / every temp+rename writer needs it */
    put("/tmp/fo/a", "new"); put("/tmp/fo/b", "old");
    errno = 0; int r = rename("/tmp/fo/a", "/tmp/fo/b");
    CHECKC("rename_over_file", r == 0);
    CHECK("rename_over_content", slurp("/tmp/fo/b", b, sizeof b) == 3 && !strcmp(b, "new"), "b=%s", b);
    CHECK("rename_over_source_gone", access("/tmp/fo/a", F_OK) != 0, "a still there");
    put("/tmp/fo/c", "x");
    errno = 0; r = link("/tmp/fo/c", "/tmp/fo/d");
    if (r == 0) { errno = 0; r = rename("/tmp/fo/c", "/tmp/fo/d"); CHECKC("rename_same_inode", r == 0); }
    mkdir("/tmp/fo/dir", 0755);
    errno = 0; r = rename("/tmp/fo/b", "/tmp/fo/dir");
    CHECK("rename_file_over_dir_refused", r != 0, "file replaced a directory");
    /* git's temp object: O_RDWR|O_CREAT|O_EXCL|O_CLOEXEC, mode 0444, then write, then rename */
    errno = 0; int fd = open("/tmp/fo/tmp_obj_X", O_RDWR | O_CREAT | O_EXCL | O_CLOEXEC, 0444);
    CHECKC("create_excl_0444", fd >= 0);
    if (fd >= 0) {
        errno = 0; CHECKC("write_0444_fd", write(fd, "0123456789", 10) == 10);
        errno = 0; CHECKC("fsync", fsync(fd) == 0);
        close(fd);
        errno = 0; CHECKC("rename_tmp_to_final", rename("/tmp/fo/tmp_obj_X", "/tmp/fo/obj") == 0);
    }
    mkdir("/tmp/fo/ab", 0777);
    errno = 0; fd = open("/tmp/fo/ab/tmp_obj_Y", O_RDWR | O_CREAT | O_EXCL, 0444);
    CHECKC("create_excl_0444_subdir", fd >= 0);
    if (fd >= 0) close(fd);
    errno = 0; fd = open("/tmp/fo/ab/tmp_obj_Z", O_WRONLY | O_CREAT | O_EXCL, 0600);
    CHECKC("create_excl_0600_subdir", fd >= 0);
    if (fd >= 0) { char big[8192]; memset(big, 'z', sizeof big); errno = 0; CHECKC("write_8k", write(fd, big, sizeof big) == (int)sizeof big); close(fd); }
    /* git runs in the work tree with relative paths and a hidden .git directory */
    mkdir("/tmp/fo/.git", 0755); mkdir("/tmp/fo/.git/objects", 0755);
    if (chdir("/tmp/fo") == 0) {
        errno = 0; fd = open(".git/objects/tmp_obj_AbCdEf", O_CREAT | O_EXCL | O_RDWR, 0444);
        CHECKC("create_relative_hidden_dir", fd >= 0);
        if (fd >= 0) close(fd);
        int made = 0;
        for (int i = 0; i < 40; i++) {
            char nm[64]; snprintf(nm, sizeof nm, ".git/objects/tmp_obj_%06d", i);
            fd = open(nm, O_CREAT | O_EXCL | O_RDWR, 0444);
            if (fd >= 0) { made++; close(fd); }
        }
        CHECK("create_40_in_one_dir", made == 40, "made %d, errno %d", made, errno);
    }
    /* git creates objects/xx/tmp_obj_X, expects ENOENT when xx is missing, then mkdir()s it and retries */
    errno = 0; fd = open("/tmp/fo/nodir/tmp_obj_X", O_CREAT | O_EXCL | O_RDWR, 0444);
    CHECK("create_in_missing_dir_enoent", fd < 0 && errno == ENOENT, "fd %d errno %d %s", fd, errno, strerror(errno));
    if (fd >= 0) close(fd);
    errno = 0; r = mkdir("/tmp/fo/.git/objects/45", 0777);
    CHECKC("mkdir_0777_hidden", r == 0);
    errno = 0; r = mkdir("/tmp/fo/.git/objects/45", 0777);
    CHECK("mkdir_twice_eexist", r != 0 && errno == EEXIST, "r %d errno %d %s", r, errno, strerror(errno));
    errno = 0; r = mkdir("/tmp/fo/nodir2/sub", 0777);
    CHECK("mkdir_in_missing_dir_enoent", r != 0 && errno == ENOENT, "r %d errno %d %s", r, errno, strerror(errno));
    /* vfork + exit/exec: musl vfork() is the vfork syscall; busybox xargs/timeout use it */
    pid_t p = vfork();
    if (p == 0) _exit(7);
    int st = 0;
    if (p > 0) { waitpid(p, &st, 0); CHECK("vfork_exit", WIFEXITED(st) && WEXITSTATUS(st) == 7, "status %d", st); }
    else { errno = errno ? errno : 0; CHECKC("vfork_exit", 0); }
    return 0;
}
