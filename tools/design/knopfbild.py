#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
import sys, zlib, struct

SK = 2
D = 10 * SK
ZOOM = 20


def png(path_2, w, h, px):
    raw = b''.join(b'\x00' + bytes(px[y * w * 3:(y + 1) * w * 3])
                   for y in range(h))
    def chunk(t, d):
        c = struct.pack('>I', len(d)) + t + d
        return c + struct.pack('>I', zlib.crc32(t + d) & 0xffffffff)
    open(path_2, 'wb').write(
        b'\x89PNG\r\n\x1a\n'
        + chunk(b'IHDR', struct.pack('>IIBBBBB', w, h, 8, 2, 0, 0, 0))
        + chunk(b'IDAT', zlib.compress(raw, 9)) + chunk(b'IEND', b''))


def empty_3(n):
    return [0] * (n * n * 3)


def deckung_direkt(k):
    f = [[0] * D for _ in range(D)]
    sb = SK
    if k == 'min':
        for t in range(sb):
            for x in range(D):
                if 0 <= D // 2 + t < D:
                    f[D // 2 + t][x] = 1
    elif k == 'max':
        for t in range(sb):
            for x in range(D):
                f[t][x] = 1
                f[D - 1 - t][x] = 1
            for y in range(D):
                f[y][t] = 1
                f[y][D - 1 - t] = 1
    else:
        kn = D - (sb - 1)
        off = (D - (kn + sb - 1)) // 2
        for k in range(kn):
            for t in range(sb):
                f[off + k][off + k + t] = 1
                f[off + k][off + kn - 1 - k + t] = 1
    return f


def deckung_vektor():
    sb = 3 * SK / 2.0
    f = [[0] * D for _ in range(D)]

    def umriss(x0, y0, x1, y1):
        dx, dy = x1 - x0, y1 - y0
        ln = (dx * dx + dy * dy) ** 0.5
        nx, ny = -dy / ln * sb / 2, dx / ln * sb / 2
        return [(x0 + nx, y0 + ny), (x1 + nx, y1 + ny),
                (x1 - nx, y1 - ny), (x0 - nx, y0 - ny)]

    def in_(poly, px, py):
        w = 0
        for i in range(len(poly)):
            ax, ay = poly[i]
            bx, by = poly[(i + 1) % len(poly)]
            if ay <= py < by or by <= py < ay:
                t = (py - ay) / (by - ay)
                if ax + t * (bx - ax) > px:
                    w += 1 if by > ay else -1
        return w != 0

    for u in (umriss(0, 0, D - 1, D - 1), umriss(D - 1, 0, 0, D - 1)):
        for y in range(D):
            for x in range(D):
                if in_(u, x + 0.5, y + 0.5):
                    f[y][x] += 1
    return f


def paint(path_2, felder, title_2):
    n = len(felder)
    width_2 = n * (D + 2) * ZOOM
    height_2 = (D + 2) * ZOOM
    px = [255] * (width_2 * height_2 * 3)
    for fi, f in enumerate(felder):
        ox = fi * (D + 2) * ZOOM + ZOOM
        for y in range(D):
            for x in range(D):
                v = f[y][x]
                if v == 0:
                    r, g, b = 245, 245, 245
                elif v == 1:
                    r, g, b = 20, 20, 20
                else:
                    r, g, b = 220, 30, 30
                for dy in range(ZOOM):
                    for dx in range(ZOOM):
                        if dx == 0 or dy == 0:
                            rr, gg, bb = (r + 90) // 2, (g + 90) // 2, (b + 90) // 2
                        else:
                            rr, gg, bb = r, g, b
                        X = ox + x * ZOOM + dx
                        Y = ZOOM + y * ZOOM + dy
                        i = (Y * width_2 + X) * 3
                        px[i], px[i + 1], px[i + 2] = rr, gg, bb
    png(path_2, width_2, height_2, px)
    print("  %-46s %s" % (title_2, path_2))


if __name__ == '__main__':
    aus = sys.argv[1] if len(sys.argv) > 1 else '/tmp/knopfbild'
    import os
    os.makedirs(aus, exist_ok=True)
    print("KNOPFBILD -- Skalierung %d (Justins Tafel: S2), %d px, Zoom %d"
          % (SK, D, ZOOM))
    print()
    v = deckung_vektor()
    mehr = sum(1 for r in v for c in r if c > 1)
    paint(aus + '/vorher-x-vektor.png', [v],
          "VORHER: X aus zwei Strichen (rot = doppelt)")
    print("        doppelt gedeckte Bildpunkte: %d" % mehr)
    d = [deckung_direkt(k) for k in ('min', 'max', 'close')]
    paint(aus + '/nachher-drei-knoepfe.png', d,
          "NACHHER: min / max / schliessen, direkt gemalt")
    mehr2 = sum(1 for f in d for r in f for c in r if c > 1)
    print("        doppelt gedeckte Bildpunkte: %d" % mehr2)
    print()
    print("BEFUND: vorher %d doppelte, nachher %d." % (mehr, mehr2))
    sys.exit(0 if mehr2 == 0 else 1)
