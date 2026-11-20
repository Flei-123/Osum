#define TNAME "unixnode"
#include "t.h"
#include <fcntl.h>
#include <stdio.h>
#include <string.h>
#include <sys/socket.h>
#include <sys/stat.h>
#include <sys/un.h>
#include <sys/wait.h>
#include <unistd.h>

#define DIR "/tmp/unixnode.d"
#define MANY 40

static int bind_to(int fd, const char *path)
{
    struct sockaddr_un a;
    memset(&a, 0, sizeof a);
    a.sun_family = AF_UNIX;
    strncpy(a.sun_path, path, sizeof a.sun_path - 1);
    return bind(fd, (struct sockaddr *)&a, sizeof a);
}

static int connect_to(int fd, const char *path)
{
    struct sockaddr_un a;
    memset(&a, 0, sizeof a);
    a.sun_family = AF_UNIX;
    strncpy(a.sun_path, path, sizeof a.sun_path - 1);
    return connect(fd, (struct sockaddr *)&a, sizeof a);
}

static int connect_accepted(int listener, const char *path)
{
    pid_t child = fork();
    if (child == 0) {
        int c = socket(AF_UNIX, SOCK_STREAM, 0);
        int r = connect_to(c, path);
        _exit(r == 0 ? 0 : (errno & 0x7f));
    }
    int a = accept(listener, NULL, NULL);
    if (a >= 0) close(a);
    int status = 0;
    waitpid(child, &status, 0);
    errno = WEXITSTATUS(status);
    return WEXITSTATUS(status) == 0 ? 0 : -1;
}

static void check_node(void)
{
    struct stat st;
    int s = socket(AF_UNIX, SOCK_STREAM, 0);
    CHECK("bind_ok", bind_to(s, DIR "/a.sock") == 0, "errno=%d", errno);
    CHECKC("lstat_ok", lstat(DIR "/a.sock", &st) == 0);
    CHECK("lstat_is_socket", S_ISSOCK(st.st_mode), "mode=%o", st.st_mode);
    CHECK("stat_is_socket", stat(DIR "/a.sock", &st) == 0 && S_ISSOCK(st.st_mode), "mode=%o", st.st_mode);
    CHECKC("listen_ok", listen(s, 4) == 0);
    CHECK("connect_ok", connect_accepted(s, DIR "/a.sock") == 0, "errno=%d", errno);
    int d = socket(AF_UNIX, SOCK_STREAM, 0);
    errno = 0;
    CHECK("rebind_addrinuse", bind_to(d, DIR "/a.sock") != 0 && errno == EADDRINUSE, "errno=%d", errno);
    close(d);
    errno = 0;
    CHECK("open_enxio", open(DIR "/a.sock", O_RDONLY) < 0 && errno == ENXIO, "errno=%d", errno);
    close(s);
}

static void check_regular_file_busy(void)
{
    int f = open(DIR "/plain", O_CREAT | O_WRONLY, 0600);
    close(f);
    int s = socket(AF_UNIX, SOCK_STREAM, 0);
    errno = 0;
    CHECK("regular_file_addrinuse", bind_to(s, DIR "/plain") != 0 && errno == EADDRINUSE, "errno=%d", errno);
    close(s);
}

static void check_relative(void)
{
    struct stat st;
    CHECKC("chdir", chdir(DIR) == 0);
    int s = socket(AF_UNIX, SOCK_STREAM, 0);
    CHECK("relative_bind", bind_to(s, "rel.sock") == 0, "errno=%d", errno);
    CHECK("relative_node", lstat(DIR "/rel.sock", &st) == 0 && S_ISSOCK(st.st_mode), "errno=%d", errno);
    listen(s, 4);
    CHECK("relative_connect", connect_accepted(s, "rel.sock") == 0, "errno=%d", errno);
    CHECK("absolute_connect_same", connect_accepted(s, DIR "/rel.sock") == 0, "errno=%d", errno);
    close(s);
    chdir("/");
}

static void check_unlink(void)
{
    int s = socket(AF_UNIX, SOCK_STREAM, 0);
    bind_to(s, DIR "/gone.sock");
    listen(s, 4);
    CHECKC("unlink_ok", unlink(DIR "/gone.sock") == 0);
    int c = socket(AF_UNIX, SOCK_STREAM, 0);
    errno = 0;
    CHECK("connect_after_unlink_enoent", connect_to(c, DIR "/gone.sock") != 0 && errno == ENOENT, "errno=%d", errno);
    close(c);
    close(s);
    int missing = socket(AF_UNIX, SOCK_STREAM, 0);
    errno = 0;
    CHECK("bind_missing_dir_enoent", bind_to(missing, DIR "/nodir/x.sock") != 0 && errno == ENOENT, "errno=%d", errno);
    close(missing);
}

static void check_many(void)
{
    int fds[MANY];
    int ok = 0;
    char path[96];
    for (int i = 0; i < MANY; i++) {
        fds[i] = socket(AF_UNIX, SOCK_STREAM, 0);
        snprintf(path, sizeof path, DIR "/m%d.sock", i);
        if (bind_to(fds[i], path) == 0 && listen(fds[i], 1) == 0) ok++;
    }
    CHECK("many_names", ok == MANY, "bound=%d", ok);
    for (int i = 0; i < MANY; i++) close(fds[i]);
}

static void check_long_path(void)
{
    struct sockaddr_un a;
    memset(&a, 0, sizeof a);
    a.sun_family = AF_UNIX;
    snprintf(a.sun_path, sizeof a.sun_path, DIR "/%s", "0123456789012345678901234567890123456789012345678901234567890123456789012");
    int s = socket(AF_UNIX, SOCK_STREAM, 0);
    int r = bind(s, (struct sockaddr *)&a, sizeof a);
    CHECK("long_path_bind", r == 0 || errno == ENAMETOOLONG, "errno=%d", errno);
    close(s);
}

int main(void)
{
    mkdir(DIR, 0700);
    check_node();
    check_regular_file_busy();
    check_relative();
    check_unlink();
    check_many();
    check_long_path();
    return 0;
}
