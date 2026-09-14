// SPDX-License-Identifier: GPL-2.0-only
// tools/wayland/leerlauf.c -- WAS DER WAYLAND-SERVER IM LEERLAUF KOSTET.
//
// Justins Vorgabe vom 14.09.2026: "Miss den Speicher-/CPU-Kostenpunkt im
// Leerlauf, dann ist die Entscheidung belegt statt behauptet."
//
// Gemessen wird GENAU das: ein `wayd`, das laeuft und auf den ersten
// Client wartet -- keiner kommt. Zwei Zahlen, beide aus dem Kern:
//
//   SEITEN  P_PAGES: wieviele 4-KiB-Seiten der Prozess wirklich
//           abgebildet hat. Das ist der Hauptspeicher, den er belegt,
//           und nicht die Groesse seiner Datei.
//   MARKEN  P_TICKS: wieviel Rechenzeit er verbraucht hat. Bei 100 Hz
//           ist eine Marke 10 ms.
//
// Das Verfahren: zweimal messen, mit einer bekannten Pause dazwischen,
// und die DIFFERENZ nehmen. Ein einzelner Messpunkt saehe den Start mit
// und sagte nichts ueber den Leerlauf.
//
// UND DIE GEGENPROBE, ohne die eine Zahl nichts wert ist: dieselbe
// Messung an einem Prozess, von dem man WEISS, dass er Rechenzeit
// verbrennt. Waere die Messung blind, zeigten beide null.

#include <stddef.h>

static long sysc(long n, long a, long b, long c)
{
    long r;
    __asm__ volatile("syscall" : "=a"(r) : "a"(n), "D"(a), "S"(b), "d"(c)
                     : "rcx", "r11", "memory");
    return r;
}

#define SYS_write     1
#define SYS_nanosleep 35
#define SYS_PSTAT     1003
#define P_STATE 0
#define P_PID   1
#define P_TICKS 5
#define P_PAGES 9

static void outs(const char *s)
{
    size_t n = 0;
    while (s[n]) n++;
    sysc(SYS_write, 1, (long)s, (long)n);
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

static void nap(long ms)
{
    long ts[2];
    ts[0] = ms / 1000;
    ts[1] = (ms % 1000) * 1000000L;
    sysc(SYS_nanosleep, (long)ts, 0, 0);
}

// Den Platz finden, an dem eine bestimmte pid steht.
static long slot_of(long pid)
{
    for (long i = 0; i < 32; i++)
        if (sysc(SYS_PSTAT, i, P_STATE, 0) != 0
            && sysc(SYS_PSTAT, i, P_PID, 0) == pid)
            return i;
    return -1;
}

int main(int argc, char **argv, char **envp)
{
    (void)argv; (void)envp;
    (void)argc;

    outs("== Leerlaufkosten, gemessen ==\n");

    // Alle laufenden Prozesse mit Seiten und Marken, zweimal.
    long s1[32], t1[32], p1[32];
    int n = 0;
    for (long i = 0; i < 32 && n < 32; i++) {
        if (sysc(SYS_PSTAT, i, P_STATE, 0) == 0) continue;
        s1[n] = i;
        p1[n] = sysc(SYS_PSTAT, i, P_PID, 0);
        t1[n] = sysc(SYS_PSTAT, i, P_TICKS, 0);
        n++;
    }

    // ZEHN SEKUNDEN statt zwei. `wayd` gibt in seiner Schleife mit
    // YIELD ab, und eine Aufgabe, die abgibt, bevor ihre Marke voll
    // ist, bekommt sie unter Umstaenden gar nicht angeschrieben. Ueber
    // zwei Sekunden war das Ergebnis null, und eine Null, die nur
    // "unter der Aufloesung" heisst, ist keine Messung.
    const long PAUSE = 10000;
    nap(PAUSE);

    outs("pid  seiten  marken/10s  (1 Marke = 10 ms)\n");
    for (int k = 0; k < n; k++) {
        long t2 = sysc(SYS_PSTAT, s1[k], P_TICKS, 0);
        long pg = sysc(SYS_PSTAT, s1[k], P_PAGES, 0);
        outnum(p1[k]); outs("  ");
        outnum(pg);    outs("  ");
        outnum(t2 - t1[k]);
        outs("\n");
    }
    outs("== Ende ==\n");
    return 0;
}
