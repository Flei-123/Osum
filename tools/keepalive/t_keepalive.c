/* SPDX-License-Identifier: GPL-2.0-only
 * tools/keepalive/t_keepalive.c -- roadmap N-006: SO_KEEPALIVE must do something.
 *
 * Runs in the guest (musl, dynamic). /etc/ka.conf holds "<mode> <echo-port>":
 *   ka      SO_KEEPALIVE + IDLE 2 s / INTVL 1 s / CNT 3 on an outgoing connection AND on a listener
 *           (the accepted connection must inherit it). After the host cuts the link both must die
 *           with ETIMEDOUT within about idle + cnt * intvl.
 *   nokeep  the counter-check: the same traffic without any option. After the cut nothing may die.
 * The host side (tools/keepalive/run.sh) answers "KA READY-CUT" by switching the QEMU link off.
 */
#define TNAME "ka"
#include "../unterbau/t.h"
#include <arpa/inet.h>
#include <netinet/in.h>
#include <netinet/tcp.h>
#include <poll.h>
#include <stdlib.h>
#include <sys/socket.h>

#define LPORT 7001
#define SLICE_MS 250

static int geti(int fd, int lvl, int opt)
{
    int v = -12345; socklen_t l = sizeof v;
    if (getsockopt(fd, lvl, opt, &v, &l) != 0) return -99999;
    return v;
}
static int seti(int fd, int lvl, int opt, int v)
{
    return setsockopt(fd, lvl, opt, &v, sizeof v);
}
static void say(const char *s) { (void)!write(1, s, strlen(s)); }

/* wait up to max_ms for an event on one of the two sockets; returns elapsed ms, or -1 if none. which: bit0 = a, bit1 = b */
static int wait_death(int a, int b, int max_ms, int *which)
{
    int waited = 0; *which = 0;
    struct pollfd p[2] = { { a, POLLIN, 0 }, { b, POLLIN, 0 } };
    while (waited < max_ms) {
        p[0].revents = p[1].revents = 0;
        int r = poll(p, 2, SLICE_MS);
        waited += SLICE_MS;
        if (r > 0) {
            if (p[0].revents) *which |= 1;
            if (p[1].revents) *which |= 2;
            if (*which == 3) return waited;
            /* give the other one a little time */
            p[0].fd = (*which & 1) ? -1 : a; p[1].fd = (*which & 2) ? -1 : b;
        }
    }
    return *which ? waited : -1;
}

