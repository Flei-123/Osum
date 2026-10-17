#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
"""tools/latency/judge.py <serial.txt> [--expect-red] -- read the `wm: lat ...` lines (one per F12 and one per desktop pulse).
Input -> picture (mean of a slice) = gapwait (mean wait of a packet before the input poll) + latmean (poll -> frame on the card), in us.

W-L (17.10.2026): the judge is statistical. A single slice is noisy (the pulse itself prints to the serial port and costs one 60-230 ms
gap per slice; the host can steal a vCPU), so the verdict is over all slices that painted at least 3 pointer-driven frames:
  - median input -> picture over the slices <= 16 ms
  - at most 25 % of the slices above 33 ms
  - at least 90 % of the slices have <= 2 poll gaps above 33 ms (the pulse artefact is one of them)
  - at least 20 such slices exist
--expect-red (counter-proof, word `nolatfix` = old 10-20 ms tick loop): the old loop must FAIL the median (> 16 ms) or make
less than a third of the polls of the new loop would (median gaps per slice < 1000)."""
import re
import statistics
import sys

LIM_MEDIAN = 16000
LIM_BAD = 33000
t = open(sys.argv[1], "rb").read().decode("latin1")
rows = []
for line in t.splitlines():
    m = re.search(r"wm: lat gapn=(\d+) gapmean=(\d+) gapwait=(\d+) gapmax=(\d+) gap8=(\d+) gap16=(\d+) gap33=(\d+) latn=(\d+) latmean=(\d+) latmax=(\d+) lat16=(\d+) lat33=(\d+)", line)
    if m:
        rows.append([int(x) for x in m.groups()])
rows = [r for r in rows if r[7] >= 3]
est = [r[2] + r[8] for r in rows]
bad = 0


def chk(ok, msg):
    global bad
    print("  %s  %s" % ("OK  " if ok else "FAIL", msg))
    if not ok:
        bad += 1


if len(rows) < 20:
    print("  FAIL  only %d slices with pointer-driven frames (need 20)" % len(rows))
    sys.exit(1)
med = statistics.median(est)
over = sum(1 for e in est if e > LIM_BAD) * 100 // len(est)
calm = sum(1 for r in rows if r[6] <= 2) * 100 // len(rows)
gapn = statistics.median(r[0] for r in rows)
print("  slices=%d median input->picture=%.1f ms  slices>33ms=%d%%  slices with <=2 gaps>33ms=%d%%  median polls/slice=%d  worst slice=%.1f ms" %
      (len(rows), med / 1000.0, over, calm, gapn, max(est) / 1000.0))
if "--expect-red" in sys.argv:
    red = med > LIM_MEDIAN or gapn < 1000
    chk(red, "counter-proof (old loop): median %.1f ms (must be > 16) or polls/slice %d (must be < 1000)" % (med / 1000.0, gapn))
else:
    chk(med <= LIM_MEDIAN, "median input -> picture %.1f ms (limit 16)" % (med / 1000.0))
    chk(over <= 25, "slices above 33 ms: %d%% (limit 25%%)" % over)
    chk(calm >= 90, "slices with <= 2 poll gaps above 33 ms: %d%% (need 90%%)" % calm)
sys.exit(1 if bad else 0)
