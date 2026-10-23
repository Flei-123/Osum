#define TNAME "scmfds"
#include "t.h"
#include <fcntl.h>
#include <stdint.h>
#include <sys/socket.h>

/* SCM_RIGHTS queue: many descriptors per message, several messages queued, all-or-nothing push,
 * MSG_CTRUNC, MSG_CMSG_CLOEXEC. Each passed descriptor is the read end of a pipe holding one id byte. */

#define MAXF 32

static int send_fds(int sk, const int *fds, int n, int flags)
{
    char data = 'x';
    struct iovec iov = { &data, 1 };
    union { struct cmsghdr h; char b[CMSG_SPACE(sizeof(int) * MAXF)]; } u;
    memset(&u, 0, sizeof u);
    struct msghdr m;
    memset(&m, 0, sizeof m);
    m.msg_iov = &iov;
    m.msg_iovlen = 1;
    m.msg_control = u.b;
    m.msg_controllen = CMSG_SPACE(sizeof(int) * n);
    struct cmsghdr *c = CMSG_FIRSTHDR(&m);
    c->cmsg_level = SOL_SOCKET;
    c->cmsg_type = SCM_RIGHTS;
    c->cmsg_len = CMSG_LEN(sizeof(int) * n);
    memcpy(CMSG_DATA(c), fds, sizeof(int) * n);
    return (int)sendmsg(sk, &m, flags);
}

/* returns number of descriptors received (or -1); *mflags gets msg_flags */
static int recv_fds(int sk, int *out, int room, int flags, int *mflags)
{
    char data[64];
    struct iovec iov = { data, sizeof data };
    union { struct cmsghdr h; char b[CMSG_SPACE(sizeof(int) * MAXF)]; } u;
    memset(&u, 0, sizeof u);
    struct msghdr m;
    memset(&m, 0, sizeof m);
    m.msg_iov = &iov;
    m.msg_iovlen = 1;
    m.msg_control = u.b;
    m.msg_controllen = CMSG_SPACE(sizeof(int) * room);
    if (recvmsg(sk, &m, flags) < 0) return -1;
    if (mflags) *mflags = m.msg_flags;
    int n = 0;
    for (struct cmsghdr *c = CMSG_FIRSTHDR(&m); c; c = CMSG_NXTHDR(&m, c)) {
        if (c->cmsg_level == SOL_SOCKET && c->cmsg_type == SCM_RIGHTS) {
            int k = (int)((c->cmsg_len - CMSG_LEN(0)) / sizeof(int));
            memcpy(out + n, CMSG_DATA(c), sizeof(int) * k);
            n += k;
        }
    }
    return n;
}

/* make k pipes; ids base..base+k-1; fills rd[] (read ends), closes write ends */
static int mkpipes(int *rd, int k, int base)
{
    for (int i = 0; i < k; i++) {
        int p[2];
        if (pipe(p) != 0) return -1;
        unsigned char id = (unsigned char)(base + i);
        if (write(p[1], &id, 1) != 1) return -1;
        close(p[1]);
        rd[i] = p[0];
    }
    return 0;
}

static int ids_ok(const int *fds, int k, int base)
{
    for (int i = 0; i < k; i++) {
        unsigned char id = 0;
        if (read(fds[i], &id, 1) != 1 || id != (unsigned char)(base + i)) return 0;
    }
    return 1;
}

static void closeall(const int *fds, int k)
{
    for (int i = 0; i < k; i++) close(fds[i]);
}

