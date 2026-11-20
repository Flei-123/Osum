#define TNAME "unixlisten"
#include "t.h"
#include <fcntl.h>
#include <poll.h>
#include <semaphore.h>
#include <sys/socket.h>
#include <sys/mman.h>
#include <sys/stat.h>
#include <time.h>
#include <sys/un.h>

static long now_ms(void)
{
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return ts.tv_sec * 1000 + ts.tv_nsec / 1000000;
}

static void make_addr(struct sockaddr_un *a, const char *path)
{
    memset(a, 0, sizeof *a);
    a->sun_family = AF_UNIX;
    strcpy(a->sun_path, path);
    unlink(path);
}

static int listener(int type, const char *path, int backlog)
{
    struct sockaddr_un a;
    make_addr(&a, path);
    int s = socket(AF_UNIX, type, 0);
    if (s < 0) return -1;
    if (bind(s, (struct sockaddr *)&a, sizeof a) != 0 || listen(s, backlog) != 0) {
        close(s);
        return -1;
    }
    return s;
}

static int dial(int type, const char *path, int flags)
{
    struct sockaddr_un a;
    memset(&a, 0, sizeof a);
    a.sun_family = AF_UNIX;
    strcpy(a.sun_path, path);
    int c = socket(AF_UNIX, type | flags, 0);
    if (c < 0) return -1;
    if (connect(c, (struct sockaddr *)&a, sizeof a) != 0) {
        int e = errno;
        close(c);
        errno = e;
        return -1;
    }
    return c;
}

static void seqpacket_roundtrip(void)
{
    const char *path = "/tmp/ul-seq";
    int l = listener(SOCK_SEQPACKET, path, 4);
    CHECKC("seq_listen", l >= 0);
    if (l < 0) return;
    int c = dial(SOCK_SEQPACKET, path, 0);
    CHECKC("seq_connect_before_accept", c >= 0);
    if (c < 0) return;
    CHECK("seq_client_send_before_accept", send(c, "ab", 2, 0) == 2 && send(c, "cdef", 4, 0) == 4, "errno=%d", errno);
    int a = accept(l, 0, 0);
    CHECKC("seq_accept", a >= 0);
    if (a < 0) return;
    char buf[64];
    int n1 = (int)recv(a, buf, sizeof buf, 0);
    CHECK("seq_boundary_1", n1 == 2 && memcmp(buf, "ab", 2) == 0, "n=%d", n1);
    int n2 = (int)recv(a, buf, sizeof buf, 0);
    CHECK("seq_boundary_2", n2 == 4 && memcmp(buf, "cdef", 4) == 0, "n=%d", n2);
    CHECK("seq_reply", send(a, "pong", 4, 0) == 4 && recv(c, buf, sizeof buf, 0) == 4 && memcmp(buf, "pong", 4) == 0, "errno=%d", errno);
    int t = 0;
    socklen_t tl = sizeof t;
    getsockopt(a, SOL_SOCKET, SO_TYPE, &t, &tl);
    CHECK("seq_accepted_type", t == SOCK_SEQPACKET, "type=%d", t);
    close(c);
    n1 = (int)recv(a, buf, sizeof buf, 0);
    CHECK("seq_eof_after_peer_close", n1 == 0, "n=%d errno=%d", n1, errno);
    close(a);
    close(l);
    unlink(path);
}

static void connect_does_not_wait(void)
{
    const char *path = "/tmp/ul-fast";
    int l = listener(SOCK_STREAM, path, 4);
    CHECKC("stream_listen", l >= 0);
    if (l < 0) return;
    long t0 = now_ms();
    int c = dial(SOCK_STREAM, path, 0);
    long dt = now_ms() - t0;
    CHECK("stream_connect_no_accept_needed", c >= 0 && dt < 500, "c=%d errno=%d dt=%ld", c, errno, dt);
    struct pollfd p = { l, POLLIN, 0 };
    CHECK("listener_pollin_when_pending", poll(&p, 1, 0) == 1 && (p.revents & POLLIN), "revents=%d", p.revents);
    CHECK("stream_data_before_accept", write(c, "xyz", 3) == 3, "errno=%d", errno);
    int a = accept(l, 0, 0);
    char buf[8];
    CHECK("stream_data_after_accept", a >= 0 && read(a, buf, sizeof buf) == 3 && memcmp(buf, "xyz", 3) == 0, "a=%d", a);
    struct pollfd p2 = { l, POLLIN, 0 };
    CHECK("listener_idle_after_accept", poll(&p2, 1, 0) == 0, "revents=%d", p2.revents);
    close(a);
    close(c);
    close(l);
    unlink(path);
}

