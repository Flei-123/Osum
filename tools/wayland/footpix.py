#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
# tools/wayland/footpix.py -- pixel facts of a QEMU screendump (P6 PPM) with a foot window in it.
#   footpix.py <shot.ppm>      prints: W=<w> H=<h> bg=<n> text=<n> bx0=.. by0=.. bx1=.. by1=.. dist=<n>
# bg   = pixels of foot's default background (#242424); the box is their bounding box (the terminal grid)
# text = pixels inside the box that are light (every channel >= 0x90): glyphs, cursor
# dist = number of distinct colours inside the box (a flat fill has 1)
import sys

def read_ppm(path):
    with open(path, 'rb') as f:
        data = f.read()
    pos = 0
    toks = []
    while len(toks) < 4:
        while data[pos:pos + 1].isspace():
            pos += 1
        if data[pos:pos + 1] == b'#':
            while data[pos:pos + 1] != b'\n':
                pos += 1
            continue
        start = pos
        while not data[pos:pos + 1].isspace():
            pos += 1
        toks.append(data[start:pos])
    pos += 1
    if toks[0] != b'P6':
        raise SystemExit('not a P6 file')
    return int(toks[1]), int(toks[2]), data[pos:]

def facts(path):
    w, h, px = read_ppm(path)
    bg = b'\x24\x24\x24'
    x0 = y0 = 10 ** 9
    x1 = y1 = -1
    n_bg = 0
    for y in range(h):
        row = px[y * w * 3:(y + 1) * w * 3]
        first = last = -1
        x = row.find(bg)
        while x != -1:
            if x % 3 == 0:
                if first < 0:
                    first = x // 3
                last = x // 3
                n_bg += 1
                x = row.find(bg, x + 3)
            else:
                x = row.find(bg, x + 1)
        if first >= 0:
            x0 = min(x0, first); x1 = max(x1, last)
            y0 = min(y0, y); y1 = y
    text = 0
    cols = set()
    if x1 >= 0:
        for y in range(y0, y1 + 1):
            row = px[(y * w + x0) * 3:(y * w + x1 + 1) * 3]
            for i in range(0, len(row), 3):
                r, g, b = row[i], row[i + 1], row[i + 2]
                if r >= 0x90 and g >= 0x90 and b >= 0x90:
                    text += 1
                if len(cols) < 64:
                    cols.add((r, g, b))
    return dict(W=w, H=h, bg=n_bg, text=text, bx0=x0 if x1 >= 0 else 0, by0=y0 if x1 >= 0 else 0, bx1=x1, by1=y1, dist=len(cols))

if __name__ == '__main__':
    r = facts(sys.argv[1])
    print(' '.join('%s=%s' % kv for kv in r.items()))
