/* POSIX record locks belong to the PROCESS: a thread that exits must not drop them (Firefox profile lock, SQLite),
 * a child that exits must not touch the parent's locks, and close() of ANY descriptor of the file releases the process's locks on it. */
#define TNAME "poslock"
#include "t.h"
#include <fcntl.h>
#include <pthread.h>
#include <stdlib.h>
#include <sys/wait.h>

#define PATH "/tmp/poslock.dat"
#define THREAD_ROUNDS 20

static int lock_whole(int fd, short type)
{
    struct flock fl = {.l_type = type, .l_whence = SEEK_SET, .l_start = 0, .l_len = 0};
    return fcntl(fd, F_SETLK, &fl);
}

static int foreign_sees(short want)
{
    pid_t child = fork();
    if (child == 0) {
        int fd = open(PATH, O_RDWR);
        struct flock fl = {.l_type = F_WRLCK, .l_whence = SEEK_SET, .l_start = 0, .l_len = 0};
        int r = fcntl(fd, F_GETLK, &fl);
        _exit(r == 0 && fl.l_type == want ? 0 : 1);
    }
    int status = 0;
    waitpid(child, &status, 0);
    return WIFEXITED(status) && WEXITSTATUS(status) == 0;
}

static void *noop(void *arg)
{
    return arg;
}

static void churn_threads(int rounds)
{
    for (int i = 0; i < rounds; i++) {
        pthread_t th;
        pthread_create(&th, 0, noop, 0);
        pthread_join(th, 0);
    }
}

int main(void)
{
    int fd = open(PATH, O_RDWR | O_CREAT | O_TRUNC, 0644);
    CHECK("lock_taken", lock_whole(fd, F_WRLCK) == 0, "errno=%d", errno);
    CHECK("foreign_sees_lock", foreign_sees(F_WRLCK), "child saw no lock");
    churn_threads(1);
    CHECK("thread_exit_keeps_lock", foreign_sees(F_WRLCK), "lock gone after one thread exit");
    churn_threads(THREAD_ROUNDS);
    CHECK("many_thread_exits_keep_lock", foreign_sees(F_WRLCK), "lock gone after %d thread exits", THREAD_ROUNDS);
    pid_t child = fork();
    if (child == 0)
        _exit(0);
    waitpid(child, 0, 0);
    CHECK("child_exit_keeps_parent_lock", foreign_sees(F_WRLCK), "lock gone after a child exit");
    close(open(PATH, O_RDWR));
    CHECK("close_of_other_fd_releases_lock", foreign_sees(F_UNLCK), "lock survived close of a second descriptor");
    CHECK("relock", lock_whole(fd, F_WRLCK) == 0, "errno=%d", errno);
    close(dup(fd));
    CHECK("close_of_dup_releases_lock", foreign_sees(F_UNLCK), "lock survived close of a dup");
    CHECK("relock_again", lock_whole(fd, F_WRLCK) == 0, "errno=%d", errno);
    close(fd);
    CHECK("close_of_locked_fd_releases_lock", foreign_sees(F_UNLCK), "lock survived close of the locking descriptor");
    unlink(PATH);
    return 0;
}
