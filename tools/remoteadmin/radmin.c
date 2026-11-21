#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <sys/syscall.h>
#include <sys/wait.h>

#define SYS_OSUM_TIPP 1843
#define TI_INFO 0
#define TQ_ARMPID 1
#define TI_ARM 1
#define TI_DROP 2
#define TI_SCAN 6
#define TI_LOCK 7
#define TI_REMOTE 10

static long tipp(long what, long a, long b) { return syscall(SYS_OSUM_TIPP, what, a, b); }

static int run_self(long mode, long scan)
{
    long set = tipp(TI_REMOTE, getpid(), mode);
    long arm = tipp(TI_ARM, 0, 0);
    long armed_pid = tipp(TI_INFO, TQ_ARMPID, 0);
    long key = tipp(TI_SCAN, scan, 0);
    tipp(TI_DROP, 0, 0);
    printf("RA-SELF mode=%ld set=%ld arm=%ld scan=%ld pid=%ld armed_pid=%ld\n", mode, set, arm, key, (long)getpid(), armed_pid);
    return 0;
}

static int run_child(long mode, long scan)
{
    long set = tipp(TI_REMOTE, getpid(), mode);
    pid_t child = fork();
    if (child == 0) {
        long arm = tipp(TI_ARM, 0, 0);
        long key = tipp(TI_SCAN, scan, 0);
        tipp(TI_DROP, 0, 0);
        printf("RA-CHILD mode=%ld set=%ld arm=%ld scan=%ld\n", mode, set, arm, key);
        fflush(stdout);
        _exit(0);
    }
    int status = 0;
    waitpid(child, &status, 0);
    return 0;
}

static int run_lock(long mode, long scan)
{
    long set = tipp(TI_REMOTE, getpid(), mode);
    long arm = tipp(TI_ARM, 0, 0);
    long lock = tipp(TI_LOCK, 1, 0);
    long rearm = tipp(TI_ARM, 0, 0);
    long key = tipp(TI_SCAN, scan, 0);
    long unlock = tipp(TI_LOCK, 0, 0);
    tipp(TI_DROP, 0, 0);
    printf("RA-LOCK mode=%ld set=%ld arm=%ld lock=%ld rearm=%ld scan=%ld unlock=%ld\n", mode, set, arm, lock, rearm, key, unlock);
    return 0;
}

static int run_clear(void)
{
    long set = tipp(TI_REMOTE, 0, 0);
    printf("RA-CLEAR set=%ld\n", set);
    return 0;
}

static int run_mark(long mode)
{
    long set = tipp(TI_REMOTE, getpid(), mode);
    printf("RA-MARK mode=%ld set=%ld\n", mode, set);
    return 0;
}

static int run_nonroot(long uid)
{
    long drop = setuid((uid_t)uid);
    long set = tipp(TI_REMOTE, getpid(), 2);
    printf("RA-NONROOT uid=%ld setuid=%ld set=%ld\n", (long)getuid(), drop, set);
    return 0;
}

int main(int argc, char **argv)
{
    if (argc < 2) {
        fprintf(stderr, "usage: radmin self|child|lock <mode> <scan> | mark <mode> | clear | nonroot <uid>\n");
        return 2;
    }
    if (!strcmp(argv[1], "clear"))
        return run_clear();
    if (!strcmp(argv[1], "mark") && argc >= 3)
        return run_mark(atol(argv[2]));
    if (!strcmp(argv[1], "nonroot") && argc >= 3)
        return run_nonroot(atol(argv[2]));
    if (argc < 4)
        return 2;
    long mode = atol(argv[2]);
    long scan = atol(argv[3]);
    if (!strcmp(argv[1], "self"))
        return run_self(mode, scan);
    if (!strcmp(argv[1], "child"))
        return run_child(mode, scan);
    if (!strcmp(argv[1], "lock"))
        return run_lock(mode, scan);
    return 2;
}
