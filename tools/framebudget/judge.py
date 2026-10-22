#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
"""tools/framebudget/judge.py <serial.txt> -- MON-5: frames of 32 ms and more per scripted scenario (bucket 6 + 7 of `wm: bild ... fach=`).

Phases (F12 lines): 1 boot rest (ignored), 2 idle, 3 start menu, 4 Settings opens, 5 wheel scroll, 6 window drag.
Budget: 0 frames >= 32 ms in phases 3..6, and every scenario phase painted at least MINFRAMES frames (a phase without frames proves nothing).
Exit 1 on any FAIL. `--selftest` plants a 40 ms frame in a doctored copy of the serial lines and expects the verdict to turn red."""
import re
import sys

NAMES = ["boot rest", "idle", "start menu open/close", "Settings opens", "wheel scroll over Settings", "window drag"]
MINFRAMES = 5
BUDGET = 0


def parse(text):
    rows = []
    for line in text.splitlines():
        m = re.search(r"wm: bild n=(\d+) mittel=(\d+) max=(\d+) ueber16=(\d+) fach=([\d ]+)", line)
        if m:
            rows.append(dict(n=int(m.group(1)), mean=int(m.group(2)), mx=int(m.group(3)), o16=int(m.group(4)),
                             fach=[int(x) for x in m.group(5).split()]))
    return rows


def judge(rows, out):
    bad = 0
    if len(rows) < 6:
        out("  FAIL  only %d phases measured (need 6)" % len(rows))
        return 1
    for i, p in enumerate(rows[:6]):
        f32 = sum(p["fach"][6:8])
        out("  phase %d %-28s frames=%d mean=%d us max=%d us over16=%d frames>=32ms=%d" % (i + 1, NAMES[i], p["n"], p["mean"], p["mx"], p["o16"], f32))
    for i in range(2, 6):
        p = rows[i]
        f32 = sum(p["fach"][6:8])
        if p["n"] < MINFRAMES:
            out("  FAIL  %s: only %d frames painted (need %d)" % (NAMES[i], p["n"], MINFRAMES))
            bad += 1
        elif f32 > BUDGET:
            out("  FAIL  %s: %d of %d frames >= 32 ms (budget %d, slowest %d us)" % (NAMES[i], f32, p["n"], BUDGET, p["mx"]))
            bad += 1
        else:
            out("  OK    %s: %d frames, none >= 32 ms (slowest %d us)" % (NAMES[i], p["n"], p["mx"]))
    return bad


def selftest():
    rows = parse("""wm: bild n=900 mittel=2000 max=40000 ueber16=3 fach=800 50 20 10 10 5 5 0
wm: bild n=300 mittel=900 max=3000 ueber16=0 fach=290 10 0 0 0 0 0 0
wm: bild n=120 mittel=3000 max=12000 ueber16=0 fach=20 30 40 30 0 0 0 0
wm: bild n=200 mittel=3000 max=14000 ueber16=0 fach=20 30 40 30 0 0 0 0
wm: bild n=80 mittel=3000 max=11000 ueber16=0 fach=20 30 20 10 0 0 0 0
wm: bild n=150 mittel=2000 max=9000 ueber16=0 fach=60 50 30 10 0 0 0 0""")
    quiet = []
    clean = judge(rows, quiet.append)
    rows[4]["fach"][6] = 1
    rows[4]["mx"] = 40000
    planted = judge(rows, quiet.append)
    rows[4]["fach"][6] = 0
    rows[3]["n"] = 2
    starved = judge(rows, quiet.append)
    if clean == 0 and planted == 1 and starved == 1:
        print("  OK    selftest: clean green, planted 40 ms frame red, starved phase red")
        return 0
    print("  FAIL  selftest: clean=%d planted=%d starved=%d (want 0 1 1)" % (clean, planted, starved))
    return 1


if sys.argv[1] == "--selftest":
    sys.exit(selftest())
rows = parse(open(sys.argv[1], "rb").read().decode("latin1"))
sys.exit(1 if judge(rows, print) else 0)