static void backlog_full(void)
{
    const char *path = "/tmp/ul-full";
    int l = listener(SOCK_STREAM, path, 1);
    if (l < 0) {
        GAP("backlog_listen", "errno=%d", errno);
        return;
    }
    int cs[8];
    int ok = 0, first_err = 0;
    for (int i = 0; i < 8; i++) {
        cs[i] = dial(SOCK_STREAM, path, SOCK_NONBLOCK);
        if (cs[i] >= 0) ok++;
        else if (!first_err) first_err = errno;
    }
    CHECK("backlog_limits_pending", ok >= 1 && ok < 8, "ok=%d", ok);
    CHECK("backlog_full_is_eagain", first_err == EAGAIN, "errno=%d", first_err);
    int a = accept(l, 0, 0);
    CHECK("backlog_accept_frees_slot", a >= 0, "errno=%d", errno);
    int again = dial(SOCK_STREAM, path, SOCK_NONBLOCK);
    CHECK("backlog_slot_reusable", again >= 0, "errno=%d", errno);
    for (int i = 0; i < 8; i++) if (cs[i] >= 0) close(cs[i]);
    if (a >= 0) close(a);
    if (again >= 0) close(again);
    close(l);
    unlink(path);
}

static void nonblocking_accept(void)
{
    const char *path = "/tmp/ul-nb";
    struct sockaddr_un a;
    make_addr(&a, path);
    int l = socket(AF_UNIX, SOCK_STREAM | SOCK_NONBLOCK, 0);
    int fl = l >= 0 ? fcntl(l, F_GETFL) : 0;
    CHECK("socket_nonblock_flag_unix", l >= 0 && (fl & O_NONBLOCK), "fl=%d", fl);
    if (l < 0) return;
    bind(l, (struct sockaddr *)&a, sizeof a);
    listen(l, 2);
    long t0 = now_ms();
    int r = accept(l, 0, 0);
    CHECK("accept_nonblocking_listener_eagain", r < 0 && errno == EAGAIN && now_ms() - t0 < 500, "r=%d errno=%d", r, errno);
    int c = dial(SOCK_STREAM, path, 0);
    int acc = accept(l, 0, 0);
    CHECK("accept_after_connect", acc >= 0, "errno=%d", errno);
    if (c >= 0) close(c);
    if (acc >= 0) close(acc);
    close(l);
    unlink(path);
}

static void type_mismatch_and_close(void)
{
    const char *path = "/tmp/ul-mix";
    int l = listener(SOCK_SEQPACKET, path, 2);
    if (l < 0) {
        GAP("mix_listen", "errno=%d", errno);
        return;
    }
    int c = dial(SOCK_STREAM, path, 0);
    CHECK("stream_to_seqpacket_refused", c < 0 && (errno == EPROTOTYPE || errno == ECONNREFUSED), "c=%d errno=%d", c, errno);
    int d = dial(SOCK_DGRAM, path, 0);
    CHECK("dgram_to_seqpacket_refused", d < 0 && (errno == EPROTOTYPE || errno == ECONNREFUSED), "d=%d errno=%d", d, errno);
    int q = dial(SOCK_SEQPACKET, path, 0);
    char buf[8];
    close(l);
    int n = q >= 0 ? (int)recv(q, buf, sizeof buf, MSG_DONTWAIT) : -2;
    CHECK("listener_close_resets_pending", q >= 0 && (n == 0 || (n < 0 && errno == ECONNRESET)), "q=%d n=%d errno=%d", q, n, errno);
    if (q >= 0) close(q);
    unlink(path);
    int u = listener(SOCK_DGRAM, "/tmp/ul-dg", 1);
    CHECK("listen_on_dgram_rejected", u < 0 && errno == EOPNOTSUPP, "u=%d errno=%d", u, errno);
    if (u >= 0) close(u);
    unlink("/tmp/ul-dg");
}

