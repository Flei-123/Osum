#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
"""tools/look/inkbox.py -- HOW MANY PIXELS OF A RECTANGLE ARE NOT THE
BACKGROUND.

Round LOOK, section B. "There is a symbol in the taskbar" is a claim
about pixels, and the two ways of getting it wrong are opposite: an
empty box passes a test that only checks the colours around it, and a
solid box passes a test that only counts non-background pixels. So this
prints BOTH numbers -- how many pixels differ from the given background
and what fraction of the box that is -- and the caller asserts a RANGE.
A 16 x 16 glyph of a line drawing covers between a tenth and a half of
its box; 0 means nothing was drawn and 256 means somebody filled it.

    inkbox.py <ppm> <x> <y> <w> <h> <r> <g> <b> [tolerance]
      -> "ink <n> of <w*h>  (<permille> permille)"
"""
import sys


def ppm(path):
    d = open(path, "rb").read()
    if not d.startswith(b"P6"):
        raise SystemExit("not a P6 PPM: %s" % path)
    f = []
    at = 2
    while len(f) < 3:
        while at < len(d) and d[at:at + 1].isspace():
            at += 1
        if d[at:at + 1] == b"#":
            while d[at:at + 1] not in (b"\n", b""):
                at += 1
            continue
        a = at
        while at < len(d) and not d[at:at + 1].isspace():
            at += 1
        f.append(int(d[a:at]))
    at += 1
    return f[0], f[1], d[at:]


def main(a):
    if len(a) < 8:
        print(__doc__)
        return 2
    w, h, data = ppm(a[0])
    x, y, bw, bh = int(a[1]), int(a[2]), int(a[3]), int(a[4])
    bg = (int(a[5]), int(a[6]), int(a[7]))
    tol = int(a[8]) if len(a) > 8 else 6
    n = 0
    for yy in range(y, y + bh):
        if yy < 0 or yy >= h:
            continue
        for xx in range(x, x + bw):
            if xx < 0 or xx >= w:
                continue
            o = (yy * w + xx) * 3
            p = (data[o], data[o + 1], data[o + 2])
            if max(abs(p[i] - bg[i]) for i in range(3)) > tol:
                n += 1
    tot = bw * bh
    print("ink %d of %d  (%d permille)" % (n, tot, (n * 1000) // max(tot, 1)))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
