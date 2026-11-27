#define TNAME "syswait"
#include "t.h"
#include <fcntl.h>
#include <sys/wait.h>

#define SETTLE_US 300000
#define READ_NR 0
#define TEXT_MAX 2048

static int slurp(const char *path, char *buf, int cap)
{
    int fd = open(path, O_RDONLY);
    if (fd < 0)
        return -1;
    int n = read(fd, buf, cap - 1);
    close(fd);
    if (n < 0)
        return -1;
    buf[n] = 0;
    return n;
}

static pid_t blocked_reader(int *wr_end, int *rd_fd)
{
    int fds[2];
    if (pipe(fds) != 0)
        return -1;
    pid_t pid = fork();
    if (pid == 0) {
        char c;
        close(fds[1]);
        read(fds[0], &c, 1);
        _exit(0);
    }
    close(fds[0]);
    *wr_end = fds[1];
    *rd_fd = fds[0];
    return pid;
}

int main(int argc, char **argv)
{
    if (argc > 1)
        return 0;
    int wr = -1, rd = -1;
    pid_t pid = blocked_reader(&wr, &rd);
    CHECK("fork", pid > 0, "fork failed");
    if (pid <= 0)
        return 0;
    usleep(SETTLE_US);
    char path[64], text[TEXT_MAX], want[32];
    snprintf(path, sizeof path, "/proc/%d/syscall", (int)pid);
    int n = slurp(path, text, sizeof text);
    snprintf(want, sizeof want, "%d %d ", READ_NR, rd);
    CHECK("syscall_file_names_read", n > 0 && strncmp(text, want, strlen(want)) == 0,
        "got '%s' want prefix '%s'", n > 0 ? text : "", want);
    snprintf(path, sizeof path, "/proc/%d/status", (int)pid);
    n = slurp(path, text, sizeof text);
    snprintf(want, sizeof want, "Syscall: %d %d ", READ_NR, rd);
    CHECK("status_line_names_read", n > 0 && strstr(text, want) != NULL, "status lacks '%s'", want);
    close(wr);
    int st = 0;
    waitpid(pid, &st, 0);
    return 0;
}