static void connect_state_errors(void)
{
    const char *path = "/tmp/ul-st";
    int l = listener(SOCK_STREAM, path, 2);
    if (l < 0) {
        GAP("st_listen", "errno=%d", errno);
        return;
    }
    int c = dial(SOCK_STREAM, path, 0);
    struct sockaddr_un a;
    memset(&a, 0, sizeof a);
    a.sun_family = AF_UNIX;
    strcpy(a.sun_path, path);
    int r = c >= 0 ? connect(c, (struct sockaddr *)&a, sizeof a) : 0;
    CHECK("connect_twice_eisconn", c >= 0 && r == -1 && errno == EISCONN, "r=%d errno=%d", r, errno);
    int l2 = socket(AF_UNIX, SOCK_STREAM, 0);
    r = connect(l, (struct sockaddr *)&a, sizeof a);
    CHECK("connect_on_listener_einval", r == -1 && errno == EINVAL, "r=%d errno=%d", r, errno);
    if (l2 >= 0) close(l2);
    if (c >= 0) close(c);
    close(l);
    unlink(path);
}

static void many_sequential(void)
{
    const char *path = "/tmp/ul-many";
    int l = listener(SOCK_SEQPACKET, path, 8);
    if (l < 0) {
        GAP("many_listen", "errno=%d", errno);
        return;
    }
    int good = 0;
    for (int i = 0; i < 40; i++) {
        int c = dial(SOCK_SEQPACKET, path, 0);
        int a = c >= 0 ? accept(l, 0, 0) : -1;
        char buf[4];
        if (a >= 0 && send(c, "k", 1, 0) == 1 && recv(a, buf, sizeof buf, 0) == 1) good++;
        if (a >= 0) close(a);
        if (c >= 0) close(c);
    }
    CHECK("many_connect_accept_cycles_no_leak", good == 40, "good=%d", good);
    close(l);
    unlink(path);
}

static void shm_inodes(void)
{
    unlink("/dev/shm/ul-ino-a");
    unlink("/dev/shm/ul-ino-b");
    int a = open("/dev/shm/ul-ino-a", O_RDWR | O_CREAT | O_EXCL, 0600);
    int b = open("/dev/shm/ul-ino-b", O_RDWR | O_CREAT | O_EXCL, 0600);
    struct stat sa, sb, sp;
    int ra = a >= 0 ? fstat(a, &sa) : -1;
    int rb = b >= 0 ? fstat(b, &sb) : -1;
    CHECK("shm_fstat_ino_nonzero", ra == 0 && rb == 0 && sa.st_ino != 0 && sb.st_ino != 0, "a=%lu b=%lu", (unsigned long)sa.st_ino, (unsigned long)sb.st_ino);
    CHECK("shm_fstat_ino_distinct", ra == 0 && rb == 0 && sa.st_ino != sb.st_ino, "a=%lu b=%lu", (unsigned long)sa.st_ino, (unsigned long)sb.st_ino);
    CHECK("shm_stat_ino_matches_fstat", ra == 0 && stat("/dev/shm/ul-ino-a", &sp) == 0 && sp.st_ino == sa.st_ino, "stat=%lu fstat=%lu", (unsigned long)sp.st_ino, (unsigned long)sa.st_ino);
    if (a >= 0) close(a);
    if (b >= 0) close(b);
    unlink("/dev/shm/ul-ino-a");
    unlink("/dev/shm/ul-ino-b");
}

static void semaphore_create(void)
{
    sem_unlink("/ul-sem");
    sem_t *s = sem_open("/ul-sem", O_CREAT | O_EXCL, 0600, 1);
    CHECK("sem_open_creat", s != SEM_FAILED, "errno=%d", errno);
    if (s == SEM_FAILED) return;
    CHECK("sem_wait_post", sem_wait(s) == 0 && sem_post(s) == 0, "errno=%d", errno);
    sem_t *s2 = sem_open("/ul-sem", 0);
    CHECK("sem_open_existing", s2 != SEM_FAILED, "errno=%d", errno);
    sem_t *s3 = sem_open("/ul-sem", O_CREAT | O_EXCL, 0600, 1);
    CHECK("sem_open_excl_eexist", s3 == SEM_FAILED && errno == EEXIST, "errno=%d", errno);
    sem_close(s);
    CHECK("sem_unlink", sem_unlink("/ul-sem") == 0, "errno=%d", errno);
    sem_t *s4 = sem_open("/ul-sem", 0);
    CHECK("sem_open_after_unlink_enoent", s4 == SEM_FAILED && errno == ENOENT, "errno=%d", errno);
}

int main(void)
{
    seqpacket_roundtrip();
    connect_does_not_wait();
    backlog_full();
    nonblocking_accept();
    type_mismatch_and_close();
    connect_state_errors();
    many_sequential();
    shm_inodes();
    semaphore_create();
    return 0;
}
