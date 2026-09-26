#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
"""tools/ttf/fuiraster.py -- fUi's glyph rasteriser, SECOND VERSION.

ROUND FUI-TEXT (24.09.2026): since this round every letter a Ring 3
program draws comes from fUi's font engine (`kernel/user/fuiglyph.fi` ->
vendor/firn/lib/font/ttf.fi + lib/font/raster.fi), not from the kernel's
4x4-sampling rasteriser (`kernel/gfx/ttf.fi`, whose second version is
`raster.py` next to this file). A screenshot of Ring 3 text is therefore
checked against THIS file. Since round FUI-KERNTEXT (26.09.2026) the
kernel's own text (titles, terminal, WIG_GLYPH) is fUi ink as well
(kernel/gfx/fuiink.fi), and `raster.py` hands every glyph to `glyph`
below; its 4x4 rasteriser is the second version of the FALLBACK only.

Every computation below is written the way it stands in Firn, in the same
order: Python floats are IEEE doubles like Firn's f64, so the same
operations in the same order give the same bits. That is the whole point
-- the comparison stays EXACT (tolerance 0), it is not loosened.

  * outlines: ttf.fi `simple` / `emit_contour` / `composite`, with the
    2x2 matrix and the implied on-curve midpoints
  * curves: raster.fi `raster_quad`, flattened with `steps_for`
  * fill: raster.fi `accumulate` + `span` (signed area accumulation) and
    `raster_finish` (running sum, absolute value, clipped at 1)
  * the glyph window: kernel/user/fuiglyph.fi `glyph_into` -- bbox from
    the glyf header times px/upem, floor/ceil, coverage * 255 + 0.5
  * advance and kerning: the kernel's integer formula, so the layout is
    the same as before (fuiglyph.fi says why)
"""
import os
import struct
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import raster as kern  # noqa: E402  the reader, cmap, kern, f26, Glyphe


def _u8(d, o):
    return d[o]


def _u16(d, o):
    return (d[o] << 8) | d[o + 1]


def _s16(d, o):
    v = _u16(d, o)
    return v - 65536 if v >= 32768 else v


def _ftrunc(x):
    if x != x:
        return 0.0
    if x > 9.0e15:
        return 9.0e15
    if x < 0.0 - 9.0e15:
        return 0.0 - 9.0e15
    return float(int(x))


def _ffloor(x):
    t = _ftrunc(x)
    if t > x:
        return t - 1.0
    return t


def _fceil(x):
    t = _ftrunc(x)
    if t < x:
        return t + 1.0
    return t


def _fsqrt(x):
    if x != x or x <= 0.0:
        return 0.0
    g = 1.0
    while g * g < x:
        g = g * 2.0
    for _ in range(8):
        g = 0.5 * (g + x / g)
    return g


def _steps_for(d):
    if d != d or d <= 0.0:
        return 1
    n = int(_fsqrt(d * 3.5) + 1.0)
    if n < 1:
        n = 1
    if n > 400:
        n = 400
    return n


