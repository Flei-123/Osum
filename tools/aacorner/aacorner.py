#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
# tools/aacorner/aacorner.py -- ARE THE ROUND CORNERS AND THE RIM OF A POPUP ANTIALIASED?
#
#   aacorner.py <picture.ppm> <x> <y> <w> <h> <radius> [corners]
#
# (x, y, w, h) is the OUTER edge of a rounded surface (window, popup menu,
# tooltip, toast) with corner radius `radius`, a rim of one pixel and a fill.
# The tool takes the three pure colours from the straight edge (outside =
# the ground, rim, fill), renders the ideal rounded corner with 8x8
# supersampling (outer arc radius r, inner arc radius r-1, rim between)
# and compares it with the picture in the four corner squares:
#
#   px     pixels compared (corner squares, one pixel margin outside)
#   arc    pixels the outer arc crosses (ideal coverage 0 < c < 1)
#   soft   of those: pixels that are NOT one of the pure colours (they carry
#          coverage alpha) -- a staircase corner has none
#   max    largest channel difference to the ideal, 0..255
#   bad    pixels differing by more than 12 (a dark fringe between rim and
#          fill, a rim that ends in the air, a missing arc)
#
# Output (one line): `px=.. arc=.. soft=.. max=.. bad=..`
import sys

TOL = 3
SS = 8


def read_ppm(path):
    d = open(path, 'rb').read()
    pos = 0
    toks = []
    while len(toks) < 4:
        while d[pos:pos + 1].isspace():
            pos += 1
        if d[pos:pos + 1] == b'#':
            while d[pos:pos + 1] != b'\n':
                pos += 1
            continue
        s = pos
        while not d[pos:pos + 1].isspace():
            pos += 1
        toks.append(d[s:pos])
    pos += 1
    w, h = int(toks[1]), int(toks[2])
    return w, h, d[pos:pos + w * h * 3]


def near(a, b, tol=TOL):
    return all(abs(a[i] - b[i]) <= tol for i in range(3))


def inside(px, py, cx, cy, r):
    """Is the sample (px, py) inside the quarter disc around (cx, cy)?
    The caller only asks in the corner square, so a plain distance test."""
    dx = px - cx
    dy = py - cy
    return dx * dx + dy * dy <= r * r


def cover(x0, y0, cx, cy, r, sx, sy):
    """Coverage of the pixel [x0,x0+1) x [y0,y0+1) by the shape whose
    corner is the circle (cx, cy, r); (sx, sy) = direction of the corner
    (-1 = left/top, +1 = right/bottom). Samples on the straight side of the
    centre count as inside."""
    n = 0
    for j in range(SS):
        for i in range(SS):
            px = x0 + (i + 0.5) / SS
            py = y0 + (j + 0.5) / SS
            dx = (px - cx) * sx
            dy = (py - cy) * sy
            if dx <= 0 or dy <= 0:
                n += 1  # straight side: inside
            elif dx * dx + dy * dy <= r * r:
                n += 1
    return n / (SS * SS)


def mix(a, b, t):
    return tuple(a[i] * (1 - t) + b[i] * t for i in range(3))


def measure(img, x, y, w, h, r, which=None):
    iw, ih, px = img

    def get(cx, cy):
        if cx < 0 or cy < 0 or cx >= iw or cy >= ih:
            return (0, 0, 0)
        o = (cy * iw + cx) * 3
        return (px[o], px[o + 1], px[o + 2])

    total = arc = soft = bad = 0
    worst = 0
    corners = [
        ("tl", x, y, -1, -1),
        ("tr", x + w, y, 1, -1),
        ("bl", x, y + h, -1, 1),
        ("br", x + w, y + h, 1, 1),
    ]
    for name, ex, ey, sx, sy in corners:
        if which and name not in which:
            continue
        # pure colours from the straight edge, in the middle of the side
        # that carries this corner's rim (top for t*, bottom for b*)
        mx = x + w // 2
        if sy < 0:
            ground = get(mx, y - 2)
            rim = get(mx, y)
            fill = get(mx, y + 3)
        else:
            ground = get(mx, y + h + 1)
            rim = get(mx, y + h - 1)
            fill = get(mx, y + h - 4)
        # the corner circle centre of the outer and of the inner shape
        ccx = ex - sx * r
        ccy = ey - sy * r
        for j in range(-1, r + 1):
            for i in range(-1, r + 1):
                # pixel position, counted from the corner inwards
                pxx = ex - 1 - i if sx > 0 else ex + i
                pyy = ey - 1 - j if sy > 0 else ey + j
                co = cover(pxx, pyy, ccx, ccy, r, sx, sy)
                ci = cover(pxx, pyy, ccx, ccy, max(r - 1, 0), sx, sy)
                # the inner shape lies one pixel inside the straight edges
                # as well: a pixel on the edge row/column is rim, not fill
                inner_x = (pxx >= x + 1) and (pxx < x + w - 1)
                inner_y = (pyy >= y + 1) and (pyy < y + h - 1)
                if not (inner_x and inner_y):
                    ci = 0.0
                if r == 0:
                    ci = 1.0 if (inner_x and inner_y) else 0.0
                if co >= 1.0 and ci >= 1.0:
                    continue  # pure fill: nothing to judge (text may stand here)
                ideal = mix(ground, mix(rim, fill, ci), co)
                actual = get(pxx, pyy)
                err = max(abs(actual[k] - ideal[k]) for k in range(3))
                total += 1
                if err > worst:
                    worst = err
                if err > 12:
                    bad += 1
                if 0.0 < co < 1.0:
                    arc += 1
                    pure = (near(actual, ground) or near(actual, rim)
                            or near(actual, fill))
                    if not pure:
                        soft += 1
    return total, arc, soft, worst, bad


def main():
    if len(sys.argv) < 7:
        print(__doc__)
        sys.exit(2)
    img = read_ppm(sys.argv[1])
    x, y, w, h, r = (int(v) for v in sys.argv[2:7])
    which = sys.argv[7].split(",") if len(sys.argv) > 7 else None
    total, arc, soft, worst, bad = measure(img, x, y, w, h, r, which)
    print("px=%d arc=%d soft=%d max=%d bad=%d" % (total, arc, soft, int(worst), bad))


if __name__ == "__main__":
    main()
