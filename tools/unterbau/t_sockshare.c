#define TNAME "sockshare"
#include "t.h"
#include <poll.h>
#include <signal.h>
#include <stdint.h>
#include <stdlib.h>
#include <sys/mman.h>
#include <sys/socket.h>
#include <sys/wait.h>

#define ROUNDS 400
#define SHARERS 2
#define HUP_TIMEOUT_MS 1500
#define MAX_MISSES 4

static int peer_sees_hangup(int peer)
{
    struct pollfd p = { peer, POLLIN, 0 };
    char c;
    if (poll(&p, 1, HUP_TIMEOUT_MS) != 1)
        return 0;
    return read(peer, &c, 1) == 0;
}

static void sharer(int sock, int ready_wr, int go_rd, int explicit_close)
{
    char c = 'r';
    (void)!write(ready_wr, &c, 1);
    (void)!read(go_rd, &c, 1);
    if (explicit_close)
        close(sock);
    _exit(0);
}

static void wait_ready(int ready_rd)
{
    char c;
    for (int i = 0; i < SHARERS; i++)
        (void)!read(ready_rd, &c, 1);
}

static void release_sharers(int go_wr)
{
    char go[SHARERS] = { 'g', 'g' };
    (void)!write(go_wr, go, sizeof go);
}

static int run_round(int explicit_close)
{
    int sv[2], ready[2], go[2];
    pid_t kids[SHARERS];
    if (socketpair(AF_UNIX, SOCK_STREAM, 0, sv) != 0 || pipe(ready) != 0 || pipe(go) != 0)
        return -1;
    for (int i = 0; i < SHARERS; i++) {
        kids[i] = fork();
        if (kids[i] < 0)
            return -1;
        if (kids[i] == 0) {
            close(sv[1]);
            sharer(sv[0], ready[1], go[0], explicit_close && i == 0);
        }
    }
    close(sv[0]);
    wait_ready(ready[0]);
    release_sharers(go[1]);
    int seen = peer_sees_hangup(sv[1]);
    for (int i = 0; i < SHARERS; i++) {
        if (!seen)
            kill(kids[i], SIGKILL);
        waitpid(kids[i], NULL, 0);
    }
    close(sv[1]);
    close(ready[0]);
    close(ready[1]);
    close(go[0]);
    close(go[1]);
    return seen;
}

static void shared_end(const char *name, int explicit_close)
{
    int misses = 0, errors = 0, done = 0;
    for (int r = 0; r < ROUNDS && misses < MAX_MISSES && errors == 0; r++) {
        int rc = run_round(explicit_close);
        done++;
        if (rc < 0)
            errors++;
        else if (rc == 0)
            misses++;
    }
    CHECK(name, misses == 0 && errors == 0, "rounds=%d peer missed hangup %d times, errors %d", done, misses, errors);
}

int main(void)
{
    shared_end("shared_end_exit_hangup", 0);
    shared_end("shared_end_close_exit_hangup", 1);
    return 0;
}
