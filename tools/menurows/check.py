#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
import re
import sys

from PIL import Image

out = sys.argv[1]
serial = open(out + "/serial.txt", "rb").read().decode("latin1")
passed = 0
failed = 0


def check(cond, text):
    global passed, failed
    if cond:
        passed += 1
        print("  OK    " + text)
    else:
        failed += 1
        print("  FAIL  " + text)


def last(pat):
    found = re.findall(pat, serial)
    return tuple(int(v) for v in found[-1]) if found else None


geom = last(r"launcher: geom x=(\d+) y=(\d+) w=(\d+) h=(\d+)")
lst = last(r"launcher: rect id=2 kind=\d+ x=(\d+) y=(\d+) w=(\d+) h=(\d+)")
zh = last(r"launcher: rows x=\d+ base=\d+ zh=(\d+)")
check(geom is not None and lst is not None and zh is not None, "launcher reported geometry, list rectangle and row height")
if geom is None or lst is None or zh is None:
    print("MENUROWS: %d passed, %d failed" % (passed, failed))
    sys.exit(1)
wx, wy = geom[0], geom[1]
lx, ly, lw = lst[0], lst[1], lst[2]
zh = zh[0]


def row_box(n):
    return (wx + lx + 4, wy + ly + n * zh + 2, wx + lx + lw - 4, wy + ly + (n + 1) * zh - 2)


def img(name):
    return Image.open("%s/%s.ppm" % (out, name)).convert("RGB")


def differing(a, b, box, skip):
    pa, pb = a.load(), b.load()
    n = 0
    for y in range(box[1], box[3]):
        for x in range(box[0], box[2]):
            if skip and skip[0] <= x <= skip[2] and skip[1] <= y <= skip[3]:
                continue
            u, v = pa[x, y], pb[x, y]
            if max(abs(u[0] - v[0]), abs(u[1] - v[1]), abs(u[2] - v[2])) > 8:
                n += 1
    return n


def sprite(n):
    b = row_box(n)
    cx, cy = (b[0] + b[2]) // 2, (b[1] + b[3]) // 2
    return (cx - 8, cy - 8, cx + 24, cy + 32)


def hover_checks(prefix, rest, first, second, n1, n2, away):
    base = img(rest)
    h1 = img(first)
    h2 = img(second)
    area = row_box(n1)
    plate = differing(base, h1, area, sprite(n1))
    check(plate >= 400, "%s: hover on row %d paints a plate (%d points differ from rest)" % (prefix, n1, plate))
    other = differing(base, h1, row_box(n2 + 1), sprite(n1))
    check(other <= 5, "%s: the row below the pointer stays as at rest (%d points)" % (prefix, other))
    moved = differing(base, h2, row_box(n1), sprite(n2))
    check(moved <= 5, "%s: row %d is back at rest after the pointer left it (%d points)" % (prefix, n1, moved))
    plate2 = differing(base, h2, row_box(n2), sprite(n2))
    check(plate2 >= 400, "%s: hover on row %d paints a plate (%d points)" % (prefix, n2, plate2))
    if away:
        gone = differing(base, img(away), row_box(n2), None)
        check(gone <= 5, "%s: the plate is gone when the pointer is away (%d points)" % (prefix, gone))


hover_checks("all apps", "a0-rest", "a1-row2", "a2-row4", 2, 4, "a3-away")
hover_checks("search", "s0-rest", "s1-row2", "s2-row1", 2, 1, None)
print("MENUROWS: %d passed, %d failed" % (passed, failed))
sys.exit(1 if failed else 0)
