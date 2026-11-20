#define TNAME "pipemany"
#include "t.h"
#include <fcntl.h>
#include <string.h>
#include <unistd.h>

#define WANTED_PIPES 240
#define PAYLOAD_LEN 16

static int fds[WANTED_PIPES][2];

static int open_all(void)
{
    int n = 0;
    while (n < WANTED_PIPES && pipe2(fds[n], O_CLOEXEC) == 0)
        n++;
    return n;
}

static int roundtrip_all(int n)
{
    int good = 0;
    for (int i = 0; i < n; i++) {
        char out[PAYLOAD_LEN], in[PAYLOAD_LEN];
        memset(out, 'a' + (i % 26), sizeof out);
        if (write(fds[i][1], out, sizeof out) != (ssize_t)sizeof out)
            continue;
        if (read(fds[i][0], in, sizeof in) == (ssize_t)sizeof in && memcmp(in, out, sizeof in) == 0)
            good++;
    }
    return good;
}

static void close_all(int n)
{
    for (int i = 0; i < n; i++) {
        close(fds[i][0]);
        close(fds[i][1]);
    }
}

int main(void)
{
    int n = open_all();
    CHECK("opens_many", n == WANTED_PIPES, "opened=%d", n);
    int good = roundtrip_all(n);
    CHECK("each_isolated", good == n, "good=%d of %d", good, n);
    close_all(n);
    int again = open_all();
    CHECK("reusable_after_close", again == WANTED_PIPES, "opened=%d", again);
    close_all(again);
    return 0;
}
