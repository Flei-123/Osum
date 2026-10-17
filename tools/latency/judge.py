#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
"""tools/latency/judge.py <serial.txt> [--expect-red] -- read the `wm: lat ...` lines (one per F12) and judge the pointer phases.
Input -> picture (mean) = gapwait (mean wait of a packet before the input poll) + latmean (poll -> frame on the card), in microseconds.
Verdict per active phase (3 desktop sweep, 5 menu hover, 7 Settings hover, 8 window drag): mean <= 16000 us, no input poll gap
> 33000 us (gap33 = 0) and no poll -> picture time > 33000 us (lat33 = 0). --expect-red: the old loop (`nolatfix`) must FAIL the mean."""
import re
import sys

LIM_MEAN = 16000
ACTIVE = {3: "desktop sweep", 5: "start menu hover", 7: "Settings hover", 8: "window drag"}
t = open(sys.argv[1], "rb").read().decode("latin1")
rows = []
for line in t.splitlines():
    m = re.search(r"wm: lat gapn=(\d+) gapmean=(\d+) gapwait=(\d+) gapmax=(\d+) gap8=(\d+) gap16=(\d+) gap33=(\d+) latn=(\d+) latmean=(\d+) latmax=(\d+) lat16=(\d+) lat33=(\d+)", line)
    if m:
        rows.append([int(x) for x in m.groups()])
bad = 0
means = []
# the loop prints the counters on every F12 and on its own pulse: keep only the slices in which pointer input was painted
rows = [r for r in rows if r[7] > 0]
for i, r in enumerate(rows, 1):
    gapn, gapmean, gapwait, gapmax, g8, g16, g33, latn, latmean, latmax, l16, l33 = r
    est = gapwait + latmean
    nm = "slice %d" % i
    print("  phase %d %-18s gaps=%d mean=%dus wait=%dus max=%dus >16ms=%d >33ms=%d | poll->picture n=%d mean=%dus max=%dus >16ms=%d >33ms=%d | input->picture mean=%.1f ms" %
          (i, nm, gapn, gapmean, gapwait, gapmax, g16, g33, latn, latmean, latmax, l16, l33, est / 1000.0))
    if True:
        means.append(est)
        ok = est <= LIM_MEAN and g33 == 0 and l33 == 0 and latn > 0
        if "--expect-red" not in sys.argv:
            print("  %s  %s: mean %.1f ms (limit 16), gaps > 33 ms: %d, poll->picture > 33 ms: %d" % ("OK  " if ok else "FAIL", nm, est / 1000.0, g33, l33))
            bad += 0 if ok else 1
if len(rows) < 3:
    print("  FAIL  only %d slices with pointer input measured (need 3)" % len(rows))
    bad += 1
if "--expect-red" in sys.argv:
    worst = max(means) if means else 0
    red = worst > LIM_MEAN
    print("  %s  counter-proof (old loop): worst active phase %.1f ms, must be > 16 ms" % ("OK  " if red else "FAIL", worst / 1000.0))
    bad += 0 if red else 1
sys.exit(1 if bad else 0)
