#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
"""tools/lockflicker/check.py <run dir> <lock|glogin> <width> <height> <scale>

Layout check of the lock / login screen from ONE run (serial.txt + base.ppm):
  rects   the entry and its tiles (serial `<app>: rect ...`) lie completely inside the screen, the group is centred
  avatar  the avatar disc (solid 0x4C6A92 pixels in the picture) is complete inside the screen, centred, 112 * scale wide
  name    the white text between the avatar and the entry lies inside the column and is centred
Prints one `OK`/`FAIL` line per measurement; exit 0 = all OK, 1 = some FAIL.
"""
import re, sys

def read_ppm(path):
    d = open(path, "rb").read()
    m = re.match(rb"P6\s+(\d+)\s+(\d+)\s+255\s", d)
    w, h = int(m.group(1)), int(m.group(2))
    return w, h, d[m.end():]

def main():
    run, app, W, H, S = sys.argv[1], sys.argv[2], int(sys.argv[3]), int(sys.argv[4]), int(sys.argv[5])
    bad = 0
    def ok(c, msg):
        nonlocal bad
        print(("  OK    " if c else "  FAIL  ") + msg)
        if not c:
            bad += 1
    ser = open(run + "/serial.txt", errors="replace").read().splitlines()
    pat = re.compile(r"%s: rect id=(\d+) kind=(\d+) x=(\d+) y=(\d+) w=(\d+) h=(\d+)" % app)
    rects = [tuple(map(int, m.groups())) for m in (pat.search(l) for l in ser) if m]
    ent = [r for r in rects if r[1] == 4]
    ok(bool(ent), "%s: entry rectangle reported" % app)
    ey = 0
    if ent:
        e = ent[-1]
        ey = e[3]
        row = [r for r in rects if r[3] == e[3] and r[0] >= e[0]]
        last = [r for r in rects if r[0] >= e[0] and r[3] == e[3]]
        x0 = e[2]
        x1 = max(r[2] + r[4] for r in last)
        ok(e[4] == 240 * S, "entry width %d = 240 * %d (design points, scaled ONCE)" % (e[4], S))
        ok(x0 >= 0 and x1 <= W and e[3] >= 0 and e[3] + e[5] <= H, "entry + tiles inside the screen (x %d..%d of %d, y %d..%d of %d)" % (x0, x1, W, e[3], e[3] + e[5], H))
        cx = (x0 + x1) // 2
        ok(abs(cx - W // 2) <= 8 * S, "entry group centred (centre %d, screen centre %d)" % (cx, W // 2))
    others = [r for r in rects if r[1] == 2 and r[3] > H * 3 // 4]
    for r in (others if H // S >= 480 else []):  # design height < 480 points: the bottom strip cannot fit (1280x800 at scale 2)
        ok(r[2] >= 0 and r[2] + r[4] <= W and r[3] + r[5] <= H, "bottom tile id=%d inside the screen (x %d..%d, y %d..%d)" % (r[0], r[2], r[2] + r[4], r[3], r[3] + r[5]))
    w, h, px = read_ppm(run + "/base.ppm")
    ok((w, h) == (W, H), "picture is %dx%d" % (w, h))
    # avatar disc: solid colour 0x4C6A92 (+-3) in the upper 3/4, biggest connected blob approximated by the bounding box of
    # rows with >= 8 * S such pixels (the bottom-left chip of the lock is far smaller and sits in the lower quarter)
    tr, tg, tb = 0x4C, 0x6A, 0x92
    # the disc = the roundest big blob of the avatar colour in the upper 3/4 (a wallpaper can contain the same colour here and there)
    import numpy as np
    from scipy import ndimage
    arr = np.frombuffer(px, dtype=np.uint8).reshape(h, w, 3).astype(np.int32)
    msk = (np.abs(arr[:, :, 0] - tr) <= 3) & (np.abs(arr[:, :, 1] - tg) <= 3) & (np.abs(arr[:, :, 2] - tb) <= 3)
    msk[h * 3 // 4:, :] = False
    lab, nlab = ndimage.label(msk)
    minx, maxx, miny, maxy = w, -1, h, -1
    best = 0
    for i, sl in enumerate(ndimage.find_objects(lab), 1):
        ys_, xs_ = sl
        bw, bh = xs_.stop - xs_.start, ys_.stop - ys_.start
        area = int((lab[sl] == i).sum())
        if bw >= 24 * S and bh >= 24 * S and 0.8 <= bw / bh <= 1.25 and area > 0.6 * bw * bh and area > best:
            best = area
            minx, maxx, miny, maxy = xs_.start, xs_.stop - 1, ys_.start, ys_.stop - 1
    if maxx < 0:
        ok(False, "avatar disc not found in the picture")
        av_bottom = 0
    else:
        dw, dh = maxx - minx + 1, maxy - miny + 1
        av_bottom = maxy
        if H // S >= 480:
            ok(abs(dw - 112 * S) <= 6 * S and abs(dh - 112 * S) <= 6 * S, "avatar %dx%d, expected %d" % (dw, dh, 112 * S))
        else:  # short screen (< 480 points): the avatar shrinks (signin.fit_av, 48..112 points), still a round disc
            ok(48 * S - 6 * S <= dw <= 112 * S + 6 * S and abs(dw - dh) <= 2 * S, "avatar %dx%d, expected 48..112 points * %d (short screen)" % (dw, dh, S))
        ok(minx >= 0 and maxx < W and miny >= 0 and maxy < H, "avatar completely inside the screen (x %d..%d, y %d..%d)" % (minx, maxx, miny, maxy))
        ok(abs((minx + maxx) // 2 - W // 2) <= 6 * S, "avatar centred (centre %d, screen centre %d)" % ((minx + maxx) // 2, W // 2))
    # name + status text: near-white pixels between the avatar and the entry
    if ey and av_bottom:
        tminx, tmaxx, cnt = w, -1, 0
        for y in range(av_bottom + 4, max(av_bottom + 5, ey - 4)):
            row = px[y * w * 3:(y + 1) * w * 3]
            for x in range(w):
                if row[3 * x] >= 0xE8 and row[3 * x + 1] >= 0xE8 and row[3 * x + 2] >= 0xE8:
                    tminx, tmaxx, cnt = min(tminx, x), max(tmaxx, x), cnt + 1
        ok(cnt >= 40 * S, "name/status text present between avatar and entry (%d white pixels)" % cnt)
        if cnt:
            col0, col1 = W // 2 - 160 * S, W // 2 + 160 * S
            ok(tminx >= col0 and tmaxx <= col1 and tminx >= 0 and tmaxx < W, "text lies in the column and in the screen (x %d..%d)" % (tminx, tmaxx))
            ok(abs((tminx + tmaxx) // 2 - W // 2) <= 8 * S, "text centred (centre %d, screen centre %d)" % ((tminx + tmaxx) // 2, W // 2))
    return 1 if bad else 0

sys.exit(main())