int main(void)
{
    char conf[64] = { 0 }; char mode[16] = { 0 }; int eport = 0;
    FILE *f = fopen("/etc/ka.conf", "r");
    if (!f || !fgets(conf, sizeof conf, f) || sscanf(conf, "%15s %d", mode, &eport) != 2) { FAIL("conf", "cannot read /etc/ka.conf"); say("KA END\n"); return 1; }
    fclose(f);
    int keep = strcmp(mode, "nokeep") != 0;
    PASS("started");

    /* ---- 1. defaults, options, ranges */
    int s0 = socket(AF_INET, SOCK_STREAM, 0);
    CHECKC("socket", s0 >= 0);
    if (s0 < 0) { say("KA END\n"); return 1; }
    CHECK("opt_default", geti(s0, SOL_SOCKET, SO_KEEPALIVE) == 0 && geti(s0, IPPROTO_TCP, TCP_KEEPIDLE) == 7200
          && geti(s0, IPPROTO_TCP, TCP_KEEPINTVL) == 75 && geti(s0, IPPROTO_TCP, TCP_KEEPCNT) == 9,
          "ka=%d idle=%d intvl=%d cnt=%d", geti(s0, SOL_SOCKET, SO_KEEPALIVE), geti(s0, IPPROTO_TCP, TCP_KEEPIDLE),
          geti(s0, IPPROTO_TCP, TCP_KEEPINTVL), geti(s0, IPPROTO_TCP, TCP_KEEPCNT));
    errno = 0; int r1 = seti(s0, IPPROTO_TCP, TCP_KEEPIDLE, 0); int e1 = errno;
    errno = 0; int r2 = seti(s0, IPPROTO_TCP, TCP_KEEPINTVL, -5); int e2 = errno;
    errno = 0; int r3 = seti(s0, IPPROTO_TCP, TCP_KEEPCNT, 128); int e3 = errno;
    errno = 0; int r4 = seti(s0, IPPROTO_TCP, TCP_KEEPIDLE, 40000); int e4 = errno;
    CHECK("opt_range", r1 == -1 && e1 == EINVAL && r2 == -1 && e2 == EINVAL && r3 == -1 && e3 == EINVAL && r4 == -1 && e4 == EINVAL,
          "r=%d/%d/%d/%d errno=%d/%d/%d/%d", r1, r2, r3, r4, e1, e2, e3, e4);
    CHECK("opt_range_kept", geti(s0, IPPROTO_TCP, TCP_KEEPIDLE) == 7200 && geti(s0, IPPROTO_TCP, TCP_KEEPCNT) == 9, "a refused value changed the socket");
    errno = 0; int shortv = setsockopt(s0, SOL_SOCKET, SO_KEEPALIVE, "\1", 1);
    CHECK("opt_short", shortv == -1 && errno == EINVAL, "short optlen -> %d errno %d", shortv, errno);
    close(s0);

    /* ---- 2. the listener (options set before listen, as servers do) */
    int ls = socket(AF_INET, SOCK_STREAM, 0);
    struct sockaddr_in la = { .sin_family = AF_INET, .sin_port = htons(LPORT) };
    int ok = ls >= 0 && bind(ls, (struct sockaddr *)&la, sizeof la) == 0 && listen(ls, 2) == 0;
    CHECKC("listen", ok);
    if (keep) {
        int set = seti(ls, SOL_SOCKET, SO_KEEPALIVE, 1) | seti(ls, IPPROTO_TCP, TCP_KEEPIDLE, 2)
                | seti(ls, IPPROTO_TCP, TCP_KEEPINTVL, 1) | seti(ls, IPPROTO_TCP, TCP_KEEPCNT, 3);
        CHECK("opt_set_listener", set == 0, "setsockopt failed errno %d", errno);
    }

    /* ---- 3. outgoing connection, options set BEFORE connect */
    int cs = socket(AF_INET, SOCK_STREAM, 0);
    if (keep) {
        int set = seti(cs, SOL_SOCKET, SO_KEEPALIVE, 1) | seti(cs, IPPROTO_TCP, TCP_KEEPIDLE, 2)
                | seti(cs, IPPROTO_TCP, TCP_KEEPINTVL, 1) | seti(cs, IPPROTO_TCP, TCP_KEEPCNT, 3);
        CHECK("opt_set", set == 0, "setsockopt failed errno %d", errno);
        CHECK("opt_get", geti(cs, SOL_SOCKET, SO_KEEPALIVE) == 1 && geti(cs, IPPROTO_TCP, TCP_KEEPIDLE) == 2
              && geti(cs, IPPROTO_TCP, TCP_KEEPINTVL) == 1 && geti(cs, IPPROTO_TCP, TCP_KEEPCNT) == 3,
              "ka=%d idle=%d intvl=%d cnt=%d", geti(cs, SOL_SOCKET, SO_KEEPALIVE), geti(cs, IPPROTO_TCP, TCP_KEEPIDLE),
              geti(cs, IPPROTO_TCP, TCP_KEEPINTVL), geti(cs, IPPROTO_TCP, TCP_KEEPCNT));
    }
    struct sockaddr_in ea = { .sin_family = AF_INET, .sin_port = htons(eport) };
    inet_pton(AF_INET, "10.0.2.2", &ea.sin_addr);
    errno = 0; int cr = connect(cs, (struct sockaddr *)&ea, sizeof ea);
    CHECKC("connect", cr == 0);
    char b[8] = { 0 };
    int echo_ok = cr == 0 && write(cs, "hello", 5) == 5;
    if (echo_ok) { struct pollfd p = { cs, POLLIN, 0 }; echo_ok = poll(&p, 1, 5000) == 1 && read(cs, b, 5) == 5 && !memcmp(b, "hello", 5); }
    CHECK("echo", echo_ok, "no echo from the host server");
    if (!echo_ok) { say("KA END\n"); return 1; }

    /* ---- 4. the host connects to the listener through the port forward */
    say("KA LISTEN\n");
    struct pollfd lp = { ls, POLLIN, 0 };
    int as = -1;
    if (poll(&lp, 1, 20000) == 1) as = accept(ls, 0, 0);
    CHECK("accept", as >= 0, "no connection came through the port forward (errno %d)", errno);
    if (as < 0) { say("KA END\n"); return 1; }
    if (keep)
        CHECK("accept_inherit", geti(as, SOL_SOCKET, SO_KEEPALIVE) == 1 && geti(as, IPPROTO_TCP, TCP_KEEPIDLE) == 2
              && geti(as, IPPROTO_TCP, TCP_KEEPINTVL) == 1 && geti(as, IPPROTO_TCP, TCP_KEEPCNT) == 3,
              "accepted socket: ka=%d idle=%d intvl=%d cnt=%d", geti(as, SOL_SOCKET, SO_KEEPALIVE),
              geti(as, IPPROTO_TCP, TCP_KEEPIDLE), geti(as, IPPROTO_TCP, TCP_KEEPINTVL), geti(as, IPPROTO_TCP, TCP_KEEPCNT));
    else
        CHECK("accept_default", geti(as, SOL_SOCKET, SO_KEEPALIVE) == 0, "an accepted socket has keepalive without being asked");

    /* ---- 5. 7 s of silence with the link UP: probes are answered, nothing may break */
    for (int i = 0; i < 7000 / SLICE_MS; i++) poll(NULL, 0, SLICE_MS);
    struct pollfd both[2] = { { cs, POLLIN, 0 }, { as, POLLIN, 0 } };
    int quiet = poll(both, 2, 0);
    CHECK("quiet_link_up", quiet == 0, "an event on an idle healthy connection: poll=%d rev=%x/%x", quiet, both[0].revents, both[1].revents);
    echo_ok = write(cs, "again", 5) == 5;
    if (echo_ok) { struct pollfd p = { cs, POLLIN, 0 }; echo_ok = poll(&p, 1, 5000) == 1 && read(cs, b, 5) == 5 && !memcmp(b, "again", 5); }
    CHECK("alive_after_idle", echo_ok, "the connection died while the peer was alive");
    CHECK("no_error_link_up", geti(cs, SOL_SOCKET, SO_ERROR) == 0 && geti(as, SOL_SOCKET, SO_ERROR) == 0, "SO_ERROR set on a healthy connection");

    /* ---- 6. the host switches the link off; the peer is now gone as far as we can tell */
    say("KA READY-CUT\n");
    int which = 0;
    int ms = wait_death(cs, as, keep ? 20000 : 16000, &which);
    if (keep) {
        CHECK("dies_out", which == 3, "connections that died: mask %d (1 = outgoing, 2 = accepted) after %d ms", which, ms);
        CHECK("dies_in_time", ms > 0 && ms <= 12000, "took %d ms (expected about 3000-6000)", ms);
        CHECK("not_instant", ms >= 1500, "took only %d ms -- no waiting for the probes", ms);
        CHECK("error_out", geti(cs, SOL_SOCKET, SO_ERROR) == ETIMEDOUT, "SO_ERROR of the outgoing connection %d, want %d", geti(cs, SOL_SOCKET, SO_ERROR), ETIMEDOUT);
        CHECK("error_accepted", geti(as, SOL_SOCKET, SO_ERROR) == ETIMEDOUT, "SO_ERROR of the accepted connection %d, want %d", geti(as, SOL_SOCKET, SO_ERROR), ETIMEDOUT);
        char x[4]; errno = 0; int rr = read(cs, x, 4);
        CHECK("read_fails", rr <= 0, "read on a dead connection returned %d", rr);
    } else {
        CHECK("nokeep_stays_open", which == 0, "a connection without keepalive died on its own: mask %d after %d ms", which, ms);
        CHECK("nokeep_no_error", geti(cs, SOL_SOCKET, SO_ERROR) == 0 && geti(as, SOL_SOCKET, SO_ERROR) == 0, "SO_ERROR set without keepalive");
    }
    say("KA END\n");
    return 0;
}
