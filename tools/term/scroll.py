#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
"""tools/term/scroll.py -- judge the serial line of tools/term/scroll.sh (r838: terminal scrollback).

Serial witnesses: `wm: termsb lines=N view=V` (stored history lines, lines the view is scrolled back) and, while V > 0,
`wm: termview R [text]` (what stands on screen row R). Live rows come as `wm: termzeile R [text]`."""
import re
import sys

MARK = re.compile(r"sbmark-(\d+)")


def judge(path):
    txt = open(path, "rb").read().decode("latin1")
    recs = []
    live = []
    cur = None
    for z in txt.split("\n"):
        z = z.rstrip("\r")
        m = re.match(r"wm: termzeile (\d+) \[(.*)\]\s*$", z)
        if m:
            live += [int(k) for k in MARK.findall(m.group(2))]
            continue
        m = re.match(r"wm: termsb lines=(\d+) view=(\d+)", z)
        if m:
            cur = {"n": int(m.group(1)), "v": int(m.group(2)), "live": live, "view": []}
            live = []
            recs.append(cur)
            continue
        m = re.match(r"wm: termview (\d+) \[(.*)\]\s*$", z)
        if m and cur is not None:
            cur["view"] += [int(k) for k in MARK.findall(m.group(2))]
    bad = 0

    def check(ok, msg):
        nonlocal bad
        print(("  OK    " if ok else "  FAIL  ") + msg)
        if not ok:
            bad += 1
    print("        %d dumps: %s" % (len(recs), [(r["n"], r["v"]) for r in recs][:40]))
    check(len(recs) > 0, "the terminal window reports its scrollback (`wm: termsb`)")
    if not recs:
        return 1
    mx = max(r["n"] for r in recs)
    check(mx >= 20, "lines that scrolled off the top were stored: %d" % mx)
    back = [r for r in recs if r["v"] > 0]
    check(len(back) > 0, "the wheel moved the view back (some dump has view > 0)")
    if back:
        b0 = back[0]
        i0 = recs.index(b0)
        lv = [r for r in recs[:i0] if r["v"] == 0 and r["live"]][-1:]
        lo_live = min(lv[0]["live"]) if lv else 999  # the live screen just before the first wheel step
        check(len(b0["view"]) > 0, "the scrolled view shows history rows: %s" % b0["view"][:6])
        check(bool(b0["view"]) and min(b0["view"]) < lo_live, "the scrolled view shows OLDER markers than the live screen (%s < %d)"
              % (min(b0["view"]) if b0["view"] else "-", lo_live))
        deep = max(back, key=lambda r: r["v"])
        check(deep["v"] > back[0]["v"] or deep["v"] >= mx - 1, "scrolling far up reaches the oldest stored line (view %d of %d)" % (deep["v"], mx))
        check(bool(deep["view"]) and min(deep["view"]) <= 3, "the top of the history shows the first markers: %s" % deep["view"][:4])
        # after the last wheel-up the Esc key must snap back
        last = recs[-1]
        check(last["v"] == 0, "after a key the view is back on the live screen (last dump view=%d)" % last["v"])
        ibk = [i for i, r in enumerate(recs) if r["v"] > 0]
        down = [r for r in recs[ibk[0]:] if r["v"] == 0]
        check(len(down) > 0, "wheel down returns to the live screen")
        # r839: Shift+PageUp / Shift+PageDown (last two steps of scroll.txt): after the Esc snap-back one key = one page
        # (rows - 1 lines), the second key = back on the live screen. The jump is exactly one page, unlike the wheel steps.
        rows = [int(k) for k in re.findall(r"wm: termgeo .*? rows=(\d+)", txt)]
        page = (rows[-1] - 1) if rows else 0
        runs = []  # maximal runs of dumps with view > 0
        for i, r in enumerate(recs):
            if r["v"] > 0:
                if runs and runs[-1][-1] == i - 1:
                    runs[-1].append(i)
                else:
                    runs.append([i])
        last_run = runs[-1]
        pv = sorted(set(recs[i]["v"] for i in last_run))
        check(page > 0 and pv == [page], "Shift+PageUp moved the view back by exactly one page (view %s, page = rows-1 = %d)" % (pv, page))
        pview = [m for i in last_run for m in recs[i]["view"]]
        before = [r for r in recs[:last_run[0]] if r["v"] == 0 and r["live"]][-1:]
        lo = min(before[0]["live"]) if before else 999
        check(bool(pview) and min(pview) < lo, "the paged view shows OLDER markers than the live screen (%s < %d)"
              % (min(pview) if pview else "-", lo))
        check(last_run[-1] < len(recs) - 1 and all(r["v"] == 0 for r in recs[last_run[-1] + 1:]),
              "Shift+PageDown returned the view to the live screen (view 0 after the page phase)")
        check(last_run[0] > 0 and recs[last_run[0] - 1]["v"] == 0, "the page phase starts from the live screen (Esc snapped back first)")
    return 0 if bad == 0 else 1


if __name__ == "__main__":
    sys.exit(judge(sys.argv[1]))