int main(void)
{
    int sv[2], src[MAXF], got[MAXF], mf = 0;
    if (socketpair(AF_UNIX, SOCK_STREAM, 0, sv) != 0) {
        GAP("socketpair", "errno=%d", errno);
        return 0;
    }

    /* 1. seven descriptors in one message (Firefox IPC sends up to 7+) */
    mkpipes(src, 7, 10);
    int r = send_fds(sv[0], src, 7, 0);
    CHECKC("send_7", r == 1, "r=%d", r);
    closeall(src, 7);
    int n = recv_fds(sv[1], got, 7, 0, &mf);
    CHECK("recv_7", n == 7 && ids_ok(got, 7, 10), "n=%d", n);
    closeall(got, n > 0 ? n : 0);

    /* 2. sixteen in one message */
    mkpipes(src, 16, 40);
    r = send_fds(sv[0], src, 16, 0);
    CHECKC("send_16", r == 1, "r=%d", r);
    closeall(src, 16);
    n = recv_fds(sv[1], got, 16, 0, &mf);
    CHECK("recv_16", n == 16 && ids_ok(got, 16, 40), "n=%d", n);
    closeall(got, n > 0 ? n : 0);

    /* 3. two messages with four descriptors each queued before the first recv */
    int a[4], b[4];
    mkpipes(a, 4, 70);
    mkpipes(b, 4, 80);
    int r1 = send_fds(sv[0], a, 4, MSG_DONTWAIT);
    int r2 = send_fds(sv[0], b, 4, MSG_DONTWAIT);
    CHECKC("queue_two_msgs", r1 == 1 && r2 == 1, "r1=%d r2=%d errno=%d", r1, r2, errno);
    closeall(a, 4);
    closeall(b, 4);
    n = recv_fds(sv[1], got, 8, 0, &mf);
    int okq = n == 8 && ids_ok(got, 4, 70) && ids_ok(got + 4, 4, 80);
    CHECK("queue_two_msgs_order", okq, "n=%d", n);
    closeall(got, n > 0 ? n : 0);

    /* 4. all-or-nothing: 15 queued, a 2-descriptor message must fail whole (EAGAIN), queue stays at 15 */
    int big[15], two[2];
    mkpipes(big, 15, 100);
    r = send_fds(sv[0], big, 15, MSG_DONTWAIT);
    CHECKC("fill_15", r == 1, "r=%d", r);
    closeall(big, 15);
    mkpipes(two, 2, 120);
    errno = 0;
    r = send_fds(sv[0], two, 2, MSG_DONTWAIT);
    CHECK("full_is_eagain", r < 0 && errno == EAGAIN, "r=%d errno=%d", r, errno);
    closeall(two, 2);
    n = recv_fds(sv[1], got, 16, 0, &mf);
    CHECK("atomic_no_partial", n == 15 && ids_ok(got, 15, 100), "n=%d (a partial push leaves extra descriptors)", n);
    closeall(got, n > 0 ? n : 0);

    /* 5. control buffer too small: MSG_CTRUNC, the rest stays queued for the next recvmsg */
    mkpipes(src, 4, 130);
    r = send_fds(sv[0], src, 4, 0);
    closeall(src, 4);
    char one = 'y';
    (void)!write(sv[0], &one, 1); /* more data so the second recv has something to read */
    n = recv_fds(sv[1], got, 2, 0, &mf);
    CHECK("small_ctl_ctrunc", n == 2 && (mf & MSG_CTRUNC) != 0, "n=%d flags=%d", n, mf);
    int ok1 = n == 2 && ids_ok(got, 2, 130);
    closeall(got, n > 0 ? n : 0);
    /* drain the leftover data of step 5 so the second recv blocks on fresh data only */
    (void)!write(sv[0], &one, 1);
    n = recv_fds(sv[1], got, 2, MSG_DONTWAIT, &mf);
    CHECK("small_ctl_rest", ok1 && n == 2 && ids_ok(got, 2, 132), "n=%d", n);
    closeall(got, n > 0 ? n : 0);
    char drain[64];
    while (recv(sv[1], drain, sizeof drain, MSG_DONTWAIT) > 0) {}

    /* 6. MSG_CMSG_CLOEXEC */
    mkpipes(src, 1, 150);
    r = send_fds(sv[0], src, 1, 0);
    close(src[0]);
    n = recv_fds(sv[1], got, 1, MSG_CMSG_CLOEXEC, &mf);
    int fl = n == 1 ? fcntl(got[0], F_GETFD) : -1;
    CHECK("cmsg_cloexec", n == 1 && fl >= 0 && (fl & FD_CLOEXEC), "n=%d fl=%d", n, fl);
    closeall(got, n > 0 ? n : 0);
    return 0;
}
