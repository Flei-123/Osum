#define TNAME "sysgap"
#include "t.h"
#include <signal.h>
#include <stdlib.h>
#include <sys/syscall.h>

struct probe {
    const char *name;
    long nr;
};

static const struct probe probes[] = {
    {"read", 0}, {"pread64", 17}, {"pwrite64", 18}, {"readv", 19}, {"writev", 20},
    {"mincore", 27}, {"madvise", 28}, {"msync", 26}, {"dup3", 292}, {"pipe2", 293},
    {"nanosleep", 35}, {"getitimer", 36}, {"setitimer", 38}, {"sendfile", 40},
    {"socket", 41}, {"connect", 42}, {"accept", 43}, {"sendto", 44}, {"recvfrom", 45},
    {"sendmsg", 46}, {"recvmsg", 47}, {"bind", 49}, {"listen", 50}, {"getsockname", 51},
    {"getpeername", 52}, {"socketpair", 53}, {"setsockopt", 54}, {"getsockopt", 55},
    {"flock", 73}, {"fsync", 74}, {"fdatasync", 75}, {"truncate", 76}, {"ftruncate", 77},
    {"getdents", 78}, {"getcwd", 79}, {"fchdir", 81}, {"rename", 82}, {"link", 86},
    {"symlink", 88}, {"readlink", 89}, {"chmod", 90}, {"fchmod", 91}, {"chown", 92},
    {"fchown", 93}, {"lchown", 94}, {"getrlimit", 97}, {"getrusage", 98}, {"sysinfo", 99},
    {"times", 100}, {"ptrace", 101}, {"syslog", 103}, {"getgroups", 115}, {"getresuid", 118},
    {"getresgid", 120}, {"getpgid", 121}, {"getsid", 124}, {"capget", 125}, {"capset", 126},
    {"rt_sigpending", 127}, {"rt_sigqueueinfo", 129}, {"sigaltstack", 131}, {"utime", 132},
    {"mknod", 133}, {"statfs", 137}, {"fstatfs", 138}, {"getpriority", 140},
    {"setpriority", 141}, {"sched_setparam", 142}, {"sched_getparam", 143},
    {"sched_setscheduler", 144}, {"sched_getscheduler", 145}, {"sched_get_priority_max", 146},
    {"sched_get_priority_min", 147}, {"mlock", 149}, {"munlock", 150}, {"mlockall", 151},
    {"munlockall", 152}, {"prctl", 157}, {"arch_prctl", 158}, {"setrlimit", 160},
    {"gettid", 186}, {"readahead", 187}, {"setxattr", 188}, {"lsetxattr", 189},
    {"fsetxattr", 190}, {"getxattr", 191}, {"lgetxattr", 192}, {"fgetxattr", 193},
    {"listxattr", 194}, {"llistxattr", 195}, {"flistxattr", 196}, {"removexattr", 197},
    {"tkill", 200}, {"time", 201}, {"sched_setaffinity", 203}, {"sched_getaffinity", 204},
    {"epoll_create", 213}, {"getdents64", 217}, {"timer_create", 222},
    {"timer_settime", 223}, {"timer_gettime", 224}, {"timer_delete", 226},
    {"clock_gettime", 228}, {"clock_getres", 229},
    {"clock_nanosleep", 230}, {"epoll_wait", 232}, {"epoll_ctl", 233}, {"tgkill", 234},
    {"utimes", 235}, {"mbind", 237}, {"set_mempolicy", 238}, {"get_mempolicy", 239},
    {"inotify_init", 253}, {"inotify_add_watch", 254}, {"inotify_rm_watch", 255},
    {"openat", 257}, {"mkdirat", 258}, {"mknodat", 259}, {"fchownat", 260},
    {"futimesat", 261}, {"newfstatat", 262}, {"unlinkat", 263}, {"renameat", 264},
    {"linkat", 265}, {"symlinkat", 266}, {"readlinkat", 267}, {"fchmodat", 268},
    {"faccessat", 269}, {"set_robust_list", 273},
    {"get_robust_list", 274}, {"splice", 275}, {"tee", 276}, {"sync_file_range", 277},
    {"vmsplice", 278}, {"utimensat", 280}, {"epoll_pwait", 281}, {"signalfd", 282},
    {"timerfd_create", 283}, {"eventfd", 284}, {"fallocate", 285}, {"timerfd_settime", 286},
    {"timerfd_gettime", 287}, {"accept4", 288}, {"signalfd4", 289}, {"eventfd2", 290},
    {"epoll_create1", 291}, {"inotify_init1", 294}, {"preadv", 295}, {"pwritev", 296},
    {"rt_tgsigqueueinfo", 297}, {"perf_event_open", 298}, {"recvmmsg", 299},
    {"fanotify_init", 300}, {"prlimit64", 302}, {"name_to_handle_at", 303},
    {"syncfs", 306}, {"sendmmsg", 307}, {"getcpu", 309},
    {"process_vm_readv", 310}, {"process_vm_writev", 311}, {"kcmp", 312},
    {"sched_setattr", 314}, {"sched_getattr", 315}, {"renameat2", 316}, {"seccomp", 317},
    {"getrandom", 318}, {"memfd_create", 319}, {"bpf", 321}, {"userfaultfd", 323},
    {"membarrier", 324}, {"mlock2", 325}, {"copy_file_range", 326}, {"preadv2", 327},
    {"pwritev2", 328}, {"pkey_mprotect", 329}, {"pkey_alloc", 330}, {"pkey_free", 331},
    {"statx", 332}, {"io_uring_setup", 425}, {"io_uring_enter", 426}, {"pidfd_send_signal", 424},
    {"pidfd_open", 434}, {"close_range", 436}, {"openat2", 437}, {"pidfd_getfd", 438},
    {"faccessat2", 439}, {"process_madvise", 440}, {"epoll_pwait2", 441},
    {"memfd_secret", 447}, {"fchmodat2", 452},
    {"shmget", 29}, {"shmat", 30}, {"shmctl", 31}, {"semget", 64}, {"msgget", 68},
    {"sched_yield", 24}, {"mremap", 25},
};

int main(void)
{
    alarm(60);
    size_t i;
    for (i = 0; i < sizeof probes / sizeof probes[0]; i++) {
        errno = 0;
        long r = syscall(probes[i].nr, -1L, 0L, 0L, 0L, 0L, 0L);
        if (r == -1 && errno == ENOSYS)
            GAP(probes[i].name, "nr=%ld", probes[i].nr);
        else
            PASS(probes[i].name);
    }
    return 0;
}
