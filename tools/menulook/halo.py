#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
import os
import re
import sys

out = sys.argv[1]
ok = fail = 0


def say(good, msg):
    global ok, fail
    if good:
        ok += 1
    else:
        fail += 1
    print(("  OK    " if good else "  FAIL  ") + msg)


def load_ppm(path):
    d = open(path, "rb").read()
    f = []
    at = 2
    while len(f) < 3:
        while d[at:at + 1].isspace():
            at += 1
        s = at
        while not d[at:at + 1].isspace():
            at += 1
        f.append(int(d[s:at]))
    return f[0], d[at + 1:]


def lum(d, w, x, y):
    o = (y * w + x) * 3
    return (d[o] * 3 + d[o + 1] * 6 + d[o + 2]) // 10


ser = open(os.path.join(out, "serial.txt"), "rb").read().decode("latin1")
m = re.search(r"taskbar: jumplist n=\d+ x=(\d+) y=(\d+) w=(\d+) h=(\d+)", ser)
if not m:
    say(False, "no jump list line in the serial log")
    print("RESULT ok=%d fail=%d" % (ok, fail))
    sys.exit(1)
x, y, w, h = (int(v) for v in m.groups())
W, base = load_ppm(os.path.join(out, "00-desktop.ppm"))
_, menu = load_ppm(os.path.join(out, "02b-icon-menu.ppm"))
RANGE = 9
profile = [0] * (RANGE + 1)
rows = 0
bright = 0
total = 0
for ry in range(y + h // 4, y + 3 * h // 4, 2):
    rows += 1
    for off in range(1, RANGE + 1):
        d = lum(base, W, x - off, ry) - lum(menu, W, x - off, ry)
        profile[off] += d
        total += 1
        if d < -3:
            bright += 1
profile = [p / max(rows, 1) for p in profile]
say(bright * 100 <= total * 3, "the margin around the panel is never brighter than the desktop (%d of %d samples)" % (bright, total))
say(profile[1] >= profile[5] - 0.5 and profile[5] >= profile[RANGE] - 0.5, "the shadow decays outward in one smooth ramp (darkening %.1f, %.1f, %.1f)" % (profile[1], profile[5], profile[RANGE]))
say(profile[RANGE] <= 2.5, "no second panel edge at the window boundary (darkening %.1f 9 px away)" % profile[RANGE])
step = max(abs(profile[i] - profile[i + 1]) for i in range(1, RANGE))
say(step <= 8.0, "no step in the halo profile (largest step %.1f levels)" % step)
print("RESULT ok=%d fail=%d" % (ok, fail))
sys.exit(1 if fail else 0)
