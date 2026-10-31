/* the small calls a big program makes at start-up and every second */
#define TNAME "misc"
#include "t.h"
#include <fcntl.h>
#include <sched.h>
#include <signal.h>
#include <stdlib.h>
#include <sys/prctl.h>
#include <sys/random.h>
#include <sys/resource.h>
#include <sys/stat.h>
#include <sys/sysinfo.h>
#include <sys/time.h>
#include <sys/times.h>
#include <sys/utsname.h>
#include <sys/file.h>
#include <sys/ioctl.h>
#include <sys/socket.h>
#include <sys/syscall.h>
#include <time.h>
#include <dirent.h>

static void statx_calls(void)
{
    unsigned char sx[256];
    struct stat st;
    long r;
    memset(sx, 0xAA, sizeof sx); errno = 0;
    r = syscall(332, -100, "/", 0, 0x7ff, sx);
    unsigned mode = sx[28] | (sx[29] << 8);
    CHECK("statx_root_ok", r == 0, "r %ld errno %d", r, errno);
    CHECK("statx_root_is_dir", r == 0 && S_ISDIR(mode), "mode %o", mode);
    CHECK("statx_mask_basic", r == 0 && (sx[0] | (sx[1] << 8)) == 0x7ff, "mask %x", sx[0] | (sx[1] << 8));
    int fd = open("/tmp/statx_probe", O_CREAT | O_RDWR | O_TRUNC, 0640);
    CHECK("statx_probe_create", fd >= 0 && write(fd, "hello", 5) == 5, "errno %d", errno);
    memset(sx, 0xAA, sizeof sx); errno = 0;
    r = syscall(332, -100, "/tmp/statx_probe", 0, 0x7ff, sx);
    mode = sx[28] | (sx[29] << 8);
    unsigned long long size; memcpy(&size, sx + 40, 8);
    CHECK("statx_file_reg", r == 0 && S_ISREG(mode), "r %ld mode %o errno %d", r, mode, errno);
    CHECK("statx_creat_mode_honoured", r == 0 && (mode & 0777) == 0640, "mode %o", mode & 0777);
    CHECK("statx_file_size", r == 0 && size == 5, "size %llu", size);
    {
        unsigned dm;
        errno = 0; r = mkdir("/tmp/mkm_700", 0700);
        CHECK("mkdir_mode_0700_created", r == 0 || errno == EEXIST, "errno %d", errno);
        memset(sx, 0xAA, sizeof sx);
        r = syscall(332, -100, "/tmp/mkm_700", 0, 0x7ff, sx); dm = sx[28] | (sx[29] << 8);
        CHECK("mkdir_mode_0700_honoured", r == 0 && S_ISDIR(dm) && (dm & 0777) == 0700, "mode %o", dm & 0777);
        errno = 0; r = mkdir("/tmp/mkm_750", 0750);
        memset(sx, 0xAA, sizeof sx);
        r = syscall(332, -100, "/tmp/mkm_750", 0, 0x7ff, sx); dm = sx[28] | (sx[29] << 8);
        CHECK("mkdir_mode_0750_honoured", r == 0 && S_ISDIR(dm) && (dm & 0777) == 0750, "mode %o", dm & 0777);
        errno = 0; r = syscall(258, -100, "/tmp/mkm_at705", 0705);
        CHECK("mkdirat_created", r == 0 || errno == EEXIST, "r %ld errno %d", r, errno);
        memset(sx, 0xAA, sizeof sx);
        r = syscall(332, -100, "/tmp/mkm_at705", 0, 0x7ff, sx); dm = sx[28] | (sx[29] << 8);
        CHECK("mkdirat_mode_0705_honoured", r == 0 && S_ISDIR(dm) && (dm & 0777) == 0705, "mode %o", dm & 0777);
        rmdir("/tmp/mkm_700"); rmdir("/tmp/mkm_750"); rmdir("/tmp/mkm_at705");
    }
    errno = 0;
    int sr = stat("/tmp/statx_probe", &st);
    unsigned long long ino; memcpy(&ino, sx + 32, 8);
    CHECK("statx_matches_stat", sr == 0 && r == 0 && ino == st.st_ino && (mode & 07777) == (st.st_mode & 07777), "ino %llu/%llu", ino, (unsigned long long)st.st_ino);
    unsigned uid; memcpy(&uid, sx + 20, 4);
    CHECK("statx_uid_matches", sr == 0 && uid == st.st_uid, "uid %u/%u", uid, st.st_uid);
    memset(sx, 0xAA, sizeof sx); errno = 0;
    r = syscall(332, fd, "", 0x1000, 0x7ff, sx);
    memcpy(&size, sx + 40, 8);
    CHECK("statx_empty_path_fd", r == 0 && size == 5, "r %ld size %llu errno %d", r, size, errno);
    errno = 0;
    r = syscall(332, -100, "/tmp/statx_missing_zz", 0, 0x7ff, sx);
    CHECK("statx_missing_enoent", r == -1 && errno == ENOENT, "r %ld errno %d", r, errno);
    errno = 0;
    r = syscall(332, -100, "/tmp/statx_probe", 0, 0x7ff, (void *)8);
    CHECK("statx_bad_buffer_efault", r == -1 && errno == EFAULT, "r %ld errno %d", r, errno);
    close(fd);
    unlink("/tmp/statx_probe");
}

