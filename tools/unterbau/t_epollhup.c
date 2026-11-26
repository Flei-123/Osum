#define TNAME "epollhup"
#include "t.h"
#include <fcntl.h>
#include <poll.h>
#include <pthread.h>
#include <stdint.h>
#include <stdlib.h>
#include <sys/epoll.h>
#include <sys/eventfd.h>
#include <sys/socket.h>
#include <sys/un.h>

#define POLL_ASK (POLLIN | POLLOUT | POLLRDHUP | POLLRDNORM | POLLWRNORM)
#define EPOLL_ASK (EPOLLIN | EPOLLOUT | EPOLLRDHUP)
#define EPOLL_VISIBLE (EPOLL_ASK | EPOLLERR | EPOLLHUP)
#define WRITABLE (POLLOUT | POLLWRNORM)
#define READABLE (POLLIN | POLLRDNORM)
#define EOF_BITS (READABLE | WRITABLE | POLLRDHUP | POLLHUP)
#define READ_SHUT_BITS (READABLE | WRITABLE | POLLRDHUP)
#define UNCONNECTED_BITS (WRITABLE | POLLHUP)
#define HUP_EVENTS (POLLIN | POLLHUP | POLLRDHUP)
#define NOT_CHECKED 0xFFFFFFFFu
#define WAIT_MS 2000
#define WAKE_ROUNDS 3000
#define HUP_ROUNDS 300
#define WAKE_WRITERS 3
#define TYPE_COUNT 3
#define DGRAM_INDEX 2

static const int sock_types[TYPE_COUNT] = { SOCK_STREAM, SOCK_SEQPACKET, SOCK_DGRAM };
static const char *const type_names[TYPE_COUNT] = { "stream", "seqpacket", "dgram" };

enum action { ACT_NONE, ACT_CLOSE, ACT_DATA_CLOSE, ACT_DATA_READ_CLOSE, ACT_SHUT_WR, ACT_SHUT_RD, ACT_SHUT_RDWR };

struct row {
    const char *name;
    enum action action;
    unsigned a_conn, a_dgram, b_conn, b_dgram;
};

static const struct row rows[] = {
    { "fresh", ACT_NONE, WRITABLE, WRITABLE, WRITABLE, WRITABLE },
    { "peer_closed", ACT_CLOSE, EOF_BITS, WRITABLE, NOT_CHECKED, NOT_CHECKED },
    { "data_close", ACT_DATA_CLOSE, EOF_BITS, READABLE | WRITABLE, NOT_CHECKED, NOT_CHECKED },
    { "data_read_close", ACT_DATA_READ_CLOSE, EOF_BITS, WRITABLE, NOT_CHECKED, NOT_CHECKED },
    { "shut_wr", ACT_SHUT_WR, READ_SHUT_BITS, WRITABLE, WRITABLE, WRITABLE },
    { "shut_rd", ACT_SHUT_RD, WRITABLE, WRITABLE, READ_SHUT_BITS, READ_SHUT_BITS },
    { "shut_rdwr", ACT_SHUT_RDWR, EOF_BITS, WRITABLE, EOF_BITS, EOF_BITS },
};

static void relax(void)
{
    __asm__ volatile("pause");
}

static void spin(unsigned n)
{
    for (volatile unsigned i = 0; i < n; i++)
        relax();
}

static unsigned poll_bits(int fd)
{
    struct pollfd p = { fd, POLL_ASK, 0 };
    if (poll(&p, 1, 0) != 1)
        return 0;
    return (unsigned)p.revents;
}

static unsigned epoll_bits(int fd)
{
    struct epoll_event ev = { .events = EPOLL_ASK, .data.fd = fd }, out;
    unsigned bits = 0;
    int ep = epoll_create1(0);
    if (ep < 0)
        return NOT_CHECKED;
    if (epoll_ctl(ep, EPOLL_CTL_ADD, fd, &ev) == 0 && epoll_wait(ep, &out, 1, 0) == 1)
        bits = out.events;
    close(ep);
    return bits;
}

static int side_matches(int fd, unsigned want, const char *side, char *why, size_t cap)
{
    if (want == NOT_CHECKED)
        return 1;
    unsigned got_poll = poll_bits(fd), got_epoll = epoll_bits(fd);
    if (got_poll == want && got_epoll == (want & EPOLL_VISIBLE))
        return 1;
    snprintf(why, cap, "%s: poll 0x%x epoll 0x%x, want 0x%x / 0x%x", side, got_poll, got_epoll, want, want & EPOLL_VISIBLE);
    return 0;
}

