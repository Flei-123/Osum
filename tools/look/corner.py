#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
"""tools/look/corner.py -- IS THE CORNER REALLY ROUND?

Round LOOK, sections C and D. "The corners are rounded now" is a claim
about pixels and it has three ways of being wrong: the corner is still
square, the corner is round but has no antialiasing (a staircase, which
at radius 6 is MORE conspicuous than a square corner), or it is round in
one place and square in another.

So this reads the DIAGONAL of a rectangle's top left corner and
classifies each pixel as background, antialiased, or face; and it reads
the PROFILE, the first face pixel of each of the first rows, which is
the quarter circle itself.

    a square corner   diagonal F F F F F F   profile 0 0 0 0 0 0
    radius 6          diagonal . . ~ ~ F F   profile 4 2 1 1 0 0

    corner.py <ppm> <x> <y> <face r g b> <bg r g b> [depth]
"""
import sys


def ppm(path):
    d = open(path, "rb").read()
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
    if len(a) < 9:
        print(__doc__)
        return 2
    W, H, data = ppm(a[0])
    x0, y0 = int(a[1]), int(a[2])
    face = (int(a[3]), int(a[4]), int(a[5]))
    bg = (int(a[6]), int(a[7]), int(a[8]))
    depth = int(a[9]) if len(a) > 9 else 10

    def px(x, y):
        o = ((y * W) + x) * 3
        return (data[o], data[o + 1], data[o + 2])

    def near(p, q, t=2):
        return max(abs(p[i] - q[i]) for i in range(3)) <= t

    out = []
    kinds = []
    for i in range(depth):
        p = px(x0 + i, y0 + i)
        out.append("%02x%02x%02x" % p)
        if near(p, face):
            kinds.append("F")
        elif near(p, bg):
            kinds.append(".")
        else:
            kinds.append("~")
    print("diagonal " + " ".join(out))
    print("kinds    " + " ".join(kinds))
    print("corner   background %d  antialiased %d  face %d"
          % (kinds.count("."), kinds.count("~"), kinds.count("F")))
    prof = []
    for r in range(depth):
        c = 0
        while c < depth + 6 and not near(px(x0 + c, y0 + r), face):
            c += 1
        prof.append(c)
    print("profile  " + " ".join(str(v) for v in prof))
    print("reach    %d" % max(prof))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
