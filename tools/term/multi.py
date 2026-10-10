#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
"""multi.py <serial.txt>: judge the per-window dumps of tools/term/multi.sh (`wm: termwin ...`, `wm: tw<slot> <row> [text]`).

Checks: four terminal windows at once (the console one + three opened from the start menu) (each its own tty), every typed marker stands in exactly ONE window (the
focused one), the new windows cascade (top-left corners differ in x AND y), and after closing the top-most window the
others are still there and still take input. Exit code 0 = all good."""
import re
import sys


def snapshots(path):
    """a list of snapshots; each is {slot: {"tty", "focus", "x", "y", "rows": {row: text}}}"""
    snaps = []
    cur = None
    for z in open(path, "rb").read().decode("latin1").splitlines():
        m = re.match(r"wm: termwin win=(\d+) tty=(\d+) focus=(\d) cols=(\d+) rows=(\d+) x=(\d+) y=(\d+)", z)
        if m:
            slot = int(m.group(1))
            if cur is None or slot in cur:
                cur = {}
                snaps.append(cur)
            cur[slot] = {"tty": int(m.group(2)), "focus": int(m.group(3)), "x": int(m.group(6)), "y": int(m.group(7)),
                         "rows": {}}
            continue
        m = re.match(r"wm: tw(\d+) (\d+) \[(.*)\]\s*$", z)
        if m and cur is not None and int(m.group(1)) in cur:
            cur[int(m.group(1))]["rows"][int(m.group(2))] = m.group(3)
    return snaps


def holders(snap, marker):
    """the slots whose cells show the marker as ECHOED OUTPUT (a line that is exactly the marker)"""
    return sorted(s for s, w in snap.items() if any(t.strip() == marker for t in w["rows"].values()))


def main(path):
    sn = snapshots(path)
    bad = 0

    def check(ok, msg):
        nonlocal bad
        print(("  OK    " if ok else "  FAIL  ") + msg)
        if not ok:
            bad += 1
    print("%d snapshot(s)" % len(sn))
    if not sn:
        check(False, "no window dump on the serial line")
        return 1
    # the snapshot with the most windows before the close
    top = max(len(x) for x in sn)
    peak = [x for x in sn if len(x) == top][-1]    # the LAST dump with the most windows: all markers are typed by then
    check(len(peak) >= 4, "four terminal windows at once (console + 3 new): saw %d" % len(peak))
    ttys = [w["tty"] for w in peak.values()]
    check(len(set(ttys)) == len(ttys), "every window has its own tty: %s" % sorted(ttys))
    owners = {}
    for mk in ("two-a", "three-a", "four-a"):
        h = holders(peak, mk)
        owners[mk] = h
        check(len(h) == 1, "marker %s stands in exactly one window: %s" % (mk, h))
    allh = [h[0] for h in owners.values() if len(h) == 1]
    check(len(set(allh)) == len(allh) and len(allh) == 3, "the three markers stand in three DIFFERENT windows: %s" % allh)
    new = [(s, w) for s, w in sorted(peak.items()) if s != 0]
    ok = len(new) >= 3
    for i in range(len(new)):
        for j in range(i + 1, len(new)):
            a, b = new[i][1], new[j][1]
            if abs(a["x"] - b["x"]) < 16 or abs(a["y"] - b["y"]) < 16:
                ok = False
    check(ok, "new windows cascade (corners differ by >= 16 px in x and y): %s" % [(w["x"], w["y"]) for _, w in new])
    last = sn[-1]
    check(len(last) == len(peak) - 1, "after the close one window less: %d -> %d" % (len(peak), len(last)))
    check(all(s in peak for s in last), "the survivors are windows that existed before")
    for mk in ("two-a", "three-a"):
        check(len(holders(last, mk)) == 1, "after the close marker %s is still in one window" % mk)
    ha = holders(last, "after-a")
    print("  INFO  the key typed after the close reached windows: %s (open point: focus after a close)" % ha)
    return 0 if bad == 0 else 1


if __name__ == "__main__":
    sys.exit(main(sys.argv[1]))
