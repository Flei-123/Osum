#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
"""tools/settingsflick/judge.py <serial.txt> <maximised.ppm> -- X2: the Settings window is painted into a private picture, so a hover
damages only what changed. Per F12 phase (`wm: bild` lines) the composed large rectangles (`wm: crect`, > 16384 px) of the window under
test are counted. Verdicts: (a) hover over the small window: <= 1 large rect per 100 frames; (b) the window follows a maximise (the
screenshot after it shows the window surface over the work area, not wallpaper); (c) hover over the maximised window: <= 1 large
rect per 100 frames. Exit 1 on any FAIL."""
import re
import sys

t = open(sys.argv[1], "rb").read().decode("latin1")
phases = []
cur = {"rects": 0, "org": {}}
for line in t.splitlines():
    m = re.match(r"wm: bild n=(\d+)", line)
    if m:
        cur["n"] = int(m.group(1))
        phases.append(cur)
        cur = {"rects": 0, "org": {}}
        continue
    r = re.search(r"wm: crect (\d+) (\d+) (\d+) (\d+) ", line)
    if r:
        x0, y0, x1, y1 = (int(r.group(i)) for i in range(1, 5))
        if (x1 - x0) * (y1 - y0) > 16384:
            cur["rects"] += 1
            cur["org"][(x0, y0)] = cur["org"].get((x0, y0), 0) + 1
bad = 0
names = ["boot rest", "Settings opens", "pointer over Settings", "maximise", "pointer over maximised Settings"]
for i, p in enumerate(phases):
    print("  phase %d %-32s frames=%s composed_large_rects=%d origins=%s" %
          (i + 1, names[i] if i < len(names) else "?", p["n"], p["rects"], sorted(p["org"].items(), key=lambda kv: -kv[1])[:3]))
if len(phases) < 5:
    print("  FAIL  only %d phases measured" % len(phases))
    sys.exit(1)
# Noise of the audit setup, not judged: the terminal window behind (uitrace prints into it), the task bar and the clock.
NOISE = {(24, 40), (24, 0), (0, 40), (0, 760), (1092, 16)}
# the window under test moves (placement, maximise), so every other origin counts
for i in (2, 4):
    p = phases[i]
    mine = max([v for k, v in p["org"].items() if k not in NOISE] or [0])
    ok = mine * 100 <= max(p["n"], 1)
    print("  %s  %s: %d composed large rects of the busiest window in %d frames (need <= 1 per 100)" %
          ("OK  " if ok else "FAIL", names[i], mine, p["n"]))
    bad += 0 if ok else 1

# (b) the maximised screenshot: the lower right quarter of the screen must be painted by the window (not one flat colour = wallpaper/black)
def ppm(path):
    d = open(path, "rb").read()
    parts = d.split(b"\n", 3)
    w, h = (int(v) for v in parts[1].split())
    return w, h, parts[3]
try:
    w, h, px = ppm(sys.argv[2])
    # the strip right of the old window (x > 1030) and the strip below it (y 742..756) must now be window surface (light), not the dark wallpaper
    def lum(x, y):
        o = (y * w + x) * 3
        return sum(px[o:o + 3]) // 3
    pts = [(1100, 300), (1100, 500), (640, 745), (300, 750)]
    ls = [lum(x, y) for x, y in pts]
    ok = min(ls) >= 180
    print("  %s  maximised Settings covers the old right/bottom strips: luminance %s (need all >= 180)" % ("OK  " if ok else "FAIL", ls))
    bad += 0 if ok else 1
except Exception as e:
    print("  FAIL  screenshot unreadable: %s" % e)
    bad += 1
sys.exit(1 if bad else 0)
