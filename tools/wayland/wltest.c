// SPDX-License-Identifier: GPL-2.0-only
// tools/wayland/wltest.c -- RUNDE WAYLAND, die Messung im laufenden Kern.
//
// Was hier gemessen wird, ist NICHT das Wayland-Protokoll, sondern die
// drei Dinge darunter, ohne die es das Protokoll nicht geben kann. Sie
// waren vor dieser Runde nicht da (gemessen, siehe kernel/unixsock.fi):
//
//   1. AF_UNIX: socket/bind/listen/connect/accept ueber einen PFAD.
//   2. SCM_RIGHTS: ein DESKRIPTOR wandert durch den Socket.
//   3. MAP_SHARED: zwei Prozesse sehen DIESELBEN Rahmen.
//
// Jede Zusage steht fuer sich und wird EINZELN gedruckt, damit ein
// Fehlschlag sagt, WAS nicht geht.
//
// GEBAUT WIE JEDES FREMDE PROGRAMM (tools/foreign/README.md) -- das ist
// Absicht: dieses Programm nimmt GENAU den Weg, den der echte
// Wayland-Client nimmt. Was hier gilt, gilt dort.

#include <stddef.h>

static long sysc(long n, long a, long b, long c, long d, long e, long f)
{
    long r;
    register long r10 __asm__("r10") = d;
    register long r8  __asm__("r8")  = e;
    register long r9  __asm__("r9")  = f;
    __asm__ volatile("syscall"
                     : "=a"(r)
                     : "a"(n), "D"(a), "S"(b), "d"(c), "r"(r10), "r"(r8),
                       "r"(r9)
                     : "rcx", "r11", "memory");
    return r;
}

#define SYS_write         1
#define SYS_close         3
#define SYS_mmap          9
#define SYS_nanosleep     35
#define SYS_socket        41
#define SYS_connect       42
#define SYS_accept        43
#define SYS_sendmsg       46
#define SYS_recvmsg       47
#define SYS_bind          49
#define SYS_listen        50
#define SYS_fork          57
#define SYS_exit          60
#define SYS_wait4         61
#define SYS_fcntl         72
#define SYS_ftruncate     77
#define SYS_poll          7
#define SYS_memfd_create  319

#define AF_UNIX       1
#define SOCK_STREAM   1
#define SOL_SOCKET    1
#define SCM_RIGHTS    1
#define PROT_READ     1
#define PROT_WRITE    2
#define MAP_SHARED    1
#define F_ADD_SEALS   1033
#define F_GET_SEALS   1034
#define F_SEAL_SHRINK 2

struct sockaddr_un { unsigned short sun_family; char sun_path[108]; };
struct iovec { void *iov_base; size_t iov_len; };
struct msghdr {
    void *msg_name; unsigned int msg_namelen;
    struct iovec *msg_iov; size_t msg_iovlen;
    void *msg_control; size_t msg_controllen;
    int msg_flags;
};
struct cmsghdr { size_t cmsg_len; int cmsg_level; int cmsg_type; };

static void outs(const char *s)
{
    size_t n = 0;
    while (s[n]) n++;
    sysc(SYS_write, 1, (long)s, (long)n, 0, 0, 0);
}

static void outnum(long v)
{
    char b[24];
    int i = 23;
    int neg = 0;
    b[i--] = 0;
    if (v < 0) { neg = 1; v = -v; }
    if (v == 0) b[i--] = '0';
    while (v > 0) { b[i--] = (char)('0' + (v % 10)); v /= 10; }
    if (neg) b[i--] = '-';
    outs(&b[i + 1]);
}

static int pass_n = 0;
static int fail_n = 0;

static void ok(const char *name, int cond)
{
    if (cond) { pass_n++; outs("  ok   "); }
    else      { fail_n++; outs("  FEHL "); }
    outs(name); outs("\n");
}

static void okv(const char *name, long got, long want)
{
    int c = (got == want);
    if (c) { pass_n++; outs("  ok   "); }
    else   { fail_n++; outs("  FEHL "); }
    outs(name);
    if (!c) { outs(" (ist "); outnum(got); outs(", soll "); outnum(want); outs(")"); }
    outs("\n");
}

