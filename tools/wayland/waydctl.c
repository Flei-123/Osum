// SPDX-License-Identifier: GPL-2.0-only
// tools/wayland/waydctl.c -- DER WAECHTER: BEDARFSSTART FUER wayd.
//
// Justins zweite Vorgabe vom 14.09.2026, und sie ist die richtige:
// der Wayland-Server soll NICHT dauerhaft laufen und auch nicht von
// Hand eingeschaltet werden muessen. Er soll kommen, wenn ein Programm
// ihn braucht, und gehen, wenn keines mehr da ist.
//
// Linux nennt das SOCKET ACTIVATION, systemd macht es so, und die
// Bauform ist dieselbe:
//
//   1. DER WAECHTER haelt den Socket, nicht der Server. `bind` und
//      `listen` passieren HIER, einmal, und bleiben.
//   2. Der Waechter wartet in `accept`. Kommt eine Verbindung, startet
//      er `/bin/wayd` -- mit `fork`, damit der lauschende Deskriptor
//      mitgeht (`elf.spawn` gibt nur 0/1/2 weiter, `fork` alles:
//      kernel/file.fi, inherit_task gegen inherit_std).
//   3. Der Server uebernimmt den Socket und bedient ALLE Clients.
//      Faellt seine Zahl auf null, wartet er die Leerlaufzeit ab und
//      beendet sich. Der Socket bleibt beim Waechter, also geht das
//      naechste Mal genauso.
//
// WAS DER CLIENT DAVON MERKT: NICHTS. Er bekommt kein "connection
// refused", weil der Socket die ganze Zeit da ist; sein `connect`
// wartet, bis jemand `accept` ruft. Genau das kann dieser Kern seit
// dieser Runde (kernel/sys.fi, do_uconnect: die Schleife auf
// S_CONNECTED). Ohne sie waere dieser Waechter nicht baubar.
//
// WARUM DER WAECHTER NICHT SELBST `accept` RUFT UND DEN DESKRIPTOR
// WEITERREICHT: er koennte -- SCM_RIGHTS kann dieser Kern jetzt. Aber
// dann muesste er die erste Verbindung zwischenspeichern und der Server
// zwei Wege kennen (einer aus SCM_RIGHTS, alle weiteren aus `accept`).
// So kennt der Server genau EINEN Weg, und der Waechter ruft `accept`
// nie -- er sieht mit `poll`, DASS jemand da ist, und ueberlaesst das
// Annehmen dem Server. Weniger Teile, weniger Faelle.

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

#define SYS_write      1
#define SYS_close      3
#define SYS_poll       7
#define SYS_nanosleep  35
#define SYS_socket     41
#define SYS_bind       49
#define SYS_listen     50
#define SYS_fork       57
#define SYS_execve     59
#define SYS_exit       60
#define SYS_wait4      61
#define SYS_unlink     87
#define SYS_getpid     39

#define AF_UNIX     1
#define SOCK_STREAM 1
#define POLLIN      1

struct sockaddr_un { unsigned short sun_family; char sun_path[108]; };

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
    b[i--] = 0;
    if (v < 0) { outs("-"); v = -v; }
    if (v == 0) b[i--] = '0';
    while (v > 0) { b[i--] = (char)('0' + (v % 10)); v /= 10; }
    outs(&b[i + 1]);
}

static void nap(long ms)
{
    long ts[2];
    ts[0] = ms / 1000;
    ts[1] = (ms % 1000) * 1000000L;
    sysc(SYS_nanosleep, (long)ts, 0, 0, 0, 0, 0);
}

int main(int argc, char **argv, char **envp)
{
    const char *path = (argc > 1) ? argv[1] : "/tmp/wayland-0";
    const char *server = "/bin/wayd";

    // Ein alter Socket unter demselben Pfad gehoert einem Lauf, den es
    // nicht mehr gibt. Weg damit, sonst scheitert `bind` mit
    // -EADDRINUSE und der Waechter startet nie.
    sysc(SYS_unlink, (long)path, 0, 0, 0, 0, 0);

    long ls = sysc(SYS_socket, AF_UNIX, SOCK_STREAM, 0, 0, 0, 0);
    if (ls < 0) { outs("waydctl: kein Socket\n"); return 1; }

    struct sockaddr_un sa;
    sa.sun_family = AF_UNIX;
    {
        int i = 0;
        while (path[i] && i < 107) { sa.sun_path[i] = path[i]; i++; }
        sa.sun_path[i] = 0;
    }
    if (sysc(SYS_bind, ls, (long)&sa, sizeof(sa), 0, 0, 0) < 0) {
        outs("waydctl: bind geht nicht\n");
        return 1;
    }
    sysc(SYS_listen, ls, 8, 0, 0, 0, 0);

    outs("waydctl: waechter bereit auf ");
    outs(path);
    outs(" (fd ");
    outnum(ls);
    outs(")\n");

    // Die Schleife: warten, bis jemand anklopft, dann den Server
    // starten und warten, bis er von selbst geht.
    for (;;) {
        long pfd[1];
        *(int *)&pfd[0] = (int)ls;
        *(short *)((char *)&pfd[0] + 4) = POLLIN;
        *(short *)((char *)&pfd[0] + 6) = 0;

        long r = sysc(SYS_poll, (long)pfd, 1, -1, 0, 0, 0);
        if (r < 0) { nap(50); continue; }
        short re = *(short *)((char *)&pfd[0] + 6);
        if (!(re & POLLIN)) { nap(50); continue; }

        // JEMAND IST DA. Der Server wird gestartet und erbt den
        // lauschenden Deskriptor -- deshalb `fork` und nicht `spawn`.
        outs("waydctl: ein Client klopft -- starte ");
        outs(server);
        outs("\n");

        long pid = sysc(SYS_fork, 0, 0, 0, 0, 0, 0);
        if (pid == 0) {
            // Im Kind: der Server. Er bekommt den Deskriptor als
            // Argument, damit er weiss, dass er nicht selbst binden
            // soll.
            char fdtxt[8];
            int i = 7;
            long v = ls;
            fdtxt[i--] = 0;
            if (v == 0) fdtxt[i--] = '0';
            while (v > 0) { fdtxt[i--] = (char)('0' + (v % 10)); v /= 10; }
            char *av[5];
            av[0] = (char *)server;
            av[1] = (char *)path;
            av[2] = &fdtxt[i + 1];
            // Die Leerlaufzeit wird durchgereicht, damit die Abnahme
            // sie kurz setzen kann, ohne den Server neu zu bauen.
            av[3] = (argc > 2) ? argv[2] : 0;
            av[4] = 0;
            sysc(SYS_execve, (long)server, (long)av, (long)envp, 0, 0, 0);
            outs("waydctl: execve gescheitert\n");
            sysc(SYS_exit, 127, 0, 0, 0, 0, 0);
        }
        if (pid < 0) { outs("waydctl: fork gescheitert\n"); nap(500); continue; }

        long st = 0;
        sysc(SYS_wait4, pid, (long)&st, 0, 0, 0, 0);
        outs("waydctl: wayd ist gegangen (Code ");
        outnum(st >> 8);
        outs(") -- der Socket bleibt\n");
    }
    return 0;
}
