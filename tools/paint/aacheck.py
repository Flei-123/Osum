#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
import os
import sys

HIER = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.normpath(os.path.join(HIER, "..", ".."))
sys.path.insert(0, os.path.join(ROOT, "tools", "ttf"))

import raster

try:
    from PIL import Image, ImageDraw, ImageFont
    HAT_PIL = True
except Exception:
    HAT_PIL = False


def raster_s(f, gid, px, S):
    schritt = 64 // S
    halb = schritt // 2
    scale = raster.scale_of(px, f.upm)
    edges = []
    for k in f.contours(gid):
        points = raster.flatten(k, scale)
        for i in range(len(points)):
            ax, ay = points[i]
            bx, by = points[(i + 1) % len(points)]
            if ay != by:
                edges.append((ax, ay, bx, by))
    if not edges:
        return 0, 0, 0, 0, []
    minx = min(min(k[0], k[2]) for k in edges)
    maxx = max(max(k[0], k[2]) for k in edges)
    miny = min(min(k[1], k[3]) for k in edges)
    maxy = max(max(k[1], k[3]) for k in edges)
    bx0, bx1 = minx >> 6, (maxx + 63) >> 6
    by0, by1 = miny >> 6, (maxy + 63) >> 6
    w, h = bx1 - bx0, by1 - by0
    if w <= 0 or h <= 0:
        return 0, 0, 0, 0, []
    voll = S * S
    a = [0] * (w * h)
    for py in range(by0, by1):
        cov = [0] * w
        for sub in range(S):
            ys = py * 64 + halb + sub * schritt
            schnitte = []
            for (ax, ay, bx, by) in edges:
                lo, hi = (ay, by) if ay < by else (by, ay)
                if ys < lo or ys >= hi:
                    continue
                xs = ax + raster.tdiv((bx - ax) * (ys - ay), (by - ay))
                schnitte.append((xs, 1 if by > ay else -1))
            if not schnitte:
                continue
            schnitte.sort(key=lambda t: t[0])
            wind = 0
            begin = 0
            for (xs, dz) in schnitte:
                vorher = wind
                wind += dz
                if vorher == 0 and wind != 0:
                    begin = xs
                elif vorher != 0 and wind == 0:
                    j0 = -((-(begin - halb)) // schritt)
                    j1 = -((-(xs - halb)) // schritt)
                    if j0 < bx0 * S:
                        j0 = bx0 * S
                    if j1 > bx1 * S:
                        j1 = bx1 * S
                    for j in range(j0, j1):
                        cov[(j // S) - bx0] += 1
        line = (by1 - 1 - py) * w
        for i in range(w):
            c = cov[i]
            if c > voll:
                c = voll
            a[line + i] = (c * 255 + voll // 2) // voll
    return w, h, bx0, by1, a


def deckung_osum(font, px, chars):
    g = font.glyphe_px(chars, px) if hasattr(font, "glyphe_px") \
        else font.glyphe(chars)
    field = []
    for r in range(g.h):
        for k in range(g.w):
            field.append(g.punkt(k, r))
    return g.w, g.h, g.left, g.top_2, field


def deckung_freetype(path_2, px, chars):
    f = ImageFont.truetype(path_2, px)
    m = f.getmask(chars, mode="L")
    w, h = m.size
    return w, h, [m.getpixel((x, y)) for y in range(h) for x in range(w)]


def stufen(field):
    return len(set(field))


def kantenstufen(w, h, field):
    best = 0
    for k in range(w):
        s = set(field[r * w + k] for r in range(h))
        if len(s) > best:
            best = len(s)
    return best


def abweichung(aw, ah, af, bw, bh, bf):
    def hole(f, w, h, x, y):
        if x < 0 or y < 0 or x >= w or y >= h:
            return 0
        return f[y * w + x]

    bestes = None
    for dy in range(-2, 3):
        for dx in range(-2, 3):
            sum_2 = 0
            groesst = 0
            n = 0
            x0 = min(0, dx)
            y0 = min(0, dy)
            x1 = max(aw, bw + dx)
            y1 = max(ah, bh + dy)
            for y in range(y0, y1):
                for x in range(x0, x1):
                    a = hole(af, aw, ah, x, y)
                    b = hole(bf, bw, bh, x - dx, y - dy)
                    d = abs(a - b)
                    sum_2 += d
                    if d > groesst:
                        groesst = d
                    n += 1
            if n == 0:
                continue
            value = (sum_2 / float(n), groesst, dx, dy)
            if bestes is None or value[0] < bestes[0]:
                bestes = value
    return bestes


def main():
    args = sys.argv[1:]
    path_2 = os.path.join(ROOT, "assets", "osum-sans.ttf")
    groessen = [11, 13, 16, 24]
    chars = "AOSgex8"
    i = 0
    rest = []
    while i < len(args):
        if args[i] == "--px":
            groessen = [int(v) for v in args[i + 1].split(",")]
            i += 2
        elif args[i] == "--chars":
            chars = args[i + 1]
            i += 2
        else:
            rest.append(args[i])
            i += 1
    if rest:
        path_2 = rest[0]

    data = open(path_2, "rb").read()
    print("PAINT-AA: %s, %d Oktette" % (os.path.relpath(path_2, ROOT),
                                        len(data)))
    if not HAT_PIL:
        print("   Pillow is missing -- the levels are counted, the "
              "Vergleich gegen FreeType nicht.")

    zusagen = 0
    error = 0
    all_stufen = []
    all_edges = []
    all_d = []
    all_max = []
    dichte = {}
    DICHTEN = [4, 8, 16]
    REF = 32

    for px in groessen:
        s = raster.Font(path_2, px)
        for c in chars:
            g = s.glyphe(ord(c))
            if g.w == 0 or g.h == 0:
                continue
            field = [g.punkt(k, r) for r in range(g.h) for k in range(g.w)]
            st = stufen(field)
            ka = kantenstufen(g.w, g.h, field)
            all_stufen.append(st)
            all_edges.append(ka)
            line = ("   px=%2d  '%s'  %2dx%-2d  stufen=%-3d kante=%-3d"
                     % (px, c, g.w, g.h, st, ka))
            if HAT_PIL:
                bw, bh, bf = deckung_freetype(path_2, px, c)
                mittel, groesst, dx, dy = abweichung(g.w, g.h, field,
                                                     bw, bh, bf)
                all_d.append(mittel)
                all_max.append(groesst)
                line += ("  |d|=%6.2f  max=%3d  (versatz %+d,%+d)"
                          % (mittel, groesst, dx, dy))
            gid = s.f.glyph_of(ord(c))
            rw, rh, _, _, rf = raster_s(s.f, gid, px, REF)
            for S in DICHTEN:
                aw2, ah2, _, _, af2 = raster_s(s.f, gid, px, S)
                if aw2 != rw or ah2 != rh:
                    continue
                e = dichte.setdefault(S, [0, 0, 0])
                for k in range(rw * rh):
                    d = abs(af2[k] - rf[k])
                    e[0] += d
                    e[1] += 1
                    if d > e[2]:
                        e[2] = d
            print(line)

    n = len(all_stufen)
    if n == 0:
        print("PAINT-AA: no glyph with an outline checked")
        return 1
    m_st = sum(all_stufen) / float(n)
    m_ka = sum(all_edges) / float(n)
    print("PAINT-AA: %d Zeichen  stufen: min=%d mittel=%.1f max=%d"
          "   kante: min=%d mittel=%.1f max=%d"
          % (n, min(all_stufen), m_st, max(all_stufen),
             min(all_edges), m_ka, max(all_edges)))

    if min(all_stufen) > 2:
        print("  OK    every glyph has more than two coverage levels "
              "(kleinstes: %d)" % min(all_stufen))
        zusagen += 1
    else:
        print("  FAIL  a glyph has only %d coverage levels -- that is "
              "eine Bitmaske" % min(all_stufen))
        error += 1

    if min(all_edges) >= 3:
        print("  OK    every edge carries at least three levels "
              "(kleinste: %d, mittlere: %.1f)"
              % (min(all_edges), m_ka))
        zusagen += 1
    else:
        print("  FAIL  an edge carries only %d levels" % min(all_edges))
        error += 1

    if HAT_PIL:
        md = sum(all_d) / float(len(all_d))
        print("PAINT-AA: gegen FreeType  |d| mittel=%.2f  "
              "schlechtestes Zeichen=%.2f  groesster Einzelfehler=%d"
              % (md, max(all_d), max(all_max)))
        if md < 45.0:
            print("  OK    the same glyph as FreeType, |d| = %.2f of "
                  "255 (%.2f Prozent, ueberwiegend Hinting)"
                  % (md, 100.0 * md / 255.0))
            zusagen += 1
        else:
            print("  FAIL  |d| against FreeType %.2f of 255 -- that is "
                  "kein Hinting mehr, das ist ein anderes Zeichen" % md)
            error += 1

    if dichte:
        print("PAINT-AA: Abtastdichte gegen %dx%d (Referenz, %d Stufen)"
              % (REF, REF, REF * REF + 1))
        for S in sorted(dichte):
            sum_2, n, groesst = dichte[S]
            print("   %2dx%-2d  stufen=%-4d  |d|=%6.3f von 255 (%.3f%%)"
                  "  max=%3d  ueber %d Bildpunkte"
                  % (S, S, S * S + 1, sum_2 / float(n),
                     100.0 * sum_2 / float(n) / 255.0, groesst, n))
        if 4 in dichte and 8 in dichte:
            v4 = dichte[4][0] / float(dichte[4][1])
            v8 = dichte[8][0] / float(dichte[8][1])
            print("   8x8 is %.2f times more accurate than 4x4" % (v4 / v8 if v8 else 0))

        if 4 in dichte:
            v4 = dichte[4][0] / float(dichte[4][1])
            if v4 < 5.0:
                print("  OK    4x4 is %.3f of 255 (%.3f percent) from "
                      "der exakten Flaechendeckung entfernt"
                      % (v4, 100.0 * v4 / 255.0))
                zusagen += 1
            else:
                print("  FAIL  4x4 is off by %.3f of 255" % v4)
                error += 1

    print("PAINT-AA: %d Zusagen, %d Fehler" % (zusagen, error))
    return 1 if error else 0


if __name__ == "__main__":
    sys.exit(main())