static void run_action(enum action act, int *a, int *b)
{
    char c = 'x';
    switch (act) {
    case ACT_CLOSE:
        close(*b);
        *b = -1;
        break;
    case ACT_DATA_CLOSE:
        (void)!write(*b, &c, 1);
        close(*b);
        *b = -1;
        break;
    case ACT_DATA_READ_CLOSE:
        (void)!write(*b, &c, 1);
        close(*b);
        *b = -1;
        (void)!read(*a, &c, 1);
        break;
    case ACT_SHUT_WR:
        shutdown(*b, SHUT_WR);
        break;
    case ACT_SHUT_RD:
        shutdown(*b, SHUT_RD);
        break;
    case ACT_SHUT_RDWR:
        shutdown(*b, SHUT_RDWR);
        break;
    default:
        break;
    }
}

static void check_bits(int ti, const struct row *row)
{
    char name[64], why[160] = "";
    int sv[2], dgram = ti == DGRAM_INDEX;
    snprintf(name, sizeof name, "bits_%s_%s", row->name, type_names[ti]);
    if (socketpair(AF_UNIX, sock_types[ti], 0, sv) != 0) {
        FAIL(name, "socketpair errno %d", errno);
        return;
    }
    run_action(row->action, &sv[0], &sv[1]);
    int ok = side_matches(sv[0], dgram ? row->a_dgram : row->a_conn, "a", why, sizeof why)
        && (sv[1] < 0 || side_matches(sv[1], dgram ? row->b_dgram : row->b_conn, "b", why, sizeof why));
    CHECK(name, ok, "%s", why);
    close(sv[0]);
    if (sv[1] >= 0)
        close(sv[1]);
}

static void check_unconnected(int ti)
{
    char name[64], why[160] = "";
    snprintf(name, sizeof name, "bits_unconnected_%s", type_names[ti]);
    int fd = socket(AF_UNIX, sock_types[ti], 0);
    if (fd < 0) {
        FAIL(name, "socket errno %d", errno);
        return;
    }
    CHECK(name, side_matches(fd, ti == DGRAM_INDEX ? WRITABLE : UNCONNECTED_BITS, "fd", why, sizeof why), "%s", why);
    close(fd);
}

static int next_event(int ep, unsigned *events)
{
    struct epoll_event out;
    int n = epoll_wait(ep, &out, 1, 0);
    if (n == 1)
        *events = out.events;
    return n;
}

static void check_edge(int ti, int late_add)
{
    char name[64];
    struct epoll_event reg = { .events = EPOLLIN | EPOLLRDHUP | EPOLLET };
    unsigned pre_events = 0, first_events = 0, second_events = 0;
    int sv[2], pre = 0, dgram = ti == DGRAM_INDEX;
    snprintf(name, sizeof name, "%s_%s", late_add ? "et_late_add" : "et_edge", type_names[ti]);
    int ep = epoll_create1(0);
    if (ep < 0 || socketpair(AF_UNIX, sock_types[ti], 0, sv) != 0) {
        FAIL(name, "setup errno %d", errno);
        return;
    }
    if (!late_add) {
        epoll_ctl(ep, EPOLL_CTL_ADD, sv[0], &reg);
        pre = next_event(ep, &pre_events);
    }
    close(sv[1]);
    if (late_add)
        epoll_ctl(ep, EPOLL_CTL_ADD, sv[0], &reg);
    int first = next_event(ep, &first_events);
    int second = next_event(ep, &second_events);
    int want_first = dgram ? 0 : 1;
    int ok = pre == 0 && first == want_first && (dgram || first_events == HUP_EVENTS) && second == 0;
    CHECK(name, ok, "pre %d first %d events 0x%x second %d events 0x%x", pre, first, first_events, second, second_events);
    close(sv[0]);
    close(ep);
}

static void check_level_repeats(int ti)
{
    char name[64];
    struct epoll_event reg = { .events = EPOLLIN | EPOLLRDHUP };
    unsigned first_events = 0, second_events = 0;
    int sv[2], dgram = ti == DGRAM_INDEX;
    snprintf(name, sizeof name, "lt_repeats_%s", type_names[ti]);
    int ep = epoll_create1(0);
    if (ep < 0 || socketpair(AF_UNIX, sock_types[ti], 0, sv) != 0) {
        FAIL(name, "setup errno %d", errno);
        return;
    }
    close(sv[1]);
    epoll_ctl(ep, EPOLL_CTL_ADD, sv[0], &reg);
    int first = next_event(ep, &first_events);
    int second = next_event(ep, &second_events);
    int want = dgram ? 0 : 1;
    int ok = first == want && second == want && (dgram || (first_events == HUP_EVENTS && second_events == HUP_EVENTS));
    CHECK(name, ok, "first %d events 0x%x second %d events 0x%x", first, first_events, second, second_events);
    close(sv[0]);
    close(ep);
}

