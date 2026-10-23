#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
"""tools/traypop/raster.py -- the tile RASTER of the tray flyout (W-MERGEB2), read from serial + photos.

    raster.py <serial> <open.ppm> <hover.ppm> <menu.ppm> <label>

Prints `OK    ...` / `FAIL  ...` lines (run.sh counts them).  Checks:
  1. tile lines `traypop: tile i= x= y= w= h=` (window coordinates): all tiles one size, one x pitch per row, one row pitch,
     all inside the flyout rectangle of `traypop: open n= x= y= w= h=`
  2. icon centre: the ink of each tile (pixels unlike the tile's main colour) has its bounding-box centre within 1 px of the
     tile centre (both axes)
  3. hover: the photo with the pointer on tile 0 differs from the one without it inside tile 0, not (or hardly) inside tile 1
  4. right click on tile 0 -> `traypop: menu id=<id of item 0>`, the photo shows a menu (differs from the hover photo)
COUNTER-PROOFS (the checks have teeth): the same raster check on a copy with one tile moved by 2 px must FAIL, the centre
check on an ink box shifted by 3 px must FAIL.
"""
import re
import sys


def load(p):
    d = open(p, "rb").read()
    f = []
    at = 2
    while len(f) < 3:
        while d[at:at + 1].isspace():
            at += 1
        s = at
        while not d[at:at + 1].isspace():
            at += 1
        f.append(int(d[s:at]))
    return f[0], f[1], d[at + 1:]


def raster_ok(tiles, ow, oh):
    """-> (ok, why).  tiles: {i: (x, y, w, h)}"""
    if len(tiles) < 2:
        return False, "only %d tile(s)" % len(tiles)
    sizes = {(t[2], t[3]) for t in tiles.values()}
    if len(sizes) != 1:
        return False, "tile sizes differ: %s" % sorted(sizes)
    rows = {}
    for t in tiles.values():
        rows.setdefault(t[1], []).append(t[0])
    for y, xs in rows.items():
        xs.sort()
        gaps = {xs[k + 1] - xs[k] for k in range(len(xs) - 1)}
        if len(gaps) > 1:
            return False, "row y=%d has uneven x gaps %s" % (y, sorted(gaps))
    ys = sorted(rows)
    gy = {ys[k + 1] - ys[k] for k in range(len(ys) - 1)}
    if len(gy) > 1:
        return False, "uneven row pitch %s" % sorted(gy)
    xs0 = {tuple(sorted(r)) for r in rows.values()}
    for t in tiles.values():
        if t[0] < 0 or t[1] < 0 or t[0] + t[2] > ow or t[1] + t[3] > oh:
            return False, "tile %s sticks out of the %dx%d flyout" % (t, ow, oh)
    sz = sorted(sizes)[0]
    return True, "%d tiles %dx%d, rows y=%s, x=%s" % (len(tiles), sz[0], sz[1], ys, sorted(xs0))


def ink_box(W, px, x, y, w, h):
    cnt = {}
    for yy in range(y, y + h):
        for xx in range(x, x + w):
            i = (yy * W + xx) * 3
            p = (px[i], px[i + 1], px[i + 2])
            cnt[p] = cnt.get(p, 0) + 1
    bg = max(cnt, key=cnt.get)
    x0 = y0 = 1 << 30
    x1 = y1 = -1
    for yy in range(y, y + h):
        for xx in range(x, x + w):
            i = (yy * W + xx) * 3
            p = (px[i], px[i + 1], px[i + 2])
            if sum(abs(p[k] - bg[k]) for k in range(3)) > 60:
                x0 = min(x0, xx); x1 = max(x1, xx); y0 = min(y0, yy); y1 = max(y1, yy)
    if x1 < 0:
        return None
    return x0, y0, x1, y1


def centre_off(box, x, y, w, h):
    """offset of the ink centre from the tile centre in px (x, y), halves kept"""
    cx2 = box[0] + box[2] + 1
    cy2 = box[1] + box[3] + 1
    return (cx2 - (2 * x + w)) / 2.0, (cy2 - (2 * y + h)) / 2.0


