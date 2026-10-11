#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
# tools/drag/check.py -- is the title bar of a dragged window in EVERY frame of the series?
#
#   check.py <dir> <prefix> <list>      <list> = lines "schleppfoto: <name> <x> <y> <phase>" (from the drehbuch run)
#
# The pointer holds the window by the middle of its title bar. The pixels in a strip LEFT of the pointer on the pointer's row belong to the
# title bar in every frame in which the bar exists (the bar moves with the pointer; the swing lags by a few points only, the bar is
# 30..60 points high). Reference = the median colour of that strip in the picture BEFORE the grab (title text skews the mean, the median
# ignores it). A frame passes when >= 70 % of its strip pixels are within TOL of the reference AND the reference differs from the colour
# 80 points further left outside the strip... (no: from the colour of the desktop, measured far from the window) so that a bar that
# happens to look like the wallpaper cannot pass.
import sys, os

TOL = 18

def read_ppm(path):
    with open(path, 'rb') as f:
        data = f.read()
    parts = []
    pos = 0
    while len(parts) < 4:
        while data[pos:pos + 1].isspace():
            pos += 1
        if data[pos:pos + 1] == b'#':
            while data[pos:pos + 1] != b'\n':
                pos += 1
            continue
        s = pos
        while not data[pos:pos + 1].isspace():
            pos += 1
        parts.append(data[s:pos])
    pos += 1
    w, h = int(parts[1]), int(parts[2])
    return w, h, data[pos:]

def px(img, x, y):
    w, h, d = img
    o = (y * w + x) * 3
    return d[o], d[o + 1], d[o + 2]

def near(a, b, tol=TOL):
    return all(abs(a[i] - b[i]) <= tol for i in range(3))

def strip(img, x, y, n0=60, n1=10):
    w, h, d = img
    return [px(img, xx, y) for xx in range(max(0, x - n0), max(0, x - n1))]

def median(cols):
    return tuple(sorted(c[i] for c in cols)[len(cols) // 2] for i in range(3))

def main():
    d, prefix, lst = sys.argv[1], sys.argv[2], sys.argv[3]
    rows = []
    for line in open(lst, errors='replace'):
        if not line.startswith('schleppfoto: ' + prefix + '-'):
            continue
        t = line.split()
        rows.append((t[1], int(t[2]), int(t[3]), t[4]))
    if len(rows) < 4:
        print('check: only %d pictures' % len(rows))
        sys.exit(2)
    before = read_ppm(os.path.join(d, rows[0][0] + '.ppm'))
    ref = median(strip(before, rows[0][1], rows[0][2]))
    far = px(before, 8, 8)
    print('check: reference title colour %s, desktop corner %s' % (ref, far))
    if near(ref, far, 10):
        print('check: the title colour looks like the desktop -- the test would be blind')
        sys.exit(2)
    bad = 0
    for name, x, y, ph in rows[1:]:
        img = read_ppm(os.path.join(d, name + '.ppm'))
        st = strip(img, x, y)
        good = sum(1 for c in st if near(c, ref))
        frac = good * 100 // max(1, len(st))
        ok = frac >= 70
        print('check: %-14s %-8s pointer %4d,%4d bar pixels %3d %%  %s' % (name, ph, x, y, frac, 'OK' if ok else 'BAR MISSING'))
        if not ok:
            bad += 1
    print('check: %d of %d frames without a title bar' % (bad, len(rows) - 1))
    sys.exit(1 if bad else 0)

main()
