#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
"""tools/lockflicker/anchor.py <run dir> <lock|glogin> <width> <height> <scale>

ANCHORED LAYOUT of the lock / login screen, measured in ONE run (serial.txt `rect` lines + base.ppm):
  margins   the bottom-right group (clock/DEU/network/power) hangs on the bottom-right corner and the user entry on the
            bottom-left corner, all four edge margins equal (32 design points * scale, tolerance 2 px + 1 pixel per scale step)
  align     the right group and the user entry end on the same bottom line
  centre    the main block (avatar top .. password field bottom) is centred on the screen, horizontally and vertically
  ink       the initial inside the avatar disc (big one and the small bottom-left chip) is centred by its INK box: the middle of
            the white letter pixels lies within 1 px of the disc centre (not the advance box: a "J" hangs left of its pen)
Prints `  OK` / `  FAIL` lines; exit 0 = all OK, 1 = some FAIL. Counter-proof: run it on pictures of the old main (it must go red).
"""
import re, sys
import numpy as np
from scipy import ndimage


def read_ppm(path):
    d = open(path, "rb").read()
    m = re.match(rb"P6\s+(\d+)\s+(\d+)\s+255\s", d)
    w, h = int(m.group(1)), int(m.group(2))
    return w, h, np.frombuffer(d[m.end():], dtype=np.uint8).reshape(h, w, 3).astype(np.int32)


def blobs(arr, rgb, lo_y, hi_y, tol=3):
    m = (np.abs(arr[:, :, 0] - rgb[0]) <= tol) & (np.abs(arr[:, :, 1] - rgb[1]) <= tol) & (np.abs(arr[:, :, 2] - rgb[2]) <= tol)
    m[:lo_y, :] = False
    m[hi_y:, :] = False
    lab, _ = ndimage.label(m)
    out = []
    for i, sl in enumerate(ndimage.find_objects(lab), 1):
        ys, xs = sl
        bw, bh = xs.stop - xs.start, ys.stop - ys.start
        area = int((lab[sl] == i).sum())
        if bw >= 20 and 0.8 <= bw / bh <= 1.25 and area > 0.6 * bw * bh:
            out.append((xs.start, ys.start, bw, bh, area))
    return out


def ink_centre(arr, disc):
    """centre of the white letter pixels inside the disc (x, y as floats), None when there are none"""
    x0, y0, bw, bh, _ = disc
    cx, cy, r = x0 + bw / 2.0, y0 + bh / 2.0, min(bw, bh) / 2.0
    yy, xx = np.mgrid[y0:y0 + bh, x0:x0 + bw]
    inside = ((xx + 0.5 - cx) ** 2 + (yy + 0.5 - cy) ** 2) <= (0.8 * r) ** 2
    sub = arr[y0:y0 + bh, x0:x0 + bw]
    white = (sub[:, :, 0] >= 0xB8) & (sub[:, :, 1] >= 0xC0) & (sub[:, :, 2] >= 0xD0) & inside
    ys, xs = np.nonzero(white)
    if len(xs) < 6:
        return None
    return (x0 + (xs.min() + xs.max() + 1) / 2.0, y0 + (ys.min() + ys.max() + 1) / 2.0, cx, cy)


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
    rects = {}
    for l in ser:
        m = pat.search(l)
        if m:
            i, k, x, y, w, h = map(int, m.groups())
            rects[i] = (k, x, y, w, h)  # the last report of an id wins
    w, h, arr = read_ppm(run + "/base.ppm")
    ok((w, h) == (W, H), "picture is %dx%d" % (w, h))
    tall = H // S >= 480
    want = 32 * S
    tol = 2 * S + 1
    av_rgb = (0x4C, 0x6A, 0x92)
    big = [b for b in blobs(arr, av_rgb, 0, H * 3 // 4) if b[2] >= 24 * S]
    # the chip may start above 3/4 of the height on a short screen: look in the lower half (the main disc is bigger than 44 * S)
    chip = [b for b in blobs(arr, av_rgb, H // 2, H) if 28 * S <= b[2] <= 44 * S]
    big = max(big, key=lambda b: b[4]) if big else None
    chip = max(chip, key=lambda b: b[4]) if chip else None
    # ---- margins (bottom strip)
    low = [(i, r) for i, r in rects.items() if r[2] > H * 3 // 4 or (not tall and r[2] > H // 2)]
    if not low:
        ok(False, "bottom strip rects reported")
    else:
        right = max(r[1] + r[3] for _, r in low)
        pw = max(low, key=lambda t: t[1][1] + t[1][3])[1]
        rm, bm = W - right, H - (pw[2] + pw[4])
        print("        right group: right edge margin %d, bottom margin %d (want %d)" % (rm, bm, want))
        ok(abs(rm - want) <= tol, "right group: margin to the right edge %d == %d (+-%d)" % (rm, want, tol))
        ok(abs(bm - want) <= tol, "right group: margin to the bottom edge %d == %d (+-%d)" % (bm, want, tol))
        if chip:
            lm = chip[0]
            ok(abs(lm - want) <= tol, "user entry: margin to the left edge %d == %d (+-%d)" % (lm, want, tol))
            if app == "glogin" and 9 in rects:
                a = rects[9]
                lb = H - (a[2] + a[4])
                ok(abs(lb - want) <= tol, "user entry ('Anderer Benutzer'): margin to the bottom edge %d == %d (+-%d)" % (lb, want, tol))
                ok(abs(lb - bm) <= S + 1, "left and right bottom groups end on one line (%d vs %d)" % (lb, bm))
            else:
                lb = H - (chip[1] + chip[3])
                ok(abs(lb - bm) <= S + 1, "chip bottom margin %d == right group's %d" % (lb, bm))
        else:
            ok(False, "bottom-left user chip found in the picture")
    # ---- centre of the main block
    if big:
        ents = [r for r in rects.values() if r[0] == 4]  # the password entry (kind 4)
        ent = ents[-1] if ents else None
        bx = big[0] + big[2] / 2.0
        ok(abs(bx - W / 2.0) <= S + 1, "main block: avatar centre x %.1f == screen centre %.1f" % (bx, W / 2.0))
        if ent and tall:
            top, bot = big[1], ent[2] + ent[4]
            mid = (top + bot) / 2.0
            ok(abs(mid - H / 2.0) <= 2 * S + 1, "main block (avatar top %d .. field bottom %d): centre y %.1f == screen centre %.1f" % (top, bot, mid, H / 2.0))
    else:
        ok(False, "avatar disc found")
    # ---- ink centre of the initial
    for nm, d in (("avatar", big), ("chip", chip)):
        if not d:
            continue
        c = ink_centre(arr, d)
        if c is None:
            ok(False, "%s: letter pixels found inside the disc" % nm)
            continue
        dx, dy = c[0] - c[2], c[1] - c[3]
        ok(abs(dx) <= 1.0 and abs(dy) <= 1.0 + (S - 1), "%s letter: ink centre (%.1f, %.1f) vs disc centre (%.1f, %.1f): dx %.1f dy %.1f <= 1 px" % (nm, c[0], c[1], c[2], c[3], dx, dy))
    return 1 if bad else 0


sys.exit(main())