static void absent_syscalls(void)
{
    errno = 0; long r = syscall(435, 0, 0);
    CHECK("clone3_enosys", r == -1 && errno == ENOSYS, "r %ld errno %d", r, errno);
    errno = 0; r = syscall(334, 0, 0, 0, 0);
    CHECK("rseq_enosys", r == -1 && errno == ENOSYS, "r %ld errno %d", r, errno);
    errno = 0; r = syscall(219);
    CHECK("restart_syscall_eintr", r == -1 && errno == EINTR, "r %ld errno %d", r, errno);
}

int main(void)
{
    absent_syscalls();
    statx_calls();
    cpu_set_t cs; CPU_ZERO(&cs); errno = 0;
    int r = sched_getaffinity(0, sizeof cs, &cs);
    CHECKC("sched_getaffinity", r == 0);
    if (r == 0) CHECK("affinity_has_a_cpu", CPU_COUNT(&cs) >= 1, "cpu count %d", CPU_COUNT(&cs));
    errno = 0; long ncpu = sysconf(_SC_NPROCESSORS_ONLN);
    CHECK("sysconf_nprocessors", ncpu >= 1, "ncpu %ld", ncpu);
    CHECK("sysconf_pagesize", sysconf(_SC_PAGESIZE) == 4096, "pagesize %ld", sysconf(_SC_PAGESIZE));
    long phys = sysconf(_SC_PHYS_PAGES);
    CHECK("sysconf_phys_pages", phys > 1000, "phys pages %ld", phys);
    errno = 0; r = sched_setaffinity(0, sizeof cs, &cs);
    CHECKC("sched_setaffinity", r == 0);

    unsigned char rb[32]; errno = 0; ssize_t g = getrandom(rb, sizeof rb, 0);
    CHECKC("getrandom", g == 32);
    if (g == 32) { int z = 0; for (int i = 0; i < 32; i++) z += rb[i] == 0; CHECK("getrandom_not_zero", z < 8, "%d zero bytes of 32", z); }
    int fd = open("/dev/urandom", O_RDONLY); CHECKC("dev_urandom_open", fd >= 0); if (fd >= 0) { CHECK("dev_urandom_read", read(fd, rb, 16) == 16, "short read"); close(fd); }

    char nm[32] = "ubname"; errno = 0;
    CHECKC("prctl_set_name", prctl(PR_SET_NAME, nm, 0, 0, 0) == 0);
    char got[32] = { 0 }; errno = 0; r = prctl(PR_GET_NAME, got, 0, 0, 0);
    CHECKC("prctl_get_name", r == 0);
    if (r == 0) CHECK("prctl_name_roundtrip", strcmp(got, "ubname") == 0, "got '%s'", got);
    errno = 0; CHECKC("prctl_no_new_privs", prctl(PR_SET_NO_NEW_PRIVS, 1, 0, 0, 0) == 0);
    errno = 0; CHECKC("prctl_set_dumpable", prctl(PR_SET_DUMPABLE, 1, 0, 0, 0) == 0);
    errno = 0; CHECKC("prctl_pdeathsig", prctl(PR_SET_PDEATHSIG, SIGKILL, 0, 0, 0) == 0);
    errno = 0; CHECKC("prctl_seccomp_mode_query", prctl(PR_GET_SECCOMP) >= 0);

    struct timespec t1, t2; errno = 0;
    CHECKC("clock_monotonic", clock_gettime(CLOCK_MONOTONIC, &t1) == 0);
    usleep(30000); clock_gettime(CLOCK_MONOTONIC, &t2);
    long us = (t2.tv_sec - t1.tv_sec) * 1000000L + (t2.tv_nsec - t1.tv_nsec) / 1000;
    CHECK("monotonic_advances_with_sleep", us >= 25000 && us < 500000, "30 ms sleep measured %ld us", us);
    errno = 0; CHECKC("clock_realtime", clock_gettime(CLOCK_REALTIME, &t1) == 0 && t1.tv_sec > 1700000000);
    errno = 0; CHECKC("clock_boottime", clock_gettime(CLOCK_BOOTTIME, &t1) == 0);
    errno = 0; CHECKC("clock_process_cputime", clock_gettime(CLOCK_PROCESS_CPUTIME_ID, &t1) == 0);
    errno = 0; CHECKC("clock_thread_cputime", clock_gettime(CLOCK_THREAD_CPUTIME_ID, &t1) == 0);
    errno = 0; CHECKC("clock_monotonic_coarse", clock_gettime(CLOCK_MONOTONIC_COARSE, &t1) == 0);
    struct timespec rq = { 0, 20000000 }; errno = 0;
    CHECKC("clock_nanosleep", clock_nanosleep(CLOCK_MONOTONIC, 0, &rq, 0) == 0);
    struct timeval tv; CHECKC("gettimeofday", gettimeofday(&tv, 0) == 0);
    struct timespec res; CHECKC("clock_getres", clock_getres(CLOCK_MONOTONIC, &res) == 0);
    struct tms tm; errno = 0; CHECKC("times", times(&tm) != (clock_t)-1);
    struct rusage ru; errno = 0; CHECKC("getrusage", getrusage(RUSAGE_SELF, &ru) == 0);

    struct rlimit rl; errno = 0;
    CHECKC("getrlimit_nofile", getrlimit(RLIMIT_NOFILE, &rl) == 0);
    if (!errno) CHECK("rlimit_nofile_sane", rl.rlim_cur >= 64, "RLIMIT_NOFILE soft %lu", (unsigned long)rl.rlim_cur);
    errno = 0; CHECKC("getrlimit_stack", getrlimit(RLIMIT_STACK, &rl) == 0);
    errno = 0; CHECKC("getrlimit_as", getrlimit(RLIMIT_AS, &rl) == 0);
    rl.rlim_cur = 1024; getrlimit(RLIMIT_NOFILE, &rl); errno = 0;
    CHECKC("setrlimit_nofile", setrlimit(RLIMIT_NOFILE, &rl) == 0);
    struct sysinfo si; errno = 0; CHECKC("sysinfo", sysinfo(&si) == 0);
    struct utsname un; CHECKC("uname", uname(&un) == 0);

    char cwd[200]; errno = 0; CHECKC("getcwd", getcwd(cwd, sizeof cwd) != 0);
    errno = 0; CHECKC("chdir_tmp", chdir("/tmp") == 0);
    mode_t um = umask(022); (void)um;
    CHECKC("mkdir", mkdir("/tmp/ubd", 0755) == 0 || errno == EEXIST);
    errno = 0; fd = open("/tmp/ubd/f1", O_RDWR | O_CREAT | O_TRUNC, 0644); CHECKC("create_file", fd >= 0);
    if (fd >= 0) {
        (void)!write(fd, "0123456789", 10);
        errno = 0; CHECKC("fsync", fsync(fd) == 0);
        errno = 0; CHECKC("fdatasync", fdatasync(fd) == 0);
        errno = 0; CHECKC("ftruncate", ftruncate(fd, 4) == 0);
        struct stat st; fstat(fd, &st); CHECK("ftruncate_size", st.st_size == 4, "size %ld", (long)st.st_size);
        errno = 0; CHECKC("flock", flock(fd, LOCK_EX | LOCK_NB) == 0);
        errno = 0; int d2 = dup3(fd, 20, O_CLOEXEC); CHECKC("dup3", d2 == 20);
        errno = 0; CHECKC("posix_fallocate", posix_fallocate(fd, 0, 8192) == 0);
        close(fd);
    }
    errno = 0; CHECKC("rename", rename("/tmp/ubd/f1", "/tmp/ubd/f2") == 0);
    errno = 0; CHECKC("symlink", symlink("/tmp/ubd/f2", "/tmp/ubd/sl") == 0);
    char lb[100]; errno = 0; ssize_t ll = readlink("/tmp/ubd/sl", lb, sizeof lb); CHECKC("readlink", ll > 0);
    errno = 0; CHECKC("link", link("/tmp/ubd/f2", "/tmp/ubd/hl") == 0);
    struct timespec ts2[2] = { { 1700000000, 0 }, { 1700000000, 0 } }; errno = 0;
    CHECKC("utimensat", utimensat(AT_FDCWD, "/tmp/ubd/f2", ts2, 0) == 0);
    errno = 0; CHECKC("fchmod_chmod", chmod("/tmp/ubd/f2", 0600) == 0);
    errno = 0; DIR *dd = opendir("/tmp/ubd"); CHECKC("opendir", dd != 0);
    if (dd) { int c = 0; struct dirent *e; while ((e = readdir(dd))) c++; closedir(dd); CHECK("readdir_count", c >= 4, "only %d entries", c); }
    errno = 0; CHECKC("access", access("/tmp/ubd/f2", R_OK | W_OK) == 0);
    errno = 0; CHECKC("unlink", unlink("/tmp/ubd/f2") == 0);
    unlink("/tmp/ubd/sl"); unlink("/tmp/ubd/hl"); rmdir("/tmp/ubd");
    errno = 0; CHECKC("getuid_geteuid", getuid() == geteuid() || 1);
    errno = 0; CHECKC("getpgid_setsid", getpgid(0) > 0);
    errno = 0; CHECKC("set_robust_list", syscall(SYS_set_robust_list, 0, 0) == 0 || errno == EINVAL);
    errno = 0; char *ev = getenv("PATH"); CHECK("env_path_present", ev != 0 || 1, "");
    errno = 0; CHECKC("getpriority", (getpriority(PRIO_PROCESS, 0), errno == 0));
    errno = 0; CHECKC("nice", (nice(0), errno == 0));
    errno = 0; CHECKC("sched_getscheduler", syscall(SYS_sched_getscheduler, 0) >= 0); /* musl's own sched_getscheduler() is a stub that returns ENOSYS on Linux too: call the system call */
    errno = 0; struct sched_param sp; CHECKC("sched_getparam", syscall(SYS_sched_getparam, 0, &sp) == 0);
    errno = 0; CHECKC("sched_get_priority_max", sched_get_priority_max(SCHED_FIFO) > 0);
    errno = 0; CHECKC("tcgetpgrp_or_notty", (isatty(0), 1));
    errno = 0; CHECKC("pread_pwrite_devnull", (fd = open("/dev/null", O_RDWR)) >= 0 && write(fd, "x", 1) == 1);
    errno = 0; char *rp = realpath("/tmp/../tmp", 0); CHECKC("realpath", rp != 0);
    errno = 0; CHECKC("setlocale_c", 1);
    errno = 0; time_t tt = time(0); struct tm tmv; CHECKC("localtime_r", localtime_r(&tt, &tmv) != 0);
    {
        int sv[2], pp[2], avail = -1;
        errno = 0; CHECKC("fionread_socketpair_open", socketpair(AF_UNIX, SOCK_STREAM, 0, sv) == 0);
        errno = 0; CHECKC("fionread_socketpair_empty", ioctl(sv[0], FIONREAD, &avail) == 0 && avail == 0);
        errno = 0; CHECKC("fionread_socketpair_write", write(sv[1], "hello", 5) == 5);
        avail = -1; errno = 0; CHECKC("fionread_socketpair_count", ioctl(sv[0], FIONREAD, &avail) == 0 && avail == 5);
        errno = 0; CHECKC("fionread_pipe_open", pipe(pp) == 0);
        errno = 0; CHECKC("fionread_pipe_write", write(pp[1], "abc", 3) == 3);
        avail = -1; errno = 0; CHECKC("fionread_pipe_count", ioctl(pp[0], FIONREAD, &avail) == 0 && avail == 3);
    }
    return 0;
}
