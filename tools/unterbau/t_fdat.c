/* r820/r821: fchdir, futimens, execveat with a directory descriptor, and *at calls with TWO DIFFERENT directory descriptors */
#define TNAME "fdat"
#include "t.h"
#include <fcntl.h>
#include <stdlib.h>
#include <sys/stat.h>
#include <sys/syscall.h>
#include <sys/wait.h>

static int put_at(int dfd, const char *p, const char *text)
{
    int fd = openat(dfd, p, O_WRONLY | O_CREAT | O_TRUNC, 0644);
    if (fd < 0) return -1;
    int n = write(fd, text, strlen(text));
    close(fd);
    return n;
}

int main(void)
{
    char b[256];
    struct stat st;
    int r;
    mkdir("/tmp/fa", 0755);
    mkdir("/tmp/fa/one", 0755);
    mkdir("/tmp/fa/two", 0755);
    int d1 = open("/tmp/fa/one", O_RDONLY | O_DIRECTORY);
    int d2 = open("/tmp/fa/two", O_RDONLY | O_DIRECTORY);
    CHECKC("open_dirs", d1 >= 0 && d2 >= 0);
    if (d1 < 0 || d2 < 0) return 0;
    put_at(d1, "f", "alpha");

    /* ---- r820: fchdir */
    errno = 0; r = fchdir(d1);
    CHECKC("fchdir_ok", r == 0);
    CHECK("fchdir_getcwd", getcwd(b, sizeof b) && !strcmp(b, "/tmp/fa/one"), "cwd '%s' errno %d", b, errno);
    CHECK("fchdir_relative_open", access("f", F_OK) == 0, "errno %d", errno);
    errno = 0; r = fchdir(d2);
    CHECKC("fchdir_second", r == 0);
    CHECK("fchdir_second_cwd", getcwd(b, sizeof b) && !strcmp(b, "/tmp/fa/two"), "cwd '%s'", b);
    CHECK("fchdir_second_relative", access("f", F_OK) != 0 && errno == ENOENT, "errno %d", errno);
    (void)!chdir("/");
    int d1b = dup(d1);
    errno = 0; r = fchdir(d1b);
    CHECK("fchdir_dup_fd", r == 0 && getcwd(b, sizeof b) && !strcmp(b, "/tmp/fa/one"), "r %d errno %d cwd '%s'", r, errno, b);
    close(d1b);
    CHECK("fchdir_dotdot", chdir("..") == 0 && getcwd(b, sizeof b) && !strcmp(b, "/tmp/fa"), "cwd '%s'", b);
    int ff = open("/tmp/fa/one/f", O_RDONLY);
    errno = 0;
    CHECK("fchdir_file_enotdir", fchdir(ff) < 0 && errno == ENOTDIR, "errno %d", errno);
    if (ff >= 0) close(ff);
    errno = 0;
    CHECK("fchdir_bad_fd_ebadf", fchdir(999) < 0 && errno == EBADF, "errno %d", errno);
    (void)!chdir("/");
    /* the descriptor survives a changed cwd, and the cwd after fchdir follows the descriptor's own directory */
    (void)!chdir("/tmp");
    CHECK("fchdir_after_chdir", fchdir(d2) == 0 && getcwd(b, sizeof b) && !strcmp(b, "/tmp/fa/two"), "cwd '%s'", b);
    (void)!chdir("/");

    /* ---- r820: futimens */
    struct timespec ts[2] = { { 2000000, 0 }, { 3000000, 0 } };
    int fd = open("/tmp/fa/one/f", O_RDWR);
    errno = 0; r = futimens(fd, ts);
    CHECKC("futimens_ok", r == 0);
    CHECK("futimens_applied", stat("/tmp/fa/one/f", &st) == 0 && st.st_atime == 2000000 && st.st_mtime == 3000000, "a %ld m %ld", (long)st.st_atime, (long)st.st_mtime);
    struct timespec om[2] = { { 0, UTIME_OMIT }, { 4000000, 0 } };
    errno = 0; r = futimens(fd, om);
    CHECK("futimens_omit_atime", r == 0 && stat("/tmp/fa/one/f", &st) == 0 && st.st_atime == 2000000 && st.st_mtime == 4000000, "r %d a %ld m %ld", r, (long)st.st_atime, (long)st.st_mtime);
    errno = 0; r = futimens(fd, NULL);
    CHECK("futimens_null_is_now", r == 0 && stat("/tmp/fa/one/f", &st) == 0 && st.st_mtime > 4000000, "r %d m %ld errno %d", r, (long)st.st_mtime, errno);
    errno = 0;
    CHECK("futimens_bad_fd_ebadf", futimens(999, ts) < 0 && errno == EBADF, "errno %d", errno);
    errno = 0; r = futimens(d1, ts);
    CHECK("futimens_dir_fd", r == 0 && stat("/tmp/fa/one", &st) == 0 && st.st_mtime == 3000000, "r %d m %ld errno %d", r, (long)st.st_mtime, errno);
    errno = 0; r = fchmod(fd, 0640);
    CHECK("fchmod_vfile", r == 0 && stat("/tmp/fa/one/f", &st) == 0 && (st.st_mode & 0777) == 0640, "r %d mode %o errno %d", r, st.st_mode & 0777, errno);
    errno = 0; r = fchown(fd, 1234, 4321);
    CHECK("fchown_vfile", r == 0 && stat("/tmp/fa/one/f", &st) == 0 && st.st_uid == 1234 && st.st_gid == 4321, "r %d uid %d gid %d errno %d", r, (int)st.st_uid, (int)st.st_gid, errno);
    errno = 0; r = fchown(fd, -1, 77);
    CHECK("fchown_keep_uid", r == 0 && stat("/tmp/fa/one/f", &st) == 0 && st.st_uid == 1234 && st.st_gid == 77, "r %d uid %d gid %d errno %d", r, (int)st.st_uid, (int)st.st_gid, errno);
    errno = 0; r = chown("/tmp/fa/one/f", 55, -1);
    CHECK("chown_path_uid", r == 0 && stat("/tmp/fa/one/f", &st) == 0 && st.st_uid == 55 && st.st_gid == 77, "r %d uid %d gid %d errno %d", r, (int)st.st_uid, (int)st.st_gid, errno);
    errno = 0; r = fchownat(AT_FDCWD, "/tmp/fa/one/f", 66, 88, 0);
    CHECK("fchownat_path", r == 0 && stat("/tmp/fa/one/f", &st) == 0 && st.st_uid == 66 && st.st_gid == 88, "r %d uid %d gid %d errno %d", r, (int)st.st_uid, (int)st.st_gid, errno);
    errno = 0; r = fchownat(d1, "f", 67, 89, 0);
    CHECK("fchownat_dirfd", r == 0 && stat("/tmp/fa/one/f", &st) == 0 && st.st_uid == 67 && st.st_gid == 89, "r %d uid %d gid %d errno %d", r, (int)st.st_uid, (int)st.st_gid, errno);
    errno = 0; r = chown("/tmp/fa/one", 11, 12);
    CHECK("chown_dir", r == 0 && stat("/tmp/fa/one", &st) == 0 && st.st_uid == 11 && st.st_gid == 12, "r %d uid %d gid %d errno %d", r, (int)st.st_uid, (int)st.st_gid, errno);
    (void)!symlink("f", "/tmp/fa/one/ln");
    errno = 0; r = lchown("/tmp/fa/one/ln", 21, 22);
    CHECK("lchown_link_itself", r == 0 && lstat("/tmp/fa/one/ln", &st) == 0 && st.st_uid == 21 && st.st_gid == 22, "r %d uid %d gid %d errno %d", r, (int)st.st_uid, (int)st.st_gid, errno);
    CHECK("lchown_target_untouched", stat("/tmp/fa/one/f", &st) == 0 && st.st_uid == 67 && st.st_gid == 89, "uid %d gid %d", (int)st.st_uid, (int)st.st_gid);
    errno = 0; r = fchownat(AT_FDCWD, "/tmp/fa/one/ln", 23, 24, AT_SYMLINK_NOFOLLOW);
    CHECK("fchownat_nofollow_link", r == 0 && lstat("/tmp/fa/one/ln", &st) == 0 && st.st_uid == 23 && st.st_gid == 24, "r %d uid %d gid %d errno %d", r, (int)st.st_uid, (int)st.st_gid, errno);
    errno = 0; r = chown("/tmp/fa/one/ln", 31, 32);
    CHECK("chown_follows_link", r == 0 && stat("/tmp/fa/one/f", &st) == 0 && st.st_uid == 31 && st.st_gid == 32 && lstat("/tmp/fa/one/ln", &st) == 0 && st.st_uid == 23, "r %d uid %d gid %d errno %d", r, (int)st.st_uid, (int)st.st_gid, errno);
    int dfd = open("/tmp/fa/one", O_RDONLY | O_DIRECTORY);
    errno = 0; r = fchown(dfd, 41, 42);
    CHECK("fchown_dir_fd", r == 0 && stat("/tmp/fa/one", &st) == 0 && st.st_uid == 41 && st.st_gid == 42, "r %d uid %d gid %d errno %d", r, (int)st.st_uid, (int)st.st_gid, errno);
    if (dfd >= 0) close(dfd);
    errno = 0; r = fchmod(d1, 0750);
    CHECK("fchmod_dir_fd", r == 0 && stat("/tmp/fa/one", &st) == 0 && (st.st_mode & 0777) == 0750, "r %d mode %o errno %d", r, st.st_mode & 0777, errno);
    errno = 0;
    CHECK("fchmod_bad_fd_ebadf", fchmod(999, 0600) < 0 && errno == EBADF, "errno %d", errno);
    if (fd >= 0) close(fd);

    /* ---- r820: execveat with a directory descriptor */
    {
        int bin = open("/bin", O_RDONLY | O_DIRECTORY);
        int po[2]; (void)!pipe(po);
        pid_t p = fork();
        if (p == 0) {
            dup2(po[1], 1); close(po[0]); close(po[1]);
            char *av[] = { "c_child", "one", "two", 0 }; char *ev[] = { "UB_X=envval", 0 };
            syscall(SYS_execveat, bin, "c_child", av, ev, 0);
            _exit(127);
        }
        close(po[1]);
        int n = read(po[0], b, sizeof b - 1); if (n < 0) n = 0; b[n] = 0; close(po[0]);
        int s = 0; waitpid(p, &s, 0);
        CHECK("execveat_rel_dirfd", !strcmp(b, "child argc=3 a1=one a2=two env=envval\n") && WIFEXITED(s) && WEXITSTATUS(s) == 42, "got '%s' status 0x%x", b, s);
        int po2[2]; (void)!pipe(po2);
        p = fork();
        if (p == 0) {
            dup2(po2[1], 1); close(po2[0]); close(po2[1]);
            char *av[] = { "c_child", "x", 0 }; char *ev[] = { 0 };
            syscall(SYS_execveat, -100 /* AT_FDCWD */, "/bin/c_child", av, ev, 0);
            _exit(127);
        }
        close(po2[1]);
        n = read(po2[0], b, sizeof b - 1); if (n < 0) n = 0; b[n] = 0; close(po2[0]);
        waitpid(p, &s, 0);
        CHECK("execveat_abs", WIFEXITED(s) && WEXITSTATUS(s) == 42 && strstr(b, "a1=x"), "got '%s' status 0x%x", b, s);
        p = fork();
        if (p == 0) {
            char *av[] = { "x", 0 }; char *ev[] = { 0 };
            syscall(SYS_execveat, bin, "no_such_program", av, ev, 0);
            _exit(errno == ENOENT ? 55 : 56);
        }
        waitpid(p, &s, 0);
        CHECK("execveat_missing_enoent", WIFEXITED(s) && WEXITSTATUS(s) == 55, "status 0x%x", s);
        p = fork();
        if (p == 0) {
            char *av[] = { "x", 0 }; char *ev[] = { 0 };
            syscall(SYS_execveat, 999, "c_child", av, ev, 0);
            _exit(errno == EBADF ? 55 : 56);
        }
        waitpid(p, &s, 0);
        CHECK("execveat_bad_fd_ebadf", WIFEXITED(s) && WEXITSTATUS(s) == 55, "status 0x%x", s);
        /* the base of the failed/successful call must not leak into the next relative call of the parent */
        CHECK("execveat_no_base_leak", access("f", F_OK) != 0 && errno == ENOENT, "errno %d", errno);
        close(bin);
    }

    /* ---- r821: two DIFFERENT directory descriptors in one call */
    errno = 0; r = renameat(d1, "f", d2, "g");
    CHECKC("renameat_two_dirfds", r == 0);
    CHECK("renameat_two_landed", access("/tmp/fa/two/g", F_OK) == 0 && access("/tmp/fa/one/f", F_OK) != 0, "errno %d", errno);
    errno = 0; r = linkat(d2, "g", d1, "h", 0);
    CHECKC("linkat_two_dirfds", r == 0);
    struct stat sg;
    CHECK("linkat_two_landed", stat("/tmp/fa/one/h", &st) == 0 && stat("/tmp/fa/two/g", &sg) == 0 && st.st_ino == sg.st_ino, "errno %d ino %lu vs %lu", errno, (unsigned long)st.st_ino, (unsigned long)sg.st_ino);
    /* a dirfd next to the cwd, both directions */
    (void)!chdir("/tmp/fa/two");
    errno = 0; r = renameat(d1, "h", AT_FDCWD, "i");
    CHECKC("renameat_dirfd_to_cwd", r == 0);
    CHECK("renameat_dirfd_to_cwd_landed", access("/tmp/fa/two/i", F_OK) == 0 && access("/tmp/fa/one/h", F_OK) != 0, "errno %d", errno);
    errno = 0; r = renameat(AT_FDCWD, "i", d1, "j");
    CHECKC("renameat_cwd_to_dirfd", r == 0);
    CHECK("renameat_cwd_to_dirfd_landed", access("/tmp/fa/one/j", F_OK) == 0 && access("/tmp/fa/two/i", F_OK) != 0, "errno %d", errno);
    errno = 0; r = linkat(AT_FDCWD, "g", d1, "k", 0);
    CHECKC("linkat_cwd_to_dirfd", r == 0 && access("/tmp/fa/one/k", F_OK) == 0);
    errno = 0; r = linkat(d1, "k", AT_FDCWD, "m", 0);
    CHECKC("linkat_dirfd_to_cwd", r == 0 && access("/tmp/fa/two/m", F_OK) == 0);
    /* the same directory twice, and a relative name next to an absolute one */
    errno = 0; r = renameat(d1, "j", d1, "j2");
    CHECKC("renameat_same_dirfd_twice", r == 0 && access("/tmp/fa/one/j2", F_OK) == 0);
    errno = 0; r = renameat(d2, "m", AT_FDCWD, "/tmp/fa/one/m2");
    CHECKC("renameat_rel_dirfd_to_abs", r == 0 && access("/tmp/fa/one/m2", F_OK) == 0);
    /* errors: a bad second descriptor, a file as the second descriptor */
    errno = 0; r = renameat(d1, "j2", 999, "x");
    CHECK("renameat_bad_second_fd_ebadf", r < 0 && errno == EBADF, "r %d errno %d", r, errno);
    int ffd = open("/tmp/fa/one/j2", O_RDONLY);
    errno = 0; r = linkat(d1, "j2", ffd, "x", 0);
    CHECK("linkat_file_second_fd_enotdir", r < 0 && errno == ENOTDIR, "r %d errno %d", r, errno);
    if (ffd >= 0) close(ffd);
    /* nothing leaks: a relative call right afterwards uses the cwd */
    CHECK("two_dirfds_no_base_leak", access("g", F_OK) == 0 && access("j2", F_OK) != 0, "errno %d", errno);
    (void)!chdir("/");
    close(d1);
    close(d2);
    return 0;
}
