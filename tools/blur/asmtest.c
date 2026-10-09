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
extern void blur_d_asm(u64 *p);
extern void blur_g_asm(u64 *p);
extern void blur_s_asm(u64 *p);
extern void blur_w_asm(u64 *p);
extern void blur_x_asm(u64 *p);
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
        u64 *sum = malloc(3 * 27520); memset(sum, 0xA5, 3 * 27520);
        if (si % 2) for (u64 i = 0; i < w * h; i++) a[i] |= rnd32() & 0xFF000000u;   /* alpha bytes must not matter */
        u64 p[16] = {(u64)a, (u64)b, w, h, r, (u64)rec, 0, 0};
        ref_h(a, c, w, h, r); { u64 pp[16]; memcpy(pp, p, sizeof p); blur_h_asm(pp); }
        if (memcmp(b, c, w * h * 4)) { printf("FAIL h w=%lu h=%lu r=%lu\n", w, h, r); bad++; }
        /* r481: four rows at a time (block x), the rest through the scalar loop */
        { memset(b, 0x5A, w * h * 4); u64 h4 = h & ~3ull; u64 pp[16] = {(u64)a, (u64)b, w, h4, r, (u64)rec, 0, 0, 0, 0};
          blur_x_asm(pp);
          u64 p2[16] = {(u64)(a + h4 * w), (u64)(b + h4 * w), w, h - h4, r, (u64)rec, 0, 0}; blur_h_asm(p2);
          if (memcmp(b, c, w * h * 4)) { printf("FAIL x w=%lu h=%lu r=%lu\n", w, h, r); bad++; } }
        p[6] = (u64)sum; p[11] = w;
        ref_v(a, c, w, h, r); { u64 pp[16]; memcpy(pp, p, sizeof p); blur_v_asm(pp); }
        if (memcmp(b, c, w * h * 4)) { printf("FAIL v w=%lu h=%lu r=%lu\n", w, h, r); bad++; }
        /* r481: the columns in groups of four (block w), the other columns through the scalar loop, same pitch */
        { memset(b, 0x5A, w * h * 4); memset(sum, 0xA5, 3 * 27520); u64 c4 = w & ~3ull;
          u64 pp[16] = {(u64)a, (u64)b, c4, h, r, (u64)rec, (u64)sum, 0, 0, 0, 0, w};
          blur_w_asm(pp);
          u64 p2[16] = {(u64)(a + c4), (u64)(b + c4), w - c4, h, r, (u64)rec, (u64)(sum + c4), 0, 0, 0, 0, w}; blur_v_asm(p2);
          if (memcmp(b, c, w * h * 4)) { printf("FAIL w w=%lu h=%lu r=%lu\n", w, h, r); bad++; } }
        free(a); free(b); free(c); free(sum); cases += 4;
    }
    for (int t = 0; t < 4000; t++) {
        u64 n = 1 + rnd32() % 300, tint = (t % 5 == 0) ? 0 : rnd32() % 101, amp = (t % 4 == 0) ? 0 : rnd32() % 40;
        u64 ton = rnd32() & 0xFFFFFF, x0 = rnd32() % 100000, y = rnd32() % 100000;
        u32 *a = malloc(n * 4), *b = malloc(n * 4);
        for (u64 i = 0; i < n; i++) a[i] = rnd32();
        if (t % 7 == 0) for (u64 i = 0; i < n; i++) a[i] = (i & 1) ? 0xFFFFFF : 0;
        u64 p[24] = {(u64)a, (u64)b, n, x0, y * 19349663ull, amp, amp * 2 + 1, 100 - tint,
                     ((ton >> 16) & 255) * tint, ((ton >> 8) & 255) * tint, (ton & 255) * tint, 0};
        blur_g_asm(p);
        if (t % 3) blur_s_asm(p);   /* r481: four pixels at a time, the rest through the scalar loop */
        blur_m_asm(p);
        for (u64 i = 0; i < n; i++) {
            u32 want = (u32)ref_mix(a[i], ton, tint, amp, x0 + i, y) & 0xFFFFFF;   /* the alpha byte is dropped, as in every pass */
            if (b[i] != want) { printf("FAIL m t=%d i=%lu tint=%lu amp=%lu got=%06x want=%06x\n", t, i, tint, amp, b[i], want); bad++; break; }
        }
        free(a); free(b); cases++;
    }
    /* r466: the magic number modulus on its own: every odd d from 3 to 201 (amp 1..100) against `%`, on full 64-bit values */
    {
        long mbad = 0, mn = 0;
        for (u64 d = 3; d <= 201; d += 2) {
            u64 p[16] = {0}; p[6] = d; blur_g_asm(p);
            u64 magic = p[12], sh = p[13];
            for (long k = 0; k < 200000; k++) {
                u64 v = (k < 64) ? (u64)k : (k < 128) ? ~(u64)0 - (u64)(k - 64) : (((u64)rnd32() << 32) ^ rnd32());
                u64 hi = (u64)(((unsigned __int128)magic * v) >> 64);
                u64 q = (((v - hi) >> 1) + hi) >> sh;
                mn++;
                if (v - q * d != v % d) mbad++;
            }
        }
        if (mbad) { printf("FAIL g: %ld of %ld\n", mbad, mn); bad++; }
        cases += mn;
    }
    /* r465: one row of the dragged window, against the Firn loop (division per pixel) */
    for (int t = 0; t < 2000; t++) {
        long bw = 1 + rnd32() % 400, nw = 1 + rnd32() % 500;
        if (t % 3 == 0) nw = bw;
        long ox = (long)(rnd32() % 50) - 20;
        long c0 = ox + (long)(rnd32() % nw), c1 = c0 + 1 + (long)(rnd32() % (ox + nw - c0));
        u32 *src = malloc(bw * 4), *b = malloc((c1 - c0) * 4), *w2 = malloc((c1 - c0) * 4);
        for (long i = 0; i < bw; i++) src[i] = rnd32();
        for (long x = c0; x < c1; x++) w2[x - c0] = src[(x - ox) * bw / nw] & 0xFFFFFF;
        long num0 = (c0 - ox) * bw, q0 = num0 / nw, r0 = num0 - q0 * nw, qs = bw / nw, rs = bw - qs * nw;
        u64 p[8] = {(u64)src, (u64)b, (u64)(c1 - c0), (u64)q0, (u64)r0, (u64)qs, (u64)rs, (u64)nw};
        blur_d_asm(p);
        if (memcmp(b, w2, (c1 - c0) * 4)) { printf("FAIL d t=%d bw=%ld nw=%ld\n", t, bw, nw); bad++; }
        free(src); free(b); free(w2); cases++;
    }
    printf("blurasm: %ld cases, %d failed\n", cases, bad);
    return bad ? 1 : 0;
}
