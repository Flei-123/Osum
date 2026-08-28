/* SPDX-License-Identifier: GPL-2.0-only
 *
 * tools/paint/native.c -- WAS DIE MISCHUNG AUF ECHTER HARDWARE KOSTET.
 *
 * WARUM ES DIESE DATEI GIBT.  Die Zahlen aus `paintbench` im Kern werden
 * unter `qemu-system-x86_64` OHNE /dev/kvm gemessen -- der Messrechner
 * dieses Projekts hat keines (`ls /dev/kvm` -> No such file).  QEMU
 * uebersetzt dann jeden Gastbefehl (TCG).  Das trifft die beiden Wege
 * SEHR verschieden hart:
 *
 *   * `fb.fill` ist `rep stosq`.  Das ist fuer TCG EIN Baustein, den
 *     QEMU auf ein `memset` des Wirts abbildet.  Es kostet im Gast fast
 *     nichts.
 *   * `fb.fill_a` ist eine Schleife aus dreissig gewoehnlichen
 *     Befehlen je Bildpunkt.  Jeder davon wird uebersetzt und
 *     ausgefuehrt.
 *
 * Ein Verhaeltnis, das unter TCG gemessen wurde, ist deshalb KEINE
 * Aussage ueber die Maschine, auf der das System laufen soll.  Diese
 * Datei misst DIESELBE Rechnung nativ, auf dem Prozessor des Wirts,
 * mit demselben `rdtsc` -- und der Vergleich der beiden Verhaeltnisse
 * sagt, wie stark die Emulation die Mischung benachteiligt.
 *
 * Gebaut und gerufen von tools/paint/run.sh; von Hand:
 *     cc -O2 -o /tmp/native tools/paint/native.c && /tmp/native
 *
 * -O2 und nicht -O3: firnc optimiert nicht aggressiv, und eine
 * automatisch vektorisierte Schleife waere eine Antwort auf eine andere
 * Frage.  -fno-tree-vectorize steht deshalb ausdruecklich dabei.
 */
#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include <string.h>

#define W 800u
#define H 600u
#define RUNDEN 20u

static inline uint64_t tsc(void)
{
    unsigned lo, hi;
    __asm__ __volatile__("rdtsc" : "=a"(lo), "=d"(hi));
    return ((uint64_t)hi << 32) | lo;
}

/* Genau `fb.mix8`. */
static inline uint32_t mix8(uint32_t dst, uint32_t src, uint32_t a,
                            uint32_t ia)
{
    uint32_t t = src * a + dst * ia + 128u;
    return (t + (t >> 8)) >> 8;
}

__attribute__((noinline, optimize("no-tree-vectorize")))
static void fuellen(uint32_t *p, size_t n, uint32_t farbe)
{
    for (size_t i = 0; i < n; i++)
        p[i] = farbe;
}

__attribute__((noinline, optimize("no-tree-vectorize")))
static void mischen(uint32_t *p, size_t n, uint32_t farbe, uint32_t a)
{
    uint32_t ia = 255u - a;
    uint32_t sr = (farbe >> 16) & 0xFF, sg = (farbe >> 8) & 0xFF;
    uint32_t sb = farbe & 0xFF;
    for (size_t i = 0; i < n; i++) {
        uint32_t alt = p[i];
        uint32_t r = mix8((alt >> 16) & 0xFF, sr, a, ia);
        uint32_t g = mix8((alt >> 8) & 0xFF, sg, a, ia);
        uint32_t b = mix8(alt & 0xFF, sb, a, ia);
        p[i] = (r << 16) | (g << 8) | b;
    }
}

/* Die abschneidende Fassung von VOR dieser Runde -- damit der Preis der
 * richtigen Rundung eine Zahl bekommt und keine Vermutung bleibt. */
__attribute__((noinline, optimize("no-tree-vectorize")))
static void mischen_div(uint32_t *p, size_t n, uint32_t farbe, uint32_t a)
{
    uint32_t ia = 255u - a;
    uint32_t sr = (farbe >> 16) & 0xFF, sg = (farbe >> 8) & 0xFF;
    uint32_t sb = farbe & 0xFF;
    for (size_t i = 0; i < n; i++) {
        uint32_t alt = p[i];
        uint32_t r = (((alt >> 16) & 0xFF) * ia + sr * a) / 255u;
        uint32_t g = (((alt >> 8) & 0xFF) * ia + sg * a) / 255u;
        uint32_t b = ((alt & 0xFF) * ia + sb * a) / 255u;
        p[i] = (r << 16) | (g << 8) | b;
    }
}

int main(void)
{
    size_t n = (size_t)W * H;
    uint32_t *p = malloc(n * 4);
    if (!p) return 1;
    memset(p, 0x11, n * 4);

    /* aufwaermen -- der erste Durchgang bezahlt die Seitenfehler */
    fuellen(p, n, 0x203040);
    mischen(p, n, 0xFFFFFF, 128);
    mischen_div(p, n, 0xFFFFFF, 128);

    uint64_t t0 = tsc();
    for (unsigned i = 0; i < RUNDEN; i++) fuellen(p, n, 0x203040u + i);
    uint64_t c_fill = (tsc() - t0) / RUNDEN;

    t0 = tsc();
    for (unsigned i = 0; i < RUNDEN; i++) mischen(p, n, 0xFFFFFF, 128);
    uint64_t c_mix = (tsc() - t0) / RUNDEN;

    t0 = tsc();
    for (unsigned i = 0; i < RUNDEN; i++) mischen_div(p, n, 0xFFFFFF, 128);
    uint64_t c_div = (tsc() - t0) / RUNDEN;

    printf("PAINT-NATIV: %ux%u = %zu Bildpunkte, %u Durchgaenge\n",
           W, H, n, RUNDEN);
    printf("   fuellen (opak)        %10llu Takte  %6.3f je Bildpunkt\n",
           (unsigned long long)c_fill, (double)c_fill / n);
    printf("   mischen (schieben)    %10llu Takte  %6.3f je Bildpunkt\n",
           (unsigned long long)c_mix, (double)c_mix / n);
    printf("   mischen (Division)    %10llu Takte  %6.3f je Bildpunkt\n",
           (unsigned long long)c_div, (double)c_div / n);
    printf("   faktor mischen/opak   %.2f\n", (double)c_mix / (double)c_fill);
    printf("   faktor Division/schieben %.2f\n",
           (double)c_div / (double)c_mix);
    free(p);
    return 0;
}