class Raster:
    """raster.fi `Raster`, with a plain list instead of a cell buffer."""

    def __init__(self, ox, oy, w, h):
        self.ox, self.oy, self.w, self.h = ox, oy, w, h
        self.stride = w + 2
        self.acc = [0.0] * (self.stride * h)

    def cell_add(self, row, col, v):
        if col < 0 or col >= self.stride:
            return
        i = row * self.stride + col
        self.acc[i] = self.acc[i] + v

    def span(self, row, lx, rx, d):
        x0floor = _ffloor(lx)
        x0i = int(x0floor)
        x1ceil = _fceil(rx)
        x1i = int(x1ceil)
        if x1i <= x0i + 1:
            xmf = 0.5 * (lx + rx) - x0floor
            self.cell_add(row, x0i, d - d * xmf)
            self.cell_add(row, x0i + 1, d * xmf)
            return
        s = 1.0 / (rx - lx)
        x0f = lx - x0floor
        a0 = 0.5 * s * (1.0 - x0f) * (1.0 - x0f)
        x1f = rx - x1ceil + 1.0
        am = 0.5 * s * x1f * x1f
        self.cell_add(row, x0i, d * a0)
        if x1i == x0i + 2:
            self.cell_add(row, x0i + 1, d * (1.0 - a0 - am))
        else:
            a1 = s * (1.5 - x0f)
            self.cell_add(row, x0i + 1, d * (a1 - a0))
            xi = x0i + 2
            while xi < x1i - 1:
                self.cell_add(row, xi, d * s)
                xi = xi + 1
            a2 = a1 + float(x1i - x0i - 3) * s
            self.cell_add(row, x1i - 1, d * (1.0 - a2 - am))
        self.cell_add(row, x1i, d * am)

    def accumulate(self, p0x, p0y, p1x, p1y):
        if p0y == p1y:
            return
        if p0x != p0x or p0y != p0y or p1x != p1x or p1y != p1y:
            return
        dirn = 1.0
        ax, ay, bx, by = p0x, p0y, p1x, p1y
        if p0y > p1y:
            dirn = 0.0 - 1.0
            ax, ay, bx, by = p1x, p1y, p0x, p0y
        hf = float(self.h)
        if by <= 0.0 or ay >= hf:
            return
        dxdy = (bx - ax) / (by - ay)
        ys = ay
        xs = ax
        if ys < 0.0:
            xs = ax + dxdy * (0.0 - ay)
            ys = 0.0
        ye = by
        if ye > hf:
            ye = hf
        if ye <= ys:
            return
        wf = float(self.w)
        x = xs
        yrow = int(_ffloor(ys))
        ylast = int(_fceil(ye))
        while yrow < ylast:
            rowtop = float(yrow)
            ytop = rowtop
            if ys > ytop:
                ytop = ys
            ybot = rowtop + 1.0
            if ye < ybot:
                ybot = ye
            dy = ybot - ytop
            if dy > 0.0:
                xnext = x + dxdy * dy
                if 0 <= yrow < self.h:
                    d = dy * dirn
                    lx, rx = x, xnext
                    if lx > rx:
                        lx, rx = xnext, x
                    if lx < 0.0:
                        lx = 0.0
                    if rx < 0.0:
                        rx = 0.0
                    if lx > wf:
                        lx = wf
                    if rx > wf:
                        rx = wf
                    self.span(yrow, lx, rx, d)
                x = xnext
            yrow = yrow + 1

    def line(self, ax, ay, bx, by):
        self.accumulate(ax - self.ox, ay - self.oy, bx - self.ox, by - self.oy)

    def finish(self):
        """Running sum per row, absolute value, clipped at one."""
        cov = []
        for y in range(self.h):
            acc = 0.0
            row = y * self.stride
            for x in range(self.w):
                acc = acc + self.acc[row + x]
                v = acc
                if v < 0.0:
                    v = 0.0 - v
                if v > 1.0:
                    v = 1.0
                cov.append(v)
        return cov


def _ffabs(x):
    return 0.0 - x if x < 0.0 else x


# raster.fi writes `ffabs(a) + ffabs(b) + ffabs(c) + ffabs(d)` -- left to
# right, which is what Python does with `+` as well.
def _qd(x0, y0, cx, cy, x1, y1):
    return _ffabs(cx - x0) + _ffabs(cy - y0) + _ffabs(x1 - cx) + \
        _ffabs(y1 - cy)



def _devx(px, py, ox, scale, m00, m10, tdx):
    return ox + (px * m00 + py * m10 + tdx) * scale


def _devy(px, py, oy, scale, m01, m11, tdy):
    return oy - (px * m01 + py * m11 + tdy) * scale