def diff(W, a, b, x, y, w, h):
    n = 0
    for yy in range(y, y + h):
        o = (yy * W + x) * 3
        ra = a[o:o + w * 3]
        rb = b[o:o + w * 3]
        if ra != rb:
            for k in range(0, w * 3, 3):
                if ra[k:k + 3] != rb[k:k + 3]:
                    n += 1
    return n


def main():
    ser, p_open, p_hover, p_menu, label = sys.argv[1:6]
    t = open(ser, "rb").read().decode("latin1")

    def say(ok, m):
        print(("OK    " if ok else "FAIL  ") + "%s: %s" % (label, m))

    o = re.search(r"traypop: open n=(\d+) x=(\d+) y=(\d+) w=(\d+) h=(\d+)", t)
    if not o:
        say(False, "no `traypop: open` line")
        return
    ox, oy, ow, oh = (int(o[k]) for k in (2, 3, 4, 5))
    tiles = {}
    for m in re.finditer(r"traypop: tile i=(\d+) x=(\d+) y=(\d+) w=(\d+) h=(\d+)", t):
        tiles.setdefault(int(m[1]), tuple(int(m[k]) for k in (2, 3, 4, 5)))
    ok, why = raster_ok(tiles, ow, oh)
    say(ok, "tile raster: " + why)
    if ok:
        bad = dict(tiles)
        k0 = sorted(bad)[-1]
        bx, by, bw, bh = bad[k0]
        bad[k0] = (bx + 2, by, bw, bh)
        okb, _ = raster_ok(bad, ow, oh)
        if len(tiles) >= 3:
            say(not okb, "COUNTER: a tile moved by 2 px is caught")
        else:
            say(True, "COUNTER skipped (2 tiles have no pitch to break)")
    if len(tiles) < 2:
        return
    W, H, op = load(p_open)
    W2, _, hv = load(p_hover)
    W3, _, mn = load(p_menu)
    # 2. icon centre
    for i in sorted(tiles)[:6]:
        x, y, w, h = tiles[i]
        box = ink_box(W, op, ox + x + 2, oy + y + 2, w - 4, h - 4)
        if box is None:
            say(False, "tile %d: no ink" % i)
            continue
        dx, dy = centre_off(box, ox + x, oy + y, w, h)
        say(abs(dx) <= 1 and abs(dy) <= 1, "tile %d: ink box %dx%d, centre off by %+.1f,%+.1f px (want <= 1)"
            % (i, box[2] - box[0] + 1, box[3] - box[1] + 1, dx, dy))
    x, y, w, h = tiles[min(tiles)]
    box = ink_box(W, op, ox + x + 2, oy + y + 2, w - 4, h - 4)
    if box:
        sh = (box[0] + 3, box[1], box[2] + 3, box[3])
        dx, dy = centre_off(sh, ox + x, oy + y, w, h)
        say(abs(dx) > 1 or abs(dy) > 1, "COUNTER: an icon shifted by 3 px is caught (off %+.1f)" % dx)
    # 3. hover
    x0, y0, w0, h0 = tiles[min(tiles)]
    d0 = diff(W, op, hv, ox + x0, oy + y0, w0, h0)
    say(d0 >= w0 * h0 // 20, "hover on tile 0: %d of %d px of the tile changed (want >= 5 %%)" % (d0, w0 * h0))
    k1 = [k for k in sorted(tiles) if k != min(tiles)][0]
    x1, y1, w1, h1 = tiles[k1]
    d1 = diff(W, op, hv, ox + x1, oy + y1, w1, h1)
    say(d1 <= w1 * h1 // 10, "tile %d (not hovered) changed in %d of %d px (want <= 10 %%)" % (k1, d1, w1 * h1))
    # 4. right click
    mid = re.search(r"traypop: item 0 id=(\d+)", t)
    mm = re.search(r"traypop: menu id=(\d+)", t)
    say(bool(mm), "right click on tile 0 -> `traypop: menu id=%s`" % (mm[1] if mm else "?"))
    if mm and mid:
        say(mm[1] == mid[1], "the menu belongs to item 0 (id %s, item 0 is id %s)" % (mm[1], mid[1]))
    dm = diff(W, hv, mn, ox, oy, ow, oh)
    say(dm >= 2000, "the picture changed %d px inside the flyout when the menu opened (want >= 2000)" % dm)


main()
