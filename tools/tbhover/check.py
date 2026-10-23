#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
"""tools/tbhover/check.py <run dir> <ui scale> -- reads serial.txt + the pictures of tools/tbhover/run.sh.

Rectangles come from the bar's own report lines (`taskbar: geom`, `pin`, `start`, `chevron`, `field clock`), never from a guess.
"""
import re
import sys

out = sys.argv[1]
sc = int(sys.argv[2]) if len(sys.argv) > 2 else 1
passed = 0
failed = 0


def ok(msg):
    global passed
    passed += 1
    print("  OK    " + msg)


def bad(msg):
    global failed
    failed += 1
    print("  FAIL  " + msg)


def check(cond, good, wrong):
    if cond:
        ok(good)
    else:
        bad(wrong)


def load(name):
    try:
        d = open("%s/%s.ppm" % (out, name), "rb").read()
    except OSError:
        return None
    f = []
    at = 2
    while len(f) < 3:
        while d[at:at + 1].isspace():
            at += 1
        s = at
        while not d[at:at + 1].isspace():
            at += 1
        f.append(int(d[s:at]))
    return (f[0], f[1], d[at + 1:])


def px(im, x, y):
    w, h, d = im
    o = (y * w + x) * 3
    return tuple(d[o:o + 3])


def dist(a, b):
    return sum(abs(a[i] - b[i]) for i in range(3))


try:
    ser = open(out + "/serial.txt", "rb").read().decode("latin-1")
except OSError:
    print("  FAIL  no serial.txt")
    print("TBHOVER-CHECK: 0 passed, 1 failed")
    sys.exit(1)

geom = list(re.finditer(r"taskbar: geom edge=\d+ x=(\d+) y=(\d+) w=(\d+) h=(\d+)", ser))
if not geom:
    print("  FAIL  no taskbar geometry on the serial line")
    print("TBHOVER-CHECK: 0 passed, 1 failed")
    sys.exit(1)
gy = int(geom[-1].group(2))
bar_h = int(geom[-1].group(4))


def first(pat):
    m = re.search(pat, ser)
    return None if m is None else (int(m.group(1)), int(m.group(2)) + gy, int(m.group(3)), int(m.group(4)))


def last(pat):
    ms = list(re.finditer(pat, ser))
    if not ms:
        return None
    m = ms[-1]
    return (int(m.group(1)), int(m.group(2)) + gy, int(m.group(3)), int(m.group(4)))


def pin(name, final):
    pat = r"taskbar: pin %s x=(\d+) y=(\d+) w=(\d+) h=(\d+)" % name
    return last(pat) if final else first(pat)


names = ["00-rest", "01-hover-pin", "02-away", "03-start", "04-chevron", "05-clock", "06-down", "07-active", "08-hover-running"]
im = {n: load(n) for n in names}
miss = [n for n in names if im[n] is None]
if miss:
    print("  FAIL  pictures missing: " + " ".join(miss))
    print("TBHOVER-CHECK: 0 passed, 1 failed")
    sys.exit(1)

rest = im["00-rest"]
rs = pin("settings", False)
rt = pin("taskmgr", False)
rst = first(r"taskbar: start x=(\d+) y=(\d+) w=(\d+) h=(\d+)")
rch = first(r"taskbar: chevron x=(\d+) y=(\d+) w=(\d+) h=(\d+)")
rck = first(r"taskbar: field clock x=(\d+) y=(\d+) w=(\d+) h=(\d+)")
for nm, r in (("settings pin", rs), ("taskmgr pin", rt), ("start", rst), ("chevron", rch), ("clock", rck)):
    check(r is not None, "%s rectangle reported %s" % (nm, r), "%s: no report line" % nm)
if None in (rs, rt, rst, rch, rck):
    print("TBHOVER-CHECK: %d passed, %d failed" % (passed, failed))
    sys.exit(1)

E = 2 * sc


