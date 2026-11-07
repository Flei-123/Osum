#define TNAME "pollmax"
#include "t.h"
#include <poll.h>
#include <stdlib.h>
#include <unistd.h>

#define PIPES 48
#define WOKEN 37

int main(void)
{
    struct pollfd p[PIPES];
    int wr[PIPES];
    int made = 0;
    for (int i = 0; i < PIPES; i++) {
        int f[2];
        if (pipe(f) < 0)
            break;
        p[i].fd = f[0];
        p[i].events = POLLIN;
        p[i].revents = 0;
        wr[i] = f[1];
        made++;
    }
    CHECK("pipes_made", made == PIPES, "made=%d", made);
    errno = 0;
    int idle = poll(p, made, 0);
    CHECK("idle_zero", idle == 0, "r=%d errno=%d nfds=%d", idle, errno, made);
    (void)!write(wr[WOKEN], "x", 1);
    errno = 0;
    int r = poll(p, made, 1000);
    int hit = -1;
    for (int i = 0; i < made; i++)
        if (p[i].revents & POLLIN)
            hit = i;
    CHECK("ready_found", r == 1 && hit == WOKEN, "r=%d hit=%d errno=%d", r, hit, errno);
    return 0;
}