static int make_listener(int type, struct sockaddr_un *sa)
{
    int ls = socket(AF_UNIX, type, 0);
    memset(sa, 0, sizeof *sa);
    sa->sun_family = AF_UNIX;
    snprintf(sa->sun_path, sizeof sa->sun_path, "/tmp/ub-epollhup-%d.sock", type);
    unlink(sa->sun_path);
    if (ls < 0 || bind(ls, (struct sockaddr *)sa, sizeof *sa) != 0 || listen(ls, 4) != 0)
        return -1;
    return ls;
}

static int connect_accept(int type, int ls, const struct sockaddr_un *sa, int *client, int *server)
{
    *client = socket(AF_UNIX, type, 0);
    if (*client < 0 || connect(*client, (const struct sockaddr *)sa, sizeof *sa) != 0)
        return -1;
    *server = accept(ls, 0, 0);
    return *server < 0 ? -1 : 0;
}

static void check_listener(int ti)
{
    char name[64], why[160] = "";
    struct sockaddr_un sa;
    int client = -1, server = -1, type = sock_types[ti];
    int ls = make_listener(type, &sa);
    snprintf(name, sizeof name, "listener_idle_%s", type_names[ti]);
    if (ls < 0) {
        FAIL(name, "listener setup errno %d", errno);
        return;
    }
    CHECK(name, side_matches(ls, 0, "listener", why, sizeof why), "%s", why);
    snprintf(name, sizeof name, "listener_pending_%s", type_names[ti]);
    int pending_client = socket(AF_UNIX, type, 0);
    int connected = pending_client >= 0 && connect(pending_client, (struct sockaddr *)&sa, sizeof sa) == 0;
    why[0] = 0;
    CHECK(name, connected && side_matches(ls, READABLE, "listener", why, sizeof why), "connected %d %s", connected, why);
    server = connected ? accept(ls, 0, 0) : -1;
    snprintf(name, sizeof name, "listener_after_accept_%s", type_names[ti]);
    why[0] = 0;
    CHECK(name, server >= 0 && side_matches(ls, 0, "listener", why, sizeof why), "accept %d %s", server, why);
    if (server >= 0)
        close(server);
    if (pending_client >= 0)
        close(pending_client);
    snprintf(name, sizeof name, "accepted_sees_client_close_%s", type_names[ti]);
    why[0] = 0;
    int paired = connect_accept(type, ls, &sa, &client, &server) == 0;
    if (paired)
        close(client);
    CHECK(name, paired && side_matches(server, EOF_BITS, "accepted", why, sizeof why), "paired %d %s", paired, why);
    if (paired)
        close(server);
    snprintf(name, sizeof name, "client_sees_accepted_close_%s", type_names[ti]);
    why[0] = 0;
    paired = connect_accept(type, ls, &sa, &client, &server) == 0;
    if (paired)
        close(server);
    CHECK(name, paired && side_matches(client, EOF_BITS, "client", why, sizeof why), "paired %d %s", paired, why);
    if (paired)
        close(client);
    close(ls);
    unlink(sa.sun_path);
}

static volatile int closer_round;
static volatile int closer_done;
static volatile int closer_fd;
static volatile int closer_quit;

static void *closer_main(void *arg)
{
    unsigned seed = 12345;
    int served = 0;
    (void)arg;
    while (!__atomic_load_n(&closer_quit, __ATOMIC_ACQUIRE)) {
        int round = __atomic_load_n(&closer_round, __ATOMIC_ACQUIRE);
        if (round == served) {
            relax();
            continue;
        }
        served = round;
        spin(rand_r(&seed) % 300);
        close(__atomic_load_n(&closer_fd, __ATOMIC_ACQUIRE));
        __atomic_store_n(&closer_done, served, __ATOMIC_RELEASE);
    }
    return NULL;
}

enum wait_mode { WAIT_POLL, WAIT_EPOLL_LT, WAIT_EPOLL_ET };

static const char *const mode_names[] = { "poll", "epoll_lt", "epoll_et" };

static unsigned wait_for_hup(enum wait_mode mode, int a, int ep, int *got)
{
    unsigned bits = 0;
    if (mode == WAIT_POLL) {
        struct pollfd p = { a, POLLIN | POLLRDHUP, 0 };
        *got = poll(&p, 1, WAIT_MS);
        bits = (unsigned)p.revents;
    } else {
        struct epoll_event out = { 0 };
        *got = epoll_wait(ep, &out, 1, WAIT_MS);
        bits = out.events;
    }
    return bits;
}

