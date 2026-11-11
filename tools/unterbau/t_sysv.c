#define TNAME "sysv"
#include "t.h"
#include <stdint.h>
#include <sys/ipc.h>
#include <sys/msg.h>
#include <sys/sem.h>

struct msgbuf_x {
    long mtype;
    char text[32];
};

union semun_x {
    int val;
    unsigned short *array;
};

static void check_sem(void)
{
    errno = 0;
    int id = semget(IPC_PRIVATE, 2, IPC_CREAT | 0600);
    CHECKC("semget", id >= 0);
    if (id < 0)
        return;
    union semun_x u = {.val = 3};
    CHECKC("semctl_setval", semctl(id, 0, SETVAL, u) == 0);
    CHECK("semctl_getval", semctl(id, 0, GETVAL) == 3, "got %d", semctl(id, 0, GETVAL));
    struct sembuf dec = {0, -2, IPC_NOWAIT};
    CHECK("semop_dec", semop(id, &dec, 1) == 0 && semctl(id, 0, GETVAL) == 1, "val %d", semctl(id, 0, GETVAL));
    errno = 0;
    CHECK("semop_would_block", semop(id, &dec, 1) == -1 && errno == EAGAIN, "errno=%d", errno);
    struct sembuf both[2] = {{0, 1, 0}, {1, 1, 0}};
    CHECK("semop_two", semop(id, both, 2) == 0 && semctl(id, 0, GETVAL) == 2 && semctl(id, 1, GETVAL) == 1, "vals");
    unsigned short all[2] = {0, 0};
    union semun_x ua = {.array = all};
    CHECK("semctl_getall", semctl(id, 0, GETALL, ua) == 0 && all[0] == 2 && all[1] == 1, "all %d %d", all[0], all[1]);
    CHECK("semctl_rmid", semctl(id, 0, IPC_RMID) == 0, "errno=%d", errno);
    errno = 0;
    CHECK("sem_stale_id", semctl(id, 0, GETVAL) == -1 && errno == EINVAL, "errno=%d", errno);
    key_t k = 0x5eed0001;
    int a = semget(k, 1, IPC_CREAT | 0600);
    int b = semget(k, 1, 0);
    CHECK("semget_key_shared", a >= 0 && a == b, "a=%d b=%d", a, b);
    errno = 0;
    CHECK("semget_excl", semget(k, 1, IPC_CREAT | IPC_EXCL) == -1 && errno == EEXIST, "errno=%d", errno);
    semctl(a, 0, IPC_RMID);
}

static void check_msg(void)
{
    errno = 0;
    int id = msgget(IPC_PRIVATE, IPC_CREAT | 0600);
    CHECKC("msgget", id >= 0);
    if (id < 0)
        return;
    struct msgbuf_x s1 = {2, "second"}, s2 = {1, "first"}, r;
    CHECK("msgsnd1", msgsnd(id, &s1, 7, 0) == 0, "errno=%d", errno);
    CHECK("msgsnd2", msgsnd(id, &s2, 6, 0) == 0, "errno=%d", errno);
    long n = msgrcv(id, &r, sizeof r.text, 1, IPC_NOWAIT);
    CHECK("msgrcv_by_type", n == 6 && r.mtype == 1 && !strcmp(r.text, "first"), "n=%ld", n);
    n = msgrcv(id, &r, sizeof r.text, 0, IPC_NOWAIT);
    CHECK("msgrcv_fifo", n == 7 && r.mtype == 2 && !strcmp(r.text, "second"), "n=%ld", n);
    errno = 0;
    CHECK("msgrcv_empty", msgrcv(id, &r, sizeof r.text, 0, IPC_NOWAIT) == -1 && errno == ENOMSG, "errno=%d", errno);
    msgsnd(id, &s1, 7, 0);
    errno = 0;
    CHECK("msgrcv_2big", msgrcv(id, &r, 3, 0, IPC_NOWAIT) == -1 && errno == E2BIG, "errno=%d", errno);
    n = msgrcv(id, &r, 3, 0, IPC_NOWAIT | MSG_NOERROR);
    CHECK("msgrcv_noerror", n == 3, "n=%ld", n);
    CHECK("msgctl_rmid", msgctl(id, IPC_RMID, 0) == 0, "errno=%d", errno);
    errno = 0;
    CHECK("msg_stale_id", msgsnd(id, &s1, 7, IPC_NOWAIT) == -1 && errno == EINVAL, "errno=%d", errno);
}

int main(void)
{
    alarm(60);
    check_sem();
    check_msg();
    return 0;
}
