#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
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
bilder = []
pairs = []
last_image = None
for line in t.splitlines():
    m = re.search(r"wm: frame n=(\d+) mittel=(\d+) max=(\d+) over16=(\d+) fach=([\d ]+)", line)
    if m:
        last_image = (int(m.group(1)), int(m.group(3)), [int(x) for x in m.group(5).split()])
        continue
    m = re.search(r"wm: lat gapn=(\d+) gapmean=(\d+) gapwait=(\d+) gapmax=(\d+) gap8=(\d+) gap16=(\d+) gap33=(\d+) latn=(\d+) latmean=(\d+) latmax=(\d+) lat16=(\d+) lat33=(\d+)", line)
    if m and last_image is not None:
        pairs.append((last_image, [int(x) for x in m.groups()]))
        last_image = None
allrows = rows
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
paired = pairs
slow_frames = 0
slow_slices = 0
frames = 0
worst_frame = 0
for (b, r) in paired[2:]:
    if r[7] < 3:
        continue
    frames += b[0]
    k = (b[2][6] if len(b[2]) > 6 else 0) + (b[2][7] if len(b[2]) > 7 else 0)
    slow_frames += k
    slow_slices += 1 if k else 0
    worst_frame = max(worst_frame, b[1])
if paired:
    print("  frames in pointer slices=%d  frames >= 32 ms=%d (in %d slices)  largest frame=%.1f ms" % (frames, slow_frames, slow_slices, worst_frame / 1000.0))
if "--expect-red" in sys.argv:
    red = med > LIM_MEDIAN or gapn < 1000
    chk(red, "counter-proof (old loop): median %.1f ms (must be > 16) or polls/slice %d (must be < 1000)" % (med / 1000.0, gapn))
else:
    chk(med <= LIM_MEDIAN, "median input -> picture %.1f ms (limit 16)" % (med / 1000.0))
    chk(over <= 25, "slices above 33 ms: %d%% (limit 25%%)" % over)
    chk(calm >= 90, "slices with <= 2 poll gaps above 33 ms: %d%% (need 90%%)" % calm)
    chk(len(pairs) * 10 >= len(allrows) * 9, "frame times: %d of %d slices have a `wm: frame` line" % (len(pairs), len(allrows)))
    chk(frames > 0 and slow_frames * 100 <= frames and slow_slices <= 3,
        "frames >= 32 ms: %d of %d (limit 1%%, in at most 3 slices; here %d)" % (slow_frames, frames, slow_slices))
sys.exit(1 if bad else 0)