def edge(r):
    return (r[0] + E, r[1] + r[3] // 2)


def bg_at(img, r):
    return px(img, 40 * sc, r[1] + r[3] // 2)


def plate(img, r):
    return px(img, *edge(r))


# 1. hover over an idle pin: a plate appears, rounded (corner pixel untouched)
bg = bg_at(rest, rs)
check(dist(plate(rest, rs), bg) <= 6, "idle pin without pointer: edge pixel is the bar colour %s" % (bg,),
      "idle pin shows a plate at rest: %s vs bar %s" % (plate(rest, rs), bg))
p1 = plate(im["01-hover-pin"], rs)
check(dist(p1, bg) >= 12, "hover on the idle pin: plate %s differs from the bar %s" % (p1, bg),
      "hover on the idle pin: NO plate (%s vs bar %s)" % (p1, bg))
c1 = px(im["01-hover-pin"], rs[0], rs[1])
check(dist(c1, px(rest, rs[0], rs[1])) <= 6, "the plate is rounded: corner pixel untouched",
      "corner pixel changed: %s -> %s (square plate)" % (px(rest, rs[0], rs[1]), c1))
# 2. gone again
a2 = plate(im["02-away"], rs)
check(dist(a2, bg) <= 6, "pointer left: the plate is gone again", "plate stays after the pointer left: %s" % (a2,))
# 3. start, chevron, clock
for nm, r, key in (("start button", rst, "03-start"), ("tray chevron", rch, "04-chevron"), ("clock", rck, "05-clock")):
    pc = plate(im[key], r)
    check(dist(pc, bg) >= 12, "hover on the %s: plate %s" % (nm, pc), "hover on the %s: NO plate (%s vs bar %s)" % (nm, pc, bg))
# 4. pressed: another colour than hover, and not the bar
pd = plate(im["06-down"], rt)
ph = plate(im["01-hover-pin"], rs)
check(dist(pd, bg) >= 12, "pressed pin: plate %s" % (pd,), "pressed pin shows no plate: %s" % (pd,))
check(dist(pd, ph) >= 4, "pressed colour %s differs from the hover colour %s" % (pd, ph),
      "pressed colour %s == hover colour %s" % (pd, ph))
# 5. active strips (final layout)
act = im["07-active"]
fe = pin("explorer", True)
ft = pin("taskmgr", True)
fs = pin("settings", True)


def strip_width(img, r):
    best = 0
    for dy in range(1, 4 * sc + 1):
        y = r[1] + r[3] - dy
        base = px(img, r[0] + E, y)
        n = 0
        for x in range(r[0] + E, r[0] + r[2] - E):
            if dist(px(img, x, y), base) >= 30:
                n += 1
        best = max(best, n)
    return best


we, wt, ws = strip_width(act, fe), strip_width(act, ft), strip_width(act, fs)
print("        strip widths: explorer(focused)=%d taskmgr(running)=%d settings(idle)=%d" % (we, wt, ws))
check(ws == 0, "idle pin: no strip", "idle pin carries a strip (%d px)" % ws)
check(wt >= 3 * sc, "running program: short strip (%d px)" % wt, "running program without a strip (%d px)" % wt)
check(we >= wt * 3 // 2 and we >= 6 * sc, "focused program: wide strip (%d px > %d px)" % (we, wt),
      "focused strip not wider than the running one (%d vs %d)" % (we, wt))
# 6. hover over a running (not focused) pin
pr = plate(im["08-hover-running"], ft)
pq = plate(act, ft)
check(dist(pr, pq) >= 12, "hover on the running pin: plate %s (before %s)" % (pr, pq),
      "hover on the running pin: no plate (%s vs %s)" % (pr, pq))
# 7. repaint only on change: one trace line per change of the hovered button
hl = len(re.findall(r"taskbar: hotbtn \d+", ser))
check(1 <= hl <= 40, "hover trace lines: %d (only changes repaint)" % hl, "hover trace lines: %d (expected 1..40)" % hl)
print("TBHOVER-CHECK: %d passed, %d failed" % (passed, failed))
sys.exit(1 if failed else 0)
