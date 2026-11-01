#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
import sys
import math

EINS = 64
KAPPA = 35
CURVE_PARTS = 16


def tdiv(a, b):
    if b == 0:
        return 0
    q = abs(a) // abs(b)
    if (a < 0) != (b < 0):
        q = -q
    return q


def rdiv(a, b):
    if b == 0:
        return 0
    if b < 0:
        a, b = -a, -b
    if a >= 0:
        return (a + b // 2) // b
    return -((-a + b // 2) // b)


class Path:
    def __init__(self):
        self.pts = []
        self.edges_2 = []
        self.start = 0

    def nach(self, x, y):
        self.start = len(self.pts)
        self.pts.append((x, y))

    def line_2(self, x, y):
        self.pts.append((x, y))

    def kubik(self, c1x, c1y, c2x, c2y, x, y):
        ax, ay = self.pts[-1]
        n = CURVE_PARTS
        for i in range(1, n + 1):
            t = i
            u = n - i
            nnn = n * n * n
            bx = rdiv(u * u * u * ax + 3 * u * u * t * c1x
                      + 3 * u * t * t * c2x + t * t * t * x, nnn)
            by = rdiv(u * u * u * ay + 3 * u * u * t * c1y
                      + 3 * u * t * t * c2y + t * t * t * y, nnn)
            self.pts.append((bx, by))

    def arc(self, x0, y0, ex, ey, x1, y1):
        c1x = x0 + rdiv((ex - x0) * KAPPA, 64)
        c1y = y0 + rdiv((ey - y0) * KAPPA, 64)
        c2x = x1 + rdiv((ex - x1) * KAPPA, 64)
        c2y = y1 + rdiv((ey - y1) * KAPPA, 64)
        self.kubik(c1x, c1y, c2x, c2y, x1, y1)

    def zu(self):
        if len(self.pts) <= self.start + 1:
            return
        for i in range(self.start, len(self.pts) - 1):
            self._k(self.pts[i], self.pts[i + 1])
        self._k(self.pts[-1], self.pts[self.start])
        self.start = len(self.pts)

    def _k(self, a, b):
        if a[1] == b[1]:
            return
        self.edges_2.append((a[0], a[1], b[0], b[1]))


def rechteck(p, x, y, w, h):
    p.nach(x, y)
    p.line_2(x + w, y)
    p.line_2(x + w, y + h)
    p.line_2(x, y + h)
    p.zu()


def rundeck(p, x, y, w, h, r):
    r = min(r, w // 2, h // 2)
    if r <= 0:
        return rechteck(p, x, y, w, h)
    x1, y1 = x + w, y + h
    p.nach(x + r, y)
    p.line_2(x1 - r, y)
    p.arc(x1 - r, y, x1, y, x1, y + r)
    p.line_2(x1, y1 - r)
    p.arc(x1, y1 - r, x1, y1, x1 - r, y1)
    p.line_2(x + r, y1)
    p.arc(x + r, y1, x, y1, x, y1 - r)
    p.line_2(x, y + r)
    p.arc(x, y + r, x, y, x + r, y)
    p.zu()


def ellipse(p, cx, cy, rx, ry):
    p.nach(cx, cy - ry)
    p.arc(cx, cy - ry, cx + rx, cy - ry, cx + rx, cy)
    p.arc(cx + rx, cy, cx + rx, cy + ry, cx, cy + ry)
    p.arc(cx, cy + ry, cx - rx, cy + ry, cx - rx, cy)
    p.arc(cx - rx, cy, cx - rx, cy - ry, cx, cy - ry)
    p.zu()


def rastern(p, rule=0):
    if not p.edges_2:
        return None
    xs = [k[0] for k in p.edges_2] + [k[2] for k in p.edges_2]
    ys = [k[1] for k in p.edges_2] + [k[3] for k in p.edges_2]
    bx0, bx1 = min(xs) >> 6, (max(xs) + 63) >> 6
    by0, by1 = min(ys) >> 6, (max(ys) + 63) >> 6
    w, h = bx1 - bx0, by1 - by0
    if w <= 0 or h <= 0:
        return None
    out = bytearray(w * h)
    for py in range(by0, by1):
        cov = [0] * w
        for sub in range(4):
            ysamp = py * 64 + 8 + sub * 16
            cross = []
            for (ax, ay, bx, by) in p.edges_2:
                lo, hi, d = (ay, by, 1) if ay < by else (by, ay, -1)
                if lo <= ysamp < hi:
                    x = ax + rdiv((bx - ax) * (ysamp - ay), by - ay)
                    cross.append((x, d))
            cross.sort()
            if rule == 0:
                wind = 0
                anf = 0
                for (x, d) in cross:
                    v = wind
                    wind += d
                    if v == 0 and wind != 0:
                        anf = x
                    if v != 0 and wind == 0:
                        spanne(cov, anf, x, bx0, w)
            else:
                for i in range(0, len(cross) - 1, 2):
                    spanne(cov, cross[i][0], cross[i + 1][0], bx0, w)
        for c in range(w):
            v = min(cov[c], 16)
            out[(py - by0) * w + c] = (v * 255 + 8) // 16
    return (out, w, h, bx0, by0)


def spanne(cov, a, b, bx0, w):
    j0 = (a - 8 + 15) >> 4
    j1 = (b - 8 + 15) >> 4
    j0 = max(j0, bx0 * 4)
    j1 = min(j1, (bx0 + w) * 4)
    for j in range(j0, j1):
        c = (j >> 2) - bx0
        if 0 <= c < w:
            cov[c] += 1



def area_2(d):
    return sum(d[0]) / 255.0


SYM_TOL = 16


def sym_lr(d):
    buf, w, h = d[0], d[1], d[2]
    m = 0
    for y in range(h):
        for x in range(w // 2):
            a = buf[y * w + x]
            b = buf[y * w + (w - 1 - x)]
            m = max(m, abs(a - b))
    return m


def sym_ud(d):
    buf, w, h = d[0], d[1], d[2]
    m = 0
    for y in range(h // 2):
        for x in range(w):
            a = buf[y * w + x]
            b = buf[(h - 1 - y) * w + x]
            m = max(m, abs(a - b))
    return m


def loecher(d):
    buf, w, h = d[0], d[1], d[2]
    n = 0
    for y in range(1, h - 1):
        for x in range(1, w - 1):
            if buf[y * w + x] < 128:
                if (buf[(y - 1) * w + x] > 240 and buf[(y + 1) * w + x] > 240
                        and buf[y * w + x - 1] > 240
                        and buf[y * w + x + 1] > 240):
                    n += 1
    return n


def randbreite(d):
    buf, w, h = d[0], d[1], d[2]
    mit = 0
    for y in range(h):
        for x in range(w):
            v = buf[y * w + x]
            if 0 < v < 255:
                mit += 1
                break
    return mit


ERROR = []
LINES = []


def check_2(name, ist, soll, tol, einheit=""):
    ok = abs(ist - soll) <= tol
    LINES.append("  %-46s ist %8.2f%s  soll %8.2f  tol %.2f  %s"
                  % (name, ist, einheit, soll, tol, "OK" if ok else "FEHLER"))
    if not ok:
        ERROR.append(name)
    return ok


def main():
    print("VECTOR SELF-TEST -- basic shapes against target values from the geometry")
    print("=" * 78)

    print("\n[1] Rectangle: area exact, no anti-aliasing needed")
    for (w, h) in [(10, 10), (33, 17), (64, 64), (7, 100)]:
        p = Path()
        rechteck(p, 0, 0, w * EINS, h * EINS)
        d = rastern(p)
        check_2("Rechteck %dx%d Flaeche" % (w, h), area_2(d), w * h,
              0.01, " px")
        check_2("Rechteck %dx%d Loecher" % (w, h), loecher(d), 0, 0)

    print("\n[2] Circle: area against pi*r^2, symmetry, no hole")
    for r in [4, 8, 16, 32, 48]:
        p = Path()
        ellipse(p, r * EINS, r * EINS, r * EINS, r * EINS)
        d = rastern(p)
        soll = math.pi * r * r
        check_2("Kreis r=%d Flaeche" % r, area_2(d), soll, soll * 0.015, " px")
        check_2("Kreis r=%d Symmetrie links/rechts" % r, sym_lr(d), 0, SYM_TOL)
        check_2("Kreis r=%d Symmetrie oben/unten" % r, sym_ud(d), 0, SYM_TOL)
        check_2("Kreis r=%d Loecher" % r, loecher(d), 0, 0)
        without = 2 * r - randbreite(d)
        check_2("Kreis r=%d Zeilen ohne Saum" % r, without, 0.0,
              2.0 + r / 6.0, " Zeilen")

    print("\n[3] Ellipse: area against pi*rx*ry")
    for (rx, ry) in [(20, 10), (8, 30), (40, 12)]:
        p = Path()
        ellipse(p, rx * EINS, ry * EINS, rx * EINS, ry * EINS)
        d = rastern(p)
        soll = math.pi * rx * ry
        check_2("Ellipse %dx%d Flaeche" % (rx, ry), area_2(d), soll,
              soll * 0.02, " px")
        check_2("Ellipse %dx%d Symmetrie l/r" % (rx, ry), sym_lr(d), 0,
              2 * SYM_TOL)

    print("\n[4] Rundeck: Flaeche = w*h - (4-pi)*r^2")
    for (w, h, r) in [(40, 24, 6), (64, 64, 16), (100, 30, 8), (48, 48, 24)]:
        p = Path()
        rundeck(p, 0, 0, w * EINS, h * EINS, r * EINS)
        d = rastern(p)
        soll = w * h - (4 - math.pi) * r * r
        check_2("Rundeck %dx%d r=%d Flaeche" % (w, h, r), area_2(d), soll,
              soll * 0.02, " px")
        check_2("Rundeck %dx%d r=%d Symmetrie l/r" % (w, h, r), sym_lr(d), 0, SYM_TOL)
        check_2("Rundeck %dx%d r=%d Symmetrie o/u" % (w, h, r), sym_ud(d), 0, SYM_TOL)
        check_2("Rundeck %dx%d r=%d Loecher" % (w, h, r), loecher(d), 0, 0)

    p = Path()
    rundeck(p, 0, 0, 48 * EINS, 48 * EINS, 24 * EINS)
    a1 = area_2(rastern(p))
    p = Path()
    ellipse(p, 24 * EINS, 24 * EINS, 24 * EINS, 24 * EINS)
    a2 = area_2(rastern(p))
    check_2("Rundeck r=w/2 ist der Kreis", abs(a1 - a2), 0, 1.0, " px")

    print("\n[5] Target size: rasterised twice is four times the area")
    for r in [8, 16]:
        p = Path()
        ellipse(p, r * EINS, r * EINS, r * EINS, r * EINS)
        a1 = area_2(rastern(p))
        p = Path()
        r2 = r * 2
        ellipse(p, r2 * EINS, r2 * EINS, r2 * EINS, r2 * EINS)
        a2 = area_2(rastern(p))
        check_2("Kreis r=%d -> r=%d Flaechenverhaeltnis" % (r, r2),
              a2 / a1, 4.0, 0.06)

    print("\n[6] Subpixel: an edge shifted by half a point")
    p = Path()
    rechteck(p, 0, 0, 10 * EINS, 10 * EINS)
    a1 = area_2(rastern(p))
    p = Path()
    rechteck(p, EINS // 2, 0, 10 * EINS, 10 * EINS)
    a2 = area_2(rastern(p))
    check_2("Rechteck um 1/2 px versetzt: gleiche Flaeche", abs(a1 - a2),
          0, 0.6, " px")

    print("\n[7] Fuellregeln: Ring, innen hohl")
    p = Path()
    ellipse(p, 32 * EINS, 32 * EINS, 30 * EINS, 30 * EINS)
    ellipse(p, 32 * EINS, 32 * EINS, 15 * EINS, 15 * EINS)
    d_nz = rastern(p, 0)
    d_eo = rastern(p, 1)
    soll_nz = math.pi * 30 * 30
    soll_eo = math.pi * (30 * 30 - 15 * 15)
    check_2("Nichtnull: voller Kreis", area_2(d_nz), soll_nz,
          soll_nz * 0.02, " px")
    check_2("Gerade-Ungerade: Ring mit Loch", area_2(d_eo), soll_eo,
          soll_eo * 0.02, " px")

    print("\n[8] Strokes: two strokes in ONE path (the cross)")

    def wurzel(v):
        if v <= 0:
            return 0
        x = v
        y = (x + 1) // 2
        n = 0
        while y < x and n < 40:
            x = y
            y = (x + v // x) // 2
            n += 1
        return x

    def stroke(p, pts, hb):
        n = len(pts)
        for page in range(2):
            for k in range(n - 1):
                a, b = (k, k + 1) if page == 0 else (n - 1 - k, n - 2 - k)
                ax, ay = pts[a]
                bx, by = pts[b]
                dx, dy = bx - ax, by - ay
                l = wurzel(dx * dx + dy * dy)
                if l <= 0:
                    continue
                nx = -dy * hb // l
                ny = dx * hb // l
                if k == 0 and page == 0:
                    p.nach(ax + nx, ay + ny)
                else:
                    p.line_2(ax + nx, ay + ny)
                p.line_2(bx + nx, by + ny)
        p.zu()

    p = Path()
    stroke(p, [(0, 0), (20 * EINS, 0)], EINS)
    a1 = area_2(rastern(p))
    check_2("Ein waagerechter Strich 20x2", a1, 40.0, 2.0, " px")

    p = Path()
    d = 20 * EINS
    stroke(p, [(0, 0), (d, d)], EINS)
    stroke(p, [(d, 0), (0, d)], EINS)
    dk = rastern(p)
    soll = 2 * (20 * 1.4142 * 2) - 8
    check_2("Kreuz aus zwei Strichen: Flaeche", area_2(dk), soll,
          soll * 0.12, " px")
    def sym_lr_kern(d):
        buf, w, h = d[0], d[1], d[2]
        m = 0
        for y in range(2, h - 2):
            for x in range(2, w // 2):
                m = max(m, abs(buf[y * w + x] - buf[y * w + (w - 1 - x)]))
        return m

    check_2("Kreuz: Symmetrie l/r (ohne Spitzen)", sym_lr_kern(dk), 0,
          SYM_TOL)
    check_2("Kreuz: Symmetrie oben/unten", sym_ud(dk), 0, SYM_TOL)
    p = Path()
    stroke(p, [(0, 0), (d, d)], EINS)
    a_einer = area_2(rastern(p))
    check_2("Ein Strich ist halb so viel wie zwei", area_2(dk) / a_einer,
          2.0, 0.25)

    print("\n" + "=" * 78)
    for z in LINES:
        print(z)
    print("=" * 78)
    n = len(LINES)
    if ERROR:
        print("ERGEBNIS: %d von %d Pruefungen FEHLGESCHLAGEN" % (len(ERROR), n))
        for f in ERROR:
            print("   - " + f)
        return 1
    print("RESULT: all %d checks passed" % n)
    return 0


if __name__ == "__main__":
    sys.exit(main())
