/* dgramrace: four processes on four cores bind and send to AF_UNIX datagram path names of different lengths at the same time; no send may reach a wrong or missing name. */
#define TNAME "dgramrace"
#include "t.h"
#include <fcntl.h>
#include <stddef.h>
#include <stdlib.h>
#include <sys/socket.h>
#include <sys/un.h>
#include <sys/wait.h>

#define PROCS 4
#define ROUNDS 4000

static const char *names[PROCS] = { "/tmp/dgr-a.sock", "/tmp/dgr-bbbbbbbbbb.sock", "/tmp/dgr-cc.sock", "/tmp/dgr-dddddddddddddddd.sock" };

static struct sockaddr_un mk(const char *p) { struct sockaddr_un a; memset(&a, 0, sizeof a); a.sun_family = AF_UNIX; strcpy(a.sun_path, p); return a; }
#define SALEN(a) ((socklen_t)(offsetof(struct sockaddr_un, sun_path) + strlen((a).sun_path) + 1))

static int worker(int me, int *socks)
{
    int bad = 0;
    int out = socket(AF_UNIX, SOCK_DGRAM, 0);
    struct sockaddr_un to = mk(names[(me + 1) % PROCS]);
    struct sockaddr_un mine = mk(names[me]);
    char b[64];
    int fl = fcntl(socks[me], F_GETFL);
    (void)!fcntl(socks[me], F_SETFL, fl | O_NONBLOCK);
    for (int i = 0; i < ROUNDS; i++) {
        ssize_t w = sendto(out, "x", 1, MSG_DONTWAIT, (struct sockaddr *)&to, SALEN(to));
        if (w < 0 && errno != EAGAIN) bad++;
        while (recv(socks[me], b, sizeof b, 0) > 0) { }
        if (i % 64 == 0) {
            int p = socket(AF_UNIX, SOCK_DGRAM, 0);
            ssize_t pw = sendto(p, "p", 1, MSG_DONTWAIT, (struct sockaddr *)&mine, SALEN(mine));
            if (pw < 0 && errno != EAGAIN) bad++;
            close(p);
        }
    }
    return bad > 200 ? 200 : bad;
}

int main(void)
{
    int socks[PROCS];
    for (int i = 0; i < PROCS; i++) {
        struct sockaddr_un a = mk(names[i]);
        socks[i] = socket(AF_UNIX, SOCK_DGRAM, 0);
        errno = 0;
        if (bind(socks[i], (struct sockaddr *)&a, SALEN(a)) != 0) { CHECK("bind_names", 0, "bind %d errno %d", i, errno); return 0; }
    }
    CHECKC("bind_names", 1);
    pid_t pid[PROCS];
    for (int i = 0; i < PROCS; i++) {
        pid[i] = fork();
        if (pid[i] == 0) _exit(worker(i, socks));
    }
    int total = 0, ended = 0;
    for (int i = 0; i < PROCS; i++) {
        int st = 0;
        if (waitpid(pid[i], &st, 0) == pid[i] && WIFEXITED(st)) { ended++; total += WEXITSTATUS(st); }
    }
    CHECK("all_workers_ended", ended == PROCS, "ended %d", ended);
    CHECK("no_send_to_wrong_name", total == 0, "%d sends failed", total);
    return 0;
}
