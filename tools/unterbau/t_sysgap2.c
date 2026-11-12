#define TNAME "sysgap2"
#include "t.h"
#include <signal.h>
#include <stdlib.h>
#include <sys/syscall.h>
#include <sys/wait.h>

struct probe {
    const char *name;
    long nr;
};

static const struct probe probes[] = {
    {"poll", 7}, {"select", 23}, {"semop", 65}, {"semctl", 66}, {"shmdt", 67}, {"msgsnd", 69},
    {"msgrcv", 70}, {"msgctl", 71}, {"rt_sigtimedwait", 128}, {"personality", 135},
    {"sched_rr_get_interval", 148}, {"sync", 162}, {"settimeofday", 164}, {"mount", 165},
    {"umount2", 166}, {"sethostname", 170}, {"setdomainname", 171}, {"chroot", 161},
    {"lremovexattr", 198}, {"fremovexattr", 199}, {"futex", 202}, {"set_tid_address", 218},
    {"semtimedop", 220}, {"fadvise64", 221}, {"timer_getoverrun", 225}, {"clock_settime", 227},
    {"waitid", 247}, {"mq_open", 240}, {"mq_unlink", 241}, {"mq_timedsend", 242},
    {"mq_timedreceive", 243}, {"mq_notify", 244}, {"mq_getsetattr", 245}, {"add_key", 248},
    {"request_key", 249}, {"keyctl", 250}, {"ioprio_set", 251}, {"ioprio_get", 252},
    {"migrate_pages", 256}, {"pselect6", 270}, {"ppoll", 271}, {"unshare", 272},
    {"move_pages", 279}, {"fanotify_mark", 301}, {"setns", 308}, {"io_pgetevents", 333},
    {"io_setup", 206}, {"io_destroy", 207}, {"io_getevents", 208}, {"io_submit", 209},
    {"io_cancel", 210}, {"ioperm", 173}, {"iopl", 172}, {"adjtimex", 159}, {"clock_adjtime", 305},
    {"swapon", 167}, {"swapoff", 168}, {"acct", 163}, {"quotactl", 179}, {"setfsuid", 122},
    {"setfsgid", 123}, {"setreuid", 113}, {"setregid", 114}, {"setresuid", 117},
    {"setresgid", 119}, {"setgroups", 116}, {"setuid", 105}, {"setgid", 106}, {"setpgid", 109},
    {"setsid", 112}, {"setdomain", 171}, {"flock", 73}, {"timer_create", 222}, {"timerfd", 283},
    {"remap_file_pages", 216}, {"lookup_dcookie", 212}, {"epoll_wait_old", 215},
    {"modify_ldt", 154}, {"set_thread_area", 205}, {"get_thread_area", 211},
    {"getcpu", 309}, {"landlock_create_ruleset", 444}, {"landlock_add_rule", 445},
    {"landlock_restrict_self", 446}, {"mount_setattr", 442}, {"open_tree", 428}, {"move_mount", 429},
    {"fsopen", 430}, {"fsconfig", 431}, {"fsmount", 432}, {"fspick", 433}, {"cachestat", 451},
    {"futex_waitv", 449}, {"set_mempolicy_home_node", 450}, {"map_shadow_stack", 453},
    {"futex_wake", 454}, {"futex_wait", 455}, {"futex_requeue", 456}, {"statmount", 457},
    {"listmount", 458}, {"lsm_get_self_attr", 459}, {"quotactl_fd", 443}, {"rseq", 334},
    {"clone3", 435}, {"fsmount2", 432}, {"unused_getpmsg", 181}, {"sysfs", 139}, {"ustat", 136},
    {"uselib", 134}, {"_sysctl", 156}, {"vhangup", 153}, {"pivot_root", 155}, {"alarm", 37},
    {"getpriority", 140}, {"mq_open", 240},
};

#define ENOSYS_EXIT 77
#define PROBE_SECONDS 4

int main(void)
{
    alarm(120);
    size_t i;
    for (i = 0; i < sizeof probes / sizeof probes[0]; i++) {
        pid_t pid = fork();
        if (pid == 0) {
            alarm(PROBE_SECONDS);
            errno = 0;
            long r = syscall(probes[i].nr, -1L, 0L, 0L, 0L, 0L, 0L);
            _exit(r == -1 && errno == ENOSYS ? ENOSYS_EXIT : 0);
        }
        int status = 0;
        if (pid < 0 || waitpid(pid, &status, 0) != pid)
            FAIL(probes[i].name, "fork or wait failed");
        else if (WIFEXITED(status) && WEXITSTATUS(status) == ENOSYS_EXIT)
            GAP(probes[i].name, "nr=%ld", probes[i].nr);
        else if (WIFEXITED(status))
            PASS(probes[i].name);
        else
            FAIL(probes[i].name, "nr=%ld killed by signal %d", probes[i].nr, WTERMSIG(status));
    }
    return 0;
}
