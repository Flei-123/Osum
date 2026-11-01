#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
import sys


def ppm_read(p):
    d = open(p, 'rb').read()
    tok, i = [], 2
    while len(tok) < 3:
        while d[i:i + 1].isspace():
            i += 1
        if d[i:i + 1] == b'#':
            while d[i:i + 1] not in (b'\n', b''):
                i += 1
            continue
        j = i
        while not d[j:j + 1].isspace():
            j += 1
        tok.append(int(d[i:j])); i = j
    i += 1
    w, h, _ = tok
    return w, h, d[i:i + w * h * 3]


if __name__ == '__main__':
    w, h, px = ppm_read(sys.argv[1])

    def f(x, y):
        i = (y * w + x) * 3
        return (px[i], px[i + 1], px[i + 2])

    hg = f(5, 5)
    ytop = None
    for y in range(0, h // 2):
        if sum(1 for x in range(w // 4, 3 * w // 4, 8) if f(x, y) != hg) > 50:
            ytop = y
            break
    xr = None
    for x in range(w - 1, w // 4, -1):
        if f(x, ytop + 6) != hg:
            xr = x
            break
    print("Titelleiste y=%d, rechte Fensterkante x=%d" % (ytop, xr))

    CAPW = 60
    for n, name in ((2, "SCHLIESSEN"), (1, "MAXIMIEREN"), (0, "MINIMIEREN")):
        x1 = xr - (2 - n) * CAPW
        x0 = x1 - CAPW
        punkte = []
        for y in range(ytop, ytop + 60):
            for x in range(x0, x1):
                if 0 <= x < w and 0 <= y < h:
                    r, g, b = f(x, y)
                    if r + g + b > 330:
                        punkte.append((x, y))
        if not punkte:
            print("  %-11s NO stroke found (x %d..%d)" % (name, x0, x1))
            continue
        xs = sorted(set(p[0] for p in punkte))
        ys = sorted(set(p[1] for p in punkte))
        mx = (xs[0] + xs[-1]) / 2.0
        beide = 0
        only_left = 0
        only_right = 0
        for y in ys:
            l = sum(1 for p in punkte if p[1] == y and p[0] < mx)
            r = sum(1 for p in punkte if p[1] == y and p[0] > mx)
            if l and r:
                beide += 1
            elif l:
                only_left += 1
            elif r:
                only_right += 1
        print("  %-11s %3d points, %2dx%2d, rows: both %2d / left only %2d / right only %2d"
              % (name, len(punkte), xs[-1] - xs[0] + 1, ys[-1] - ys[0] + 1,
                 beide, only_left, only_right))
        if name == "SCHLIESSEN":
            if beide >= (len(ys) * 2) // 3:
                print("               -> a CROSS (both diagonals)")
            else:
                print("               -> ONLY ONE STROKE, the second diagonal is missing")