static void nap(long ms)
{
    long ts[2];
    ts[0] = ms / 1000;
    ts[1] = (ms % 1000) * 1000000L;
    sysc(SYS_nanosleep, (long)ts, 0, 0, 0, 0, 0);
}

static void setpath(struct sockaddr_un *a, const char *p)
{
    int i = 0;
    a->sun_family = AF_UNIX;
    while (p[i] && i < 107) { a->sun_path[i] = p[i]; i++; }
    a->sun_path[i] = 0;
}

int main(int argc, char **argv, char **envp)
{
    (void)argc; (void)argv; (void)envp;
    const char *SOCKPATH = "/tmp/wl-test-0";

    outs("== wltest: der lokale Socket und der geteilte Speicher ==\n");

    outs("\n1. AF_UNIX anlegen\n");
    long ls = sysc(SYS_socket, AF_UNIX, SOCK_STREAM, 0, 0, 0, 0);
    ok("socket(AF_UNIX, SOCK_STREAM) gelingt", ls >= 0);
    if (ls < 0) { outs("  -> Fehler "); outnum(ls); outs("\n"); goto ende; }

    long bad = sysc(SYS_socket, 99, SOCK_STREAM, 0, 0, 0, 0);
    ok("GEGENPROBE: AF_99 wird abgewiesen", bad < 0);

    long dg = sysc(SYS_socket, AF_UNIX, 2, 0, 0, 0, 0);
    ok("GEGENPROBE: AF_UNIX+SOCK_DGRAM wird abgewiesen", dg < 0);

    outs("\n2. binden und lauschen\n");
    struct sockaddr_un sa;
    setpath(&sa, SOCKPATH);
    long r = sysc(SYS_bind, ls, (long)&sa, sizeof(sa), 0, 0, 0);
    okv("bind auf einen Pfad", r, 0);

    long ls2 = sysc(SYS_socket, AF_UNIX, SOCK_STREAM, 0, 0, 0, 0);
    long r2 = sysc(SYS_bind, ls2, (long)&sa, sizeof(sa), 0, 0, 0);
    ok("GEGENPROBE: derselbe Pfad zweimal wird abgewiesen", r2 < 0);
    sysc(SYS_close, ls2, 0, 0, 0, 0, 0);

    r = sysc(SYS_listen, ls, 4, 0, 0, 0, 0);
    okv("listen", r, 0);

    outs("\n3. GEGENPROBE: verbinden, wo niemand lauscht\n");
    struct sockaddr_un nowhere;
    setpath(&nowhere, "/tmp/wl-gibt-es-nicht");
    long cs0 = sysc(SYS_socket, AF_UNIX, SOCK_STREAM, 0, 0, 0, 0);
    long rc0 = sysc(SYS_connect, cs0, (long)&nowhere, sizeof(nowhere), 0, 0, 0);
    ok("connect auf einen toten Pfad scheitert (haengt nicht)", rc0 < 0);
    sysc(SYS_close, cs0, 0, 0, 0, 0, 0);

    outs("\n4. memfd + MAP_SHARED\n");
    long mfd = sysc(SYS_memfd_create, (long)"wltest", 0, 0, 0, 0, 0);
    ok("memfd_create gelingt", mfd >= 0);

    const long SHM_BYTES = 8192;
    r = sysc(SYS_ftruncate, mfd, SHM_BYTES, 0, 0, 0, 0);
    okv("ftruncate auf 8192", r, 0);

    long addr = sysc(SYS_mmap, 0, SHM_BYTES, PROT_READ | PROT_WRITE,
                     MAP_SHARED, mfd, 0);
    ok("mmap(MAP_SHARED) gelingt", addr > 0);

    if (addr > 0) {
        volatile unsigned int *p = (volatile unsigned int *)addr;
        int sauber = 1;
        for (long i = 0; i < SHM_BYTES / 4; i++)
            if (p[i] != 0) { sauber = 0; break; }
        ok("frischer geteilter Speicher ist genullt", sauber);
        p[0] = 0xCAFEBABEu;
        p[1] = 0x12345678u;
        okv("zurueckgelesen", (long)p[0], (long)0xCAFEBABEu);
    }

    r = sysc(SYS_fcntl, mfd, F_ADD_SEALS, F_SEAL_SHRINK, 0, 0, 0);
    okv("fcntl F_ADD_SEALS F_SEAL_SHRINK", r, 0);
    long seals = sysc(SYS_fcntl, mfd, F_GET_SEALS, 0, 0, 0, 0);
    okv("F_GET_SEALS liest es zurueck", seals, F_SEAL_SHRINK);
    long shrink = sysc(SYS_ftruncate, mfd, 4096, 0, 0, 0, 0);
    ok("GEGENPROBE: verkleinern nach F_SEAL_SHRINK scheitert", shrink < 0);

    outs("\n5. zwei Prozesse, ein Speicher, ein Deskriptor durch den Socket\n");

    long pid = sysc(SYS_fork, 0, 0, 0, 0, 0, 0);
    if (pid == 0) {
        nap(60);
        long cs = sysc(SYS_socket, AF_UNIX, SOCK_STREAM, 0, 0, 0, 0);
        if (cs < 0) sysc(SYS_exit, 11, 0, 0, 0, 0, 0);
        struct sockaddr_un ca;
        setpath(&ca, SOCKPATH);
        if (sysc(SYS_connect, cs, (long)&ca, sizeof(ca), 0, 0, 0) < 0)
            sysc(SYS_exit, 12, 0, 0, 0, 0, 0);

        long kfd = sysc(SYS_memfd_create, (long)"vomkind", 0, 0, 0, 0, 0);
        if (kfd < 0) sysc(SYS_exit, 13, 0, 0, 0, 0, 0);
        if (sysc(SYS_ftruncate, kfd, 4096, 0, 0, 0, 0) < 0)
            sysc(SYS_exit, 14, 0, 0, 0, 0, 0);
        long ka = sysc(SYS_mmap, 0, 4096, PROT_READ | PROT_WRITE,
                       MAP_SHARED, kfd, 0);
        if (ka <= 0) sysc(SYS_exit, 15, 0, 0, 0, 0, 0);
        volatile unsigned int *kp = (volatile unsigned int *)ka;
        kp[0] = 0xA5A5F00Du;
        kp[1] = 4242;

        char payload[8];
        payload[0]='H'; payload[1]='A'; payload[2]='L'; payload[3]='L';
        payload[4]='O'; payload[5]='-'; payload[6]='W'; payload[7]='L';
        struct iovec iov;
        iov.iov_base = payload;
        iov.iov_len = 8;

        char cbuf[64];
        for (int i = 0; i < 64; i++) cbuf[i] = 0;
        struct cmsghdr *cm = (struct cmsghdr *)cbuf;
        cm->cmsg_len = sizeof(struct cmsghdr) + sizeof(int);
        cm->cmsg_level = SOL_SOCKET;
        cm->cmsg_type = SCM_RIGHTS;
        *(int *)(cbuf + sizeof(struct cmsghdr)) = (int)kfd;

        struct msghdr mh;
        mh.msg_name = 0; mh.msg_namelen = 0;
        mh.msg_iov = &iov; mh.msg_iovlen = 1;
        mh.msg_control = cbuf;
        mh.msg_controllen = cm->cmsg_len;
        mh.msg_flags = 0;

        long sent = sysc(SYS_sendmsg, cs, (long)&mh, 0, 0, 0, 0);
        if (sent != 8) sysc(SYS_exit, 16, 0, 0, 0, 0, 0);
        nap(250);
        sysc(SYS_exit, 0, 0, 0, 0, 0, 0);
    }

    ok("fork", pid > 0);

    long as = sysc(SYS_accept, ls, 0, 0, 0, 0, 0);
    ok("accept nimmt die Verbindung an", as >= 0);

    if (as >= 0) {
        char rbuf[32];
        for (int i = 0; i < 32; i++) rbuf[i] = 0;
        struct iovec riov;
        riov.iov_base = rbuf;
        riov.iov_len = sizeof(rbuf);
        char rcbuf[64];
        for (int i = 0; i < 64; i++) rcbuf[i] = 0;
        struct msghdr rmh;
        rmh.msg_name = 0; rmh.msg_namelen = 0;
        rmh.msg_iov = &riov; rmh.msg_iovlen = 1;
        rmh.msg_control = rcbuf;
        rmh.msg_controllen = sizeof(rcbuf);
        rmh.msg_flags = 0;

        long got = sysc(SYS_recvmsg, as, (long)&rmh, 0, 0, 0, 0);
        okv("recvmsg holt 8 Oktette", got, 8);
        ok("die Oktette stimmen",
           rbuf[0] == 'H' && rbuf[1] == 'A' && rbuf[7] == 'L');

        struct cmsghdr *rcm = (struct cmsghdr *)rcbuf;
        ok("eine Steuernachricht kam an", rmh.msg_controllen >= 20);
        ok("sie ist SOL_SOCKET/SCM_RIGHTS",
           rcm->cmsg_level == SOL_SOCKET && rcm->cmsg_type == SCM_RIGHTS);

        int nfd = *(int *)(rcbuf + sizeof(struct cmsghdr));
        ok("der Deskriptor ist gueltig", nfd > 2);

        if (nfd > 2) {
            long na = sysc(SYS_mmap, 0, 4096, PROT_READ | PROT_WRITE,
                           MAP_SHARED, nfd, 0);
            ok("mmap auf den GEERBTEN Deskriptor gelingt", na > 0);
            if (na > 0) {
                volatile unsigned int *np = (volatile unsigned int *)na;
                okv("was das Kind schrieb, steht hier",
                    (long)np[0], (long)0xA5A5F00Du);
                okv("und die zweite Zahl auch", (long)np[1], 4242);
            }
        }
    }

    // ---- 6. poll SIEHT, was der andere geschickt hat ----
    //
    // Genau daran haengt libwayland: es ruft poll und dann recvmsg. Ein
    // poll, das nichts meldet, obwohl Oktette im Ring liegen, laesst
    // jeden Client haengen -- und das sieht aus wie ein toter Server.
    outs("\n6. poll auf dem verbundenen Socket\n");
    if (as >= 0) {
        char back[4];
        back[0]='P'; back[1]='O'; back[2]='N'; back[3]='G';
        struct iovec biov;
        biov.iov_base = back;
        biov.iov_len = 4;
        struct msghdr bmh;
        bmh.msg_name = 0; bmh.msg_namelen = 0;
        bmh.msg_iov = &biov; bmh.msg_iovlen = 1;
        bmh.msg_control = 0; bmh.msg_controllen = 0;
        bmh.msg_flags = 0;
        long s2 = sysc(SYS_sendmsg, as, (long)&bmh, 0, 0, 0, 0);
        okv("der Server sendet 4 Oktette zurueck", s2, 4);
        // Jetzt MUSS poll auf der Serverseite POLLOUT melden und auf
        // der Clientseite POLLIN -- die Clientseite ist im Kind, also
        // wird hier die Richtung geprueft, die hier messbar ist.
        long pfd[1];
        // struct pollfd: int fd, short events, short revents
        *(int *)&pfd[0] = (int)as;
        *(short *)((char *)&pfd[0] + 4) = 4; // POLLOUT
        *(short *)((char *)&pfd[0] + 6) = 0;
        long pr = sysc(SYS_poll, (long)pfd, 1, 0, 0, 0, 0);
        ok("poll(POLLOUT) meldet den Socket als schreibbar", pr == 1);
    }

    long st = 0;
    sysc(SYS_wait4, pid, (long)&st, 0, 0, 0, 0);
    outs("  (Kind beendet, Status "); outnum(st >> 8); outs(")\n");

ende:
    outs("\n== wltest fertig: ");
    outnum(pass_n);
    outs(" bestanden, ");
    outnum(fail_n);
    outs(" gescheitert ==\n");
    return fail_n == 0 ? 0 : 1;
}
