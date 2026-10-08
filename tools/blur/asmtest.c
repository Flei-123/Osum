// SPDX-License-Identifier: GPL-2.0-only
// tools/blur/asmtest.c -- r464: the assembly loops of tools/blur/blurasm.py against the Firn loops of kernel/ui/wm.fi
// (blur_h, blur_v, blur_mix) written out in C, on random pictures, many sizes and radii. Exit 0 = all equal.
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdint.h>
typedef uint64_t u64;
typedef uint32_t u32;
extern void blur_h_asm(u64 *p);
extern void blur_v_asm(u64 *p);
extern void blur_m_asm(u64 *p);
#define SHIFT 19
#define RUND 262144ull
static u64 rec[64];
static u64 bdiv(u64 s, u64 r) { return (s * r + RUND) >> SHIFT; }
static void ref_h(u32 *q, u32 *z, u64 w, u64 h, u64 r) {
    for (u64 y = 0; y < h; y++) {
        u32 *qz = q + y * w, *zz = z + y * w;
        u64 sr = 0, sg = 0, sb = 0, n = 0;
        for (u64 k = 0; k <= r && k < w; k++) { u32 p = qz[k]; sr += (p >> 16) & 255; sg += (p >> 8) & 255; sb += p & 255; n++; }
        for (u64 x = 0; x < w; x++) {
            u64 rc = rec[n];
            zz[x] = (u32)((bdiv(sr, rc) << 16) | (bdiv(sg, rc) << 8) | bdiv(sb, rc));
            if (x + r + 1 < w) { u32 p = qz[x + r + 1]; sr += (p >> 16) & 255; sg += (p >> 8) & 255; sb += p & 255; n++; }
            if (x >= r) { u32 p = qz[x - r]; sr -= (p >> 16) & 255; sg -= (p >> 8) & 255; sb -= p & 255; n--; }
        }
    }
}
static void ref_v(u32 *q, u32 *z, u64 w, u64 h, u64 r) {
    u64 *gr = calloc(w, 8), *gg = calloc(w, 8), *gb = calloc(w, 8);
    u64 n = 0;
    for (u64 k = 0; k <= r && k < h; k++) {
        for (u64 x = 0; x < w; x++) { u32 p = q[k * w + x]; gr[x] += (p >> 16) & 255; gg[x] += (p >> 8) & 255; gb[x] += p & 255; }
        n++;
    }
    for (u64 y = 0; y < h; y++) {
        u64 rc = rec[n];
        for (u64 x = 0; x < w; x++) z[y * w + x] = (u32)((bdiv(gr[x], rc) << 16) | (bdiv(gg[x], rc) << 8) | bdiv(gb[x], rc));
        if (y + r + 1 < h) { for (u64 x = 0; x < w; x++) { u32 p = q[(y + r + 1) * w + x]; gr[x] += (p >> 16) & 255; gg[x] += (p >> 8) & 255; gb[x] += p & 255; } n++; }
        if (y >= r) { for (u64 x = 0; x < w; x++) { u32 p = q[(y - r) * w + x]; gr[x] -= (p >> 16) & 255; gg[x] -= (p >> 8) & 255; gb[x] -= p & 255; } n--; }
    }
    free(gr); free(gg); free(gb);
}
static u64 mix_ch(u64 a, u64 b, u64 per) { return (a * (100 - per) + b * per) / 100; }
static u64 mix24(u64 a, u64 b, u64 per) {
    return (mix_ch((a >> 16) & 255, (b >> 16) & 255, per) << 16) | (mix_ch((a >> 8) & 255, (b >> 8) & 255, per) << 8) | mix_ch(a & 255, b & 255, per);
}
static u64 noise(u64 x, u64 y, u64 amp) {
    if (amp == 0) return 0;
    u64 v = x * 73856093ull; v ^= y * 19349663ull; v ^= v >> 13; v *= 2654435761ull; v ^= v >> 15;
    return v % (amp * 2 + 1);
}
static u64 ref_mix(u64 farbe, u64 ton, u64 tint, u64 amp, u64 x, u64 y) {
    u64 c = farbe;
    if (tint) c = mix24(c, ton, tint);
    if (amp == 0) return c;
    u64 d = noise(x, y, amp);
    u64 r = (c >> 16) & 255, g = (c >> 8) & 255, b = c & 255;
    if (d >= amp) { u64 a = d - amp; r += a; g += a; b += a; if (r > 255) r = 255; if (g > 255) g = 255; if (b > 255) b = 255; }
    else { u64 a = amp - d; r = r > a ? r - a : 0; g = g > a ? g - a : 0; b = b > a ? b - a : 0; }
    return (r << 16) | (g << 8) | b;
}
static u32 rnd32(void) { return ((u32)rand() << 16) ^ (u32)rand(); }
int main(void) {
    for (u64 n = 1; n < 64; n++) rec[n] = ((1ull << SHIFT) + n - 1) / n;
    rec[0] = 0;
    int bad = 0; long cases = 0;
    srand(12345);
    u64 sizes[][2] = {{1,1},{2,3},{5,5},{17,3},{3,17},{33,34},{35,2},{64,40},{100,7},{640,5},{9,200}};
    for (int si = 0; si < 11; si++) for (u64 r = 1; r <= 16; r++) {
        u64 w = sizes[si][0], h = sizes[si][1];
        u32 *a = malloc(w * h * 4), *b = malloc(w * h * 4), *c = malloc(w * h * 4);
        for (u64 i = 0; i < w * h; i++) a[i] = rnd32() & 0xFFFFFF;
        if (si % 3 == 0) for (u64 i = 0; i < w * h; i++) a[i] = (i & 1) ? 0xFFFFFF : 0;
        u64 *sum = malloc(3 * 27520);
        u64 p[8] = {(u64)a, (u64)b, w, h, r, (u64)rec, 0, 0};
        ref_h(a, c, w, h, r); { u64 pp[8]; memcpy(pp, p, sizeof p); blur_h_asm(pp); }
        if (memcmp(b, c, w * h * 4)) { printf("FAIL h w=%lu h=%lu r=%lu\n", w, h, r); bad++; }
        p[6] = (u64)sum;
        ref_v(a, c, w, h, r); { u64 pp[8]; memcpy(pp, p, sizeof p); blur_v_asm(pp); }
        if (memcmp(b, c, w * h * 4)) { printf("FAIL v w=%lu h=%lu r=%lu\n", w, h, r); bad++; }
        free(a); free(b); free(c); free(sum); cases += 2;
    }
    for (int t = 0; t < 400; t++) {
        u64 n = 1 + rnd32() % 300, tint = (t % 5 == 0) ? 0 : rnd32() % 101, amp = (t % 4 == 0) ? 0 : rnd32() % 20;
        u64 ton = rnd32() & 0xFFFFFF, x0 = rnd32() % 3000, y = rnd32() % 2000;
        u32 *a = malloc(n * 4), *b = malloc(n * 4);
        for (u64 i = 0; i < n; i++) a[i] = rnd32() & 0xFFFFFF;
        if (t % 7 == 0) for (u64 i = 0; i < n; i++) a[i] = (i & 1) ? 0xFFFFFF : 0;
        u64 p[12] = {(u64)a, (u64)b, n, x0, y * 19349663ull, amp, amp * 2 + 1, 100 - tint,
                     ((ton >> 16) & 255) * tint, ((ton >> 8) & 255) * tint, (ton & 255) * tint, 0};
        blur_m_asm(p);
        for (u64 i = 0; i < n; i++) {
            u32 want = (u32)ref_mix(a[i], ton, tint, amp, x0 + i, y);
            if (b[i] != want) { printf("FAIL m t=%d i=%lu tint=%lu amp=%lu got=%06x want=%06x\n", t, i, tint, amp, b[i], want); bad++; break; }
        }
        free(a); free(b); cases++;
    }
    printf("blurasm: %ld cases, %d failed\n", cases, bad);
    return bad ? 1 : 0;
}