static void check_hup_wake(int ti, enum wait_mode mode)
{
    char name[64];
    int lost = 0, wrong = 0, first_wrong_bits = 0;
    snprintf(name, sizeof name, "hup_wake_%s_%s", mode_names[mode], type_names[ti]);
    for (int round = 1; round <= HUP_ROUNDS; round++) {
        int sv[2], got = 0;
        if (socketpair(AF_UNIX, sock_types[ti], 0, sv) != 0) {
            FAIL(name, "socketpair errno %d at round %d", errno, round);
            return;
        }
        int ep = -1;
        if (mode != WAIT_POLL) {
            struct epoll_event reg = { .events = EPOLLIN | EPOLLRDHUP | (mode == WAIT_EPOLL_ET ? EPOLLET : 0), .data.fd = sv[0] };
            ep = epoll_create1(0);
            epoll_ctl(ep, EPOLL_CTL_ADD, sv[0], &reg);
        }
        __atomic_store_n(&closer_fd, sv[1], __ATOMIC_RELEASE);
        __atomic_store_n(&closer_round, round, __ATOMIC_RELEASE);
        unsigned bits = wait_for_hup(mode, sv[0], ep, &got);
        while (__atomic_load_n(&closer_done, __ATOMIC_ACQUIRE) != round)
            relax();
        if (got != 1)
            lost++;
        else if ((bits & HUP_EVENTS) != HUP_EVENTS && !wrong++)
            first_wrong_bits = (int)bits;
        close(sv[0]);
        if (ep >= 0)
            close(ep);
    }
    CHECK(name, lost == 0 && wrong == 0, "lost %d wrong %d first wrong bits 0x%x of %d rounds", lost, wrong, first_wrong_bits, HUP_ROUNDS);
}

static volatile int wake_go;
static volatile int wake_wrote;
static int wake_efd;

static void *wake_writer(void *arg)
{
    unsigned seed = (unsigned)(uintptr_t)arg * 2654435761u + 1;
    uint64_t one = 1;
    for (int round = 1; round <= WAKE_ROUNDS; round++) {
        while (__atomic_load_n(&wake_go, __ATOMIC_ACQUIRE) < round)
            relax();
        spin(rand_r(&seed) % 400);
        (void)!write(wake_efd, &one, sizeof one);
        __atomic_add_fetch(&wake_wrote, 1, __ATOMIC_ACQ_REL);
    }
    return NULL;
}

static void check_wake(int edge_triggered)
{
    char name[64];
    pthread_t writers[WAKE_WRITERS];
    struct epoll_event reg = { .events = EPOLLIN | (edge_triggered ? EPOLLET : 0) }, out;
    int lost = 0, first_lost = 0;
    snprintf(name, sizeof name, "wake_drained_%s", edge_triggered ? "et" : "lt");
    wake_go = 0;
    wake_wrote = 0;
    wake_efd = eventfd(0, EFD_NONBLOCK);
    int ep = epoll_create1(0);
    reg.data.fd = wake_efd;
    if (wake_efd < 0 || ep < 0 || epoll_ctl(ep, EPOLL_CTL_ADD, wake_efd, &reg) != 0) {
        FAIL(name, "setup errno %d", errno);
        return;
    }
    for (long i = 0; i < WAKE_WRITERS; i++)
        pthread_create(&writers[i], NULL, wake_writer, (void *)(i + 1));
    for (int round = 1; round <= WAKE_ROUNDS; round++) {
        uint64_t drained;
        __atomic_store_n(&wake_go, round, __ATOMIC_RELEASE);
        if (epoll_wait(ep, &out, 1, WAIT_MS) != 1 && !lost++)
            first_lost = round;
        while (__atomic_load_n(&wake_wrote, __ATOMIC_ACQUIRE) < round * WAKE_WRITERS)
            relax();
        (void)!read(wake_efd, &drained, sizeof drained);
    }
    for (int i = 0; i < WAKE_WRITERS; i++)
        pthread_join(writers[i], NULL);
    CHECK(name, lost == 0, "lost %d wakeups of %d rounds, first at %d", lost, WAKE_ROUNDS, first_lost);
    close(ep);
    close(wake_efd);
}

int main(void)
{
    pthread_t closer;
    for (int ti = 0; ti < TYPE_COUNT; ti++) {
        for (unsigned r = 0; r < sizeof rows / sizeof rows[0]; r++)
            check_bits(ti, &rows[r]);
        check_unconnected(ti);
        check_edge(ti, 0);
        check_edge(ti, 1);
        check_level_repeats(ti);
        if (ti != DGRAM_INDEX)
            check_listener(ti);
    }
    pthread_create(&closer, NULL, closer_main, NULL);
    for (int ti = 0; ti < DGRAM_INDEX; ti++)
        for (int mode = WAIT_POLL; mode <= WAIT_EPOLL_ET; mode++)
            check_hup_wake(ti, (enum wait_mode)mode);
    __atomic_store_n(&closer_quit, 1, __ATOMIC_RELEASE);
    pthread_join(closer, NULL);
    check_wake(0);
    check_wake(1);
    return 0;
}
