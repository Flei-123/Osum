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


def messen(px, w, h, bx, by, bw, bh, name):
    def f(x, y):
        i = (y * w + x) * 3
        return (px[i], px[i + 1], px[i + 2])

    zaehl = {}
    for y in range(by, min(by + bh, h)):
        for x in range(bx, min(bx + bw, w)):
            zaehl[f(x, y)] = zaehl.get(f(x, y), 0) + 1
    if not zaehl:
        print("  %s: Rechteck liegt ausserhalb" % name)
        return False
    reason = max(zaehl.items(), key=lambda kv: kv[1])[0]

    def changed(c):
        return (abs(c[0] - reason[0]) + abs(c[1] - reason[1])
                + abs(c[2] - reason[2])) > 90

    pts = [(x, y)
           for y in range(by, min(by + bh, h))
           for x in range(bx, min(bx + bw, w))
           if changed(f(x, y))]
    if not pts:
        print("  %-14s no text/symbol found in the button" % name)
        return False
    xs = [p[0] for p in pts]; ys = [p[1] for p in pts]
    left = min(xs) - bx
    right = (bx + bw - 1) - max(xs)
    top_2 = min(ys) - by
    bottom = (by + bh - 1) - max(ys)
    dx = abs(left - right)
    dy = abs(top_2 - bottom)
    ok = dx <= 1 and dy <= 1
    print("  %-14s Knopf %dx%d   links %3d rechts %3d (Diff %d)   "
          "oben %3d unten %3d (Diff %d)   %s"
          % (name, bw, bh, left, right, dx, top_2, bottom, dy,
             "MITTIG" if ok else "NICHT MITTIG"))
    return ok


if __name__ == '__main__':
    src = sys.argv[1]
    w, h, px = ppm_read(src)
    if len(sys.argv) >= 6:
        bx, by, bw, bh = (int(v) for v in sys.argv[2:6])
        name = sys.argv[6] if len(sys.argv) > 6 else "Knopf"
        sys.exit(0 if messen(px, w, h, bx, by, bw, bh, name) else 1)
    print("Aufruf: textmitte.py <ppm> <x> <y> <w> <h> [name]")
