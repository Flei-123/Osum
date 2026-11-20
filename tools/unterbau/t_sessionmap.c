#define TNAME "sessionmap"
#include "t.h"
#include <fcntl.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mman.h>
#include <sys/wait.h>
#include <unistd.h>

#define BLOCK0 0x150000UL
#define BLOCK1 0x80000UL
#define TOTAL (BLOCK0 + BLOCK1)
#define MARK0 0x1000UL
#define MARK1 (BLOCK0 + 0x2000UL)
#define MAGIC0 0x11223344u
#define MAGIC1 0x55667788u

static void wait_byte(int fd)
{
    char c;
    (void)!read(fd, &c, 1);
}

static void send_byte(int fd)
{
    (void)!write(fd, "x", 1);
}

static int spawn_reader(int fd, unsigned long first, unsigned long len, unsigned long mark, unsigned magic, int ready[2], int go[2])
{
    pid_t pid = fork();
    if (pid != 0) return pid;
    volatile unsigned char *m = mmap(NULL, len, PROT_READ, MAP_SHARED, fd, first);
    if (m == MAP_FAILED) _exit(2);
    send_byte(ready[1]);
    wait_byte(go[0]);
    unsigned v = *(volatile unsigned *)(m + (mark - first));
    _exit(v == magic ? 0 : 3);
}

static int reader_status(pid_t pid)
{
    int st = 0;
    waitpid(pid, &st, 0);
    return WIFEXITED(st) ? WEXITSTATUS(st) : 99;
}

int main(void)
{
    char path[] = "/tmp/sessionmap.XXXXXX";
    int fd = mkstemp(path);
    CHECKC("create", fd >= 0);
    if (fd < 0) return 1;
    unlink(path);
    CHECK("size0", ftruncate(fd, BLOCK0) == 0, "errno=%d", errno);
    volatile unsigned char *b0 = mmap(NULL, BLOCK0, PROT_READ | PROT_WRITE, MAP_SHARED, fd, 0);
    CHECKC("server_block0", b0 != MAP_FAILED);
    CHECK("size1", ftruncate(fd, TOTAL) == 0, "errno=%d", errno);
    volatile unsigned char *b1 = mmap(NULL, BLOCK1, PROT_READ | PROT_WRITE, MAP_SHARED, fd, BLOCK0);
    CHECKC("server_block1", b1 != MAP_FAILED);
    if (b0 == MAP_FAILED || b1 == MAP_FAILED) return 1;

    int ready[2], go[2];
    pipe(ready);
    pipe(go);
    pid_t whole = spawn_reader(fd, 0, TOTAL, MARK0, MAGIC0, ready, go);
    wait_byte(ready[0]);
    *(volatile unsigned *)(b0 + MARK0) = MAGIC0;
    send_byte(go[1]);
    CHECK("whole_sees_block0_write", reader_status(whole) == 0, "status");

    pipe(ready);
    pipe(go);
    pid_t whole2 = spawn_reader(fd, 0, TOTAL, MARK1, MAGIC1, ready, go);
    wait_byte(ready[0]);
    *(volatile unsigned *)(b1 + (MARK1 - BLOCK0)) = MAGIC1;
    send_byte(go[1]);
    CHECK("whole_sees_block1_write", reader_status(whole2) == 0, "status");

    pipe(ready);
    pipe(go);
    pid_t tail = spawn_reader(fd, BLOCK0, BLOCK1, MARK1, MAGIC1, ready, go);
    wait_byte(ready[0]);
    send_byte(go[1]);
    CHECK("tail_sees_block1_value", reader_status(tail) == 0, "status");

    pipe(ready);
    pipe(go);
    pid_t first = spawn_reader(fd, 0, BLOCK0, MARK0, MAGIC0, ready, go);
    wait_byte(ready[0]);
    *(volatile unsigned *)(b0 + MARK0) = MAGIC0;
    send_byte(go[1]);
    CHECK("first_sees_block0_write", reader_status(first) == 0, "status");
    return 0;
}
