/* dgramname: AF_UNIX SOCK_DGRAM sockets bound to a path (r731): bind, sendto, connect+send, boundaries, poll, EADDRINUSE, ECONNREFUSED, close. */
#define TNAME "dgramname"
#include "t.h"
#include <fcntl.h>
#include <poll.h>
#include <stddef.h>
#include <stdlib.h>
#include <sys/socket.h>
#include <sys/un.h>

static struct sockaddr_un mk(const char *p) { struct sockaddr_un a; memset(&a, 0, sizeof a); a.sun_family = AF_UNIX; strcpy(a.sun_path, p); return a; }
#define SALEN(a) ((socklen_t)(offsetof(struct sockaddr_un, sun_path) + strlen((a).sun_path) + 1))

int main(void)
{
    struct sockaddr_un sa = mk("/tmp/dgn-server.sock");
    int srv = socket(AF_UNIX, SOCK_DGRAM, 0);
    CHECKC("socket", srv >= 0);
    if (srv < 0) return 0;
    errno = 0; CHECKC("bind", bind(srv, (struct sockaddr *)&sa, SALEN(sa)) == 0);
    int s2 = socket(AF_UNIX, SOCK_DGRAM, 0);
    errno = 0; CHECK("bind_in_use", bind(s2, (struct sockaddr *)&sa, SALEN(sa)) == -1 && errno == EADDRINUSE, "errno=%d", errno);
    /* sendto without bind of the sender */
    char b[64]; errno = 0;
    ssize_t w1 = sendto(s2, "one", 3, 0, (struct sockaddr *)&sa, SALEN(sa));
    ssize_t w2 = sendto(s2, "two22", 5, 0, (struct sockaddr *)&sa, SALEN(sa));
    CHECKC("sendto_path", w1 == 3 && w2 == 5);
    struct pollfd p = { srv, POLLIN, 0 };
    CHECK("poll_in", poll(&p, 1, 1000) == 1 && (p.revents & POLLIN), "revents 0x%x", p.revents);
    ssize_t r1 = recvfrom(srv, b, sizeof b, 0, 0, 0); int ok1 = r1 == 3 && !memcmp(b, "one", 3);
    ssize_t r2 = recvfrom(srv, b, sizeof b, 0, 0, 0); int ok2 = r2 == 5 && !memcmp(b, "two22", 5);
    CHECK("boundaries_and_order", ok1 && ok2, "got %zd %zd", r1, r2);
    /* empty + nonblocking: EAGAIN, not end of file */
    int fl = fcntl(srv, F_GETFL); (void)!fcntl(srv, F_SETFL, fl | O_NONBLOCK);
    errno = 0; ssize_t e = recv(srv, b, sizeof b, 0);
    CHECK("empty_eagain_not_eof", e == -1 && errno == EAGAIN, "ret %zd errno %d", e, errno);
    /* connect + send from a second client */
    int c = socket(AF_UNIX, SOCK_DGRAM, 0);
    errno = 0; CHECKC("connect", connect(c, (struct sockaddr *)&sa, SALEN(sa)) == 0);
    ssize_t cw = send(c, "via-connect", 11, 0);
    ssize_t cr = recv(srv, b, sizeof b, 0);
    CHECK("connected_send", cw == 11 && cr == 11 && !memcmp(b, "via-connect", 11), "sent %zd got %zd", cw, cr);
    /* a second sender does not disturb the first */
    sendto(s2, "from-s2", 7, 0, (struct sockaddr *)&sa, SALEN(sa)); send(c, "from-c", 6, 0);
    ssize_t q1 = recv(srv, b, sizeof b, 0); int g1 = q1 == 7 && !memcmp(b, "from-s2", 7);
    ssize_t q2 = recv(srv, b, sizeof b, 0); int g2 = q2 == 6 && !memcmp(b, "from-c", 6);
    CHECK("two_senders", g1 && g2, "got %zd %zd", q1, q2);
    /* nobody at that path */
    struct sockaddr_un none = mk("/tmp/dgn-nobody.sock");
    errno = 0; ssize_t nw = sendto(s2, "x", 1, 0, (struct sockaddr *)&none, SALEN(none));
    CHECK("sendto_nobody_econnrefused", nw == -1 && errno == ECONNREFUSED, "ret %zd errno %d", nw, errno);
    errno = 0; int cc = connect(s2, (struct sockaddr *)&none, SALEN(none));
    CHECK("connect_nobody_econnrefused", cc == -1 && errno == ECONNREFUSED, "ret %d errno %d", cc, errno);
    /* close the server: the connected client gets an error, the path can be bound again */
    close(srv);
    errno = 0; ssize_t dw = send(c, "late", 4, MSG_NOSIGNAL);
    CHECK("send_after_server_close_fails", dw == -1, "send returned %zd", dw);
    int srv2 = socket(AF_UNIX, SOCK_DGRAM, 0);
    errno = 0; CHECKC("rebind_after_close", bind(srv2, (struct sockaddr *)&sa, SALEN(sa)) == 0);
    sendto(s2, "again", 5, 0, (struct sockaddr *)&sa, SALEN(sa));
    ssize_t ar = recv(srv2, b, sizeof b, 0);
    CHECK("new_server_receives", ar == 5 && !memcmp(b, "again", 5), "got %zd", ar);
    /* stream sockets are not mixed up with it */
    int st = socket(AF_UNIX, SOCK_STREAM, 0);
    errno = 0; CHECK("stream_cannot_connect_to_dgram_name", connect(st, (struct sockaddr *)&sa, SALEN(sa)) == -1, "stream connect to a datagram name succeeded");
    /* boundaries with a big message */
    char big[1500], rb[1600]; memset(big, 'z', sizeof big);
    ssize_t bw = sendto(s2, big, sizeof big, 0, (struct sockaddr *)&sa, SALEN(sa));
    ssize_t br = recv(srv2, rb, sizeof rb, 0);
    CHECK("big_message", bw == (ssize_t)sizeof big && br == (ssize_t)sizeof big && !memcmp(big, rb, sizeof big), "sent %zd got %zd", bw, br);
    return 0;
}
