#define TNAME "loopboot"
#include "t.h"
#include <arpa/inet.h>
#include <netinet/in.h>
#include <sys/socket.h>
#include <sys/wait.h>

#define BASE_PORT 5750
#define WORKERS 4

static struct sockaddr_in port_addr(int index)
{
    struct sockaddr_in a;
    memset(&a, 0, sizeof a);
    a.sin_family = AF_INET;
    a.sin_port = htons(BASE_PORT + index);
    inet_pton(AF_INET, "127.0.0.1", &a.sin_addr);
    return a;
}

static int exchange(int listener, int index)
{
    struct sockaddr_in a = port_addr(index);
    int c = socket(AF_INET, SOCK_STREAM, 0);
    if (c < 0 || connect(c, (struct sockaddr *)&a, sizeof a) != 0) return 12;
    int s = accept(listener, 0, 0);
    if (s < 0) return 13;
    char b = 'a' + index;
    char got = 0;
    if (write(c, &b, 1) != 1 || read(s, &got, 1) != 1 || got != b) return 14;
    close(s);
    close(c);
    return 0;
}

static int worker(int index, int ready_fd, int turn_fd, int done_fd)
{
    struct sockaddr_in a = port_addr(index);
    int l = socket(AF_INET, SOCK_STREAM, 0);
    if (l < 0) return 10;
    if (bind(l, (struct sockaddr *)&a, sizeof a) != 0 || listen(l, 2) != 0) return 11;
    char b = 'r';
    if (write(ready_fd, &b, 1) != 1) return 15;
    if (read(turn_fd, &b, 1) != 1) return 16;
    int rc = exchange(l, index);
    char ok = rc == 0 ? 'o' : 'x';
    if (write(done_fd, &ok, 1) != 1) return 17;
    close(l);
    return rc;
}

int main(void)
{
    int gate[2], ready[2], done[2], turns[WORKERS][2];
    if (pipe(gate) != 0 || pipe(ready) != 0 || pipe(done) != 0) return 1;
    pid_t pids[WORKERS];
    for (int i = 0; i < WORKERS; i++)
        if (pipe(turns[i]) != 0) return 1;
    for (int i = 0; i < WORKERS; i++) {
        pids[i] = fork();
        if (pids[i] == 0) {
            char go;
            if (read(gate[0], &go, 1) < 0) _exit(9);
            _exit(worker(i, ready[1], turns[i][0], done[1]));
        }
    }
    for (int i = 0; i < WORKERS; i++)
        if (write(gate[1], "g", 1) != 1) break;
    int listening = 0;
    char b;
    for (int i = 0; i < WORKERS; i++)
        if (read(ready[0], &b, 1) == 1) listening++;
    int exchanged = 0;
    for (int i = 0; i < WORKERS; i++) {
        if (write(turns[i][1], "t", 1) != 1) continue;
        if (read(done[0], &b, 1) == 1 && b == 'o') exchanged++;
    }
    int clean = 0;
    int worst = 0;
    for (int i = 0; i < WORKERS; i++) {
        int status = 0;
        waitpid(pids[i], &status, 0);
        if (WIFEXITED(status) && WEXITSTATUS(status) == 0) clean++;
        else if (WIFEXITED(status)) worst = WEXITSTATUS(status);
        else worst = 99;
    }
    CHECK("first_socket_race_all_listening", listening == WORKERS, "listening=%d", listening);
    CHECK("first_socket_race_all_exchanged", exchanged == WORKERS, "exchanged=%d", exchanged);
    CHECK("first_socket_race_all_workers_clean", clean == WORKERS, "clean=%d worst=%d", clean, worst);
    return 0;
}