class Outline:
    """ttf.fi `outline_at` and what it calls, on a `raster.Ttf`."""

    def __init__(self, f):
        self.f = f
        self.d = f.d

    def glyph_range(self, gid):
        if gid >= self.f.numglyphs:
            return None
        a, b = self.f.loca(gid), self.f.loca(gid + 1)
        if b <= a:
            return None
        return self.f.tab["glyf"][0] + a

    def bbox(self, gid):
        o = self.glyph_range(gid)
        if o is None:
            return None
        d = self.d
        return (_s16(d, o + 2), _s16(d, o + 4), _s16(d, o + 6), _s16(d, o + 8))

    def outline_at(self, gid, r, ox, oy, scale, m00, m01, m10, m11,
                   tdx, tdy, depth):
        if depth > 6:
            return False
        o = self.glyph_range(gid)
        if o is None:
            return True
        nc = _s16(self.d, o)
        if nc < 0:
            return self.composite(o + 10, r, ox, oy, scale,
                                  m00, m01, m10, m11, tdx, tdy, depth)
        return self.simple(o, nc, r, ox, oy, scale,
                           m00, m01, m10, m11, tdx, tdy)

    def simple(self, o, ncont, r, ox, oy, scale, m00, m01, m10, m11,
               tdx, tdy):
        d = self.d
        if ncont == 0:
            return True
        ends = o + 10
        npts = _u16(d, ends + (ncont - 1) * 2) + 1
        cends = [_u16(d, ends + i * 2) for i in range(ncont)]
        ilen = _u16(d, ends + ncont * 2)
        p = ends + ncont * 2 + 2 + ilen
        fl = []
        while len(fl) < npts:
            f = _u8(d, p)
            p += 1
            fl.append(f)
            if f & 8:
                rep = _u8(d, p)
                p += 1
                while rep > 0 and len(fl) < npts:
                    fl.append(f)
                    rep -= 1
        xs, x = [], 0
        for f in fl:
            if f & 2:
                dd = _u8(d, p)
                p += 1
                x = x + dd if (f & 16) else x - dd
            elif not (f & 16):
                x += _s16(d, p)
                p += 2
            xs.append(x)
        ys, y = [], 0
        for f in fl:
            if f & 4:
                dd = _u8(d, p)
                p += 1
                y = y + dd if (f & 32) else y - dd
            elif not (f & 32):
                y += _s16(d, p)
                p += 2
            ys.append(y)
        pts = [(xs[i], ys[i], fl[i]) for i in range(npts)]
        start = 0
        for last in cends:
            if start <= last < npts:
                self.emit_contour(r, pts, start, last, ox, oy, scale,
                                  m00, m01, m10, m11, tdx, tdy)
            start = last + 1
        return True

    def emit_contour(self, r, pts, first, last, ox, oy, scale,
                     m00, m01, m10, m11, tdx, tdy):
        n = last - first + 1
        if n < 2:
            return

        def dx_(px, py):
            return _devx(px, py, ox, scale, m00, m10, tdx)

        def dy_(px, py):
            return _devy(px, py, oy, scale, m01, m11, tdy)

        def q(ax, ay, cx, cy, bx, by):
            _quad(r, dx_(ax, ay), dy_(ax, ay), dx_(cx, cy), dy_(cx, cy),
                  dx_(bx, by), dy_(bx, by))

        def ln(ax, ay, bx, by):
            r.line(dx_(ax, ay), dy_(ax, ay), dx_(bx, by), dy_(bx, by))

        if pts[first][2] & 1:
            sx, sy = float(pts[first][0]), float(pts[first][1])
            startoff = 1
        elif pts[last][2] & 1:
            sx, sy = float(pts[last][0]), float(pts[last][1])
            startoff = 0
        else:
            sx = 0.5 * (float(pts[first][0]) + float(pts[last][0]))
            sy = 0.5 * (float(pts[first][1]) + float(pts[last][1]))
            startoff = 0
        curx, cury = sx, sy
        haveq = False
        qx = qy = 0.0
        for i in range(n):
            idx = first + ((i + startoff) % n)
            px, py = float(pts[idx][0]), float(pts[idx][1])
            on = (pts[idx][2] & 1) != 0
            if on:
                if haveq:
                    q(curx, cury, qx, qy, px, py)
                    haveq = False
                else:
                    ln(curx, cury, px, py)
                curx, cury = px, py
            else:
                if haveq:
                    mx = 0.5 * (qx + px)
                    my = 0.5 * (qy + py)
                    q(curx, cury, qx, qy, mx, my)
                    curx, cury = mx, my
                qx, qy = px, py
                haveq = True
        if haveq:
            q(curx, cury, qx, qy, sx, sy)
        else:
            ln(curx, cury, sx, sy)

    def composite(self, p, r, ox, oy, scale, m00, m01, m10, m11,
                  tdx, tdy, depth):
        d = self.d
        more = True
        okall = True
        while more:
            flags = _u16(d, p)
            sub = _u16(d, p + 2)
            p += 4
            if flags & 1:
                a1, a2 = _s16(d, p), _s16(d, p + 2)
                p += 4
            else:
                a1 = struct.unpack_from(">b", d, p)[0]
                a2 = struct.unpack_from(">b", d, p + 1)[0]
                p += 2
            s00, s01, s10, s11 = 1.0, 0.0, 0.0, 1.0
            if flags & 8:
                s00 = float(_s16(d, p)) / 16384.0
                s11 = s00
                p += 2
            elif flags & 64:
                s00 = float(_s16(d, p)) / 16384.0
                s11 = float(_s16(d, p + 2)) / 16384.0
                p += 4
            elif flags & 128:
                s00 = float(_s16(d, p)) / 16384.0
                s01 = float(_s16(d, p + 2)) / 16384.0
                s10 = float(_s16(d, p + 4)) / 16384.0
                s11 = float(_s16(d, p + 6)) / 16384.0
                p += 8
            ddx = ddy = 0.0
            if flags & 2:
                ddx, ddy = float(a1), float(a2)
            n00 = s00 * m00 + s01 * m10
            n01 = s00 * m01 + s01 * m11
            n10 = s10 * m00 + s11 * m10
            n11 = s10 * m01 + s11 * m11
            ndx = tdx + ddx * m00 + ddy * m10
            ndy = tdy + ddx * m01 + ddy * m11
            if not self.outline_at(sub, r, ox, oy, scale, n00, n01, n10,
                                   n11, ndx, ndy, depth + 1):
                okall = False
            more = (flags & 32) != 0
        return okall


def _quad(r, x0, y0, cx, cy, x1, y1):
    n = _steps_for(_qd(x0, y0, cx, cy, x1, y1))
    px, py = x0, y0
    i = 1
    while i <= n:
        t = float(i) / float(n)
        mt = 1.0 - t
        qx = mt * mt * x0 + 2.0 * mt * t * cx + t * t * x1
        qy = mt * mt * y0 + 2.0 * mt * t * cy + t * t * y1
        r.line(px, py, qx, qy)
        px, py = qx, qy
        i = i + 1


def glyph(f, gid, px):
    """kernel/user/fuiglyph.fi `glyph_into`, line for line."""
    sc16 = kern.scale_of(px, f.upm)
    adv = kern.f26(f.advance(gid), sc16)
    ol = Outline(f)
    sc = float(px) / float(f.upm)
    w = h = bx0 = by1 = 0
    bb = ol.bbox(gid)
    if bb is not None and bb[2] > bb[0] and bb[3] > bb[1]:
        x0, y0, x1, y1 = bb
        bx0 = int(_ffloor(float(x0) * sc))
        bx1 = int(_fceil(float(x1) * sc))
        by0 = int(_ffloor(float(y0) * sc))
        by1 = int(_fceil(float(y1) * sc))
        w = bx1 - bx0
        h = by1 - by0
    if w < 0 or h < 0 or w > 256 or h > 256:
        return None                       # the kernel draws it instead
    a = bytearray(w * h)
    if w * h > 0:
        r = Raster(float(bx0), float(0 - by1), w, h)
        ol.outline_at(gid, r, 0.0, 0.0, sc, 1.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0)
        cov = r.finish()
        for i, c in enumerate(cov):
            if c < 0.0:
                c = 0.0
            if c > 1.0:
                c = 1.0
            a[i] = int(c * 255.0 + 0.5)
    return kern.Glyphe(w, h, bx0, by1, adv, a)


class Schrift(kern.Schrift):
    """`raster.Schrift` with fUi's ink. Layout (`stellen`, `laufweite`,
    ascender ...) is inherited unchanged -- it IS unchanged."""

    def glyphe(self, c):
        if c in self.speicher:
            return self.speicher[c]
        gid = self.f.glyph_of(c)
        g = glyph(self.f, gid, self.px)
        if g is None:
            g = kern.raster_kern(self.f, gid, self.px)
        self.speicher[c] = g
        return g


def main(argv):
    if len(argv) >= 4 and argv[0] == "glyphe":
        s = Schrift(argv[1], int(argv[2]))
        g = s.glyphe(ord(argv[3]))
        print("w=%d h=%d links=%d oben=%d adv26=%d" %
              (g.w, g.h, g.links, g.oben, g.adv26))
        for y in range(g.h):
            print("".join(" .:-=+*#%@"[min(9, g.punkt(x, y) * 10 // 256)]
                          for x in range(g.w)))
        return 0
    if len(argv) >= 4 and argv[0] == "summe":
        s = Schrift(argv[1], int(argv[2]))
        print(kern.summe(s.glyphe(ord(argv[3]))))
        return 0
    print("fuiraster.py glyphe|summe <ttf> <px> <zeichen>", file=sys.stderr)
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
