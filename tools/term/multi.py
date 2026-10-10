#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
"""multi.py <serial.txt>: judge the per-window dumps of tools/term/multi.sh (`wm: termwin ...`, `wm: tw<slot> <row> [text]`).

Checks (r528-r530): nine terminal windows at once (the console one + eight opened from the start menu; the old 8-slot tty
table allowed seven), each its own tty, every typed marker stands in exactly ONE window (the focused one), consecutive new
windows do not stack, closing the top-most window twice leaves the others alive AND the next typed line reaches one of them
(focus after a close), three more windows can be opened afterwards (slots given back), and 40 openpty/close rounds (ptytest)
all succeed. Exit code 0 = all good."""
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

    def find(marker):
        """the LAST snapshot in which `marker` stands in some window"""
        hit = [x for x in sn if holders(x, marker)]
        return hit[-1] if hit else None
    print("%d snapshot(s)" % len(sn))
    if not sn:
        check(False, "no window dump on the serial line")
        return 1
    names = ["two-a", "three-a", "four-a", "five-a", "six-a", "seven-a", "eight-a", "nine-a"]
    # --- nine windows at once
    p9 = find("nine-a")
    check(p9 is not None and len(p9) >= 9, "nine terminal windows at once (console + 8 new): saw %d" % (len(p9) if p9 else 0))
    if p9:
        ttys = [w["tty"] for w in p9.values()]
        check(len(set(ttys)) == len(ttys), "every window has its own tty: %s" % sorted(ttys))
        owners = {}
        for mk in names:
            owners[mk] = holders(p9, mk)
        check(all(len(h) == 1 for h in owners.values()), "every marker stands in exactly one window: %s" % owners)
        allh = [h[0] for h in owners.values() if len(h) == 1]
        check(len(set(allh)) == len(names), "the eight markers stand in eight DIFFERENT windows: %s" % allh)
        new = [w for _, w in sorted(p9.items()) if w["tty"] != 0]
        ok = len(new) >= 8
        for a, b in zip(new, new[1:]):
            if abs(a["x"] - b["x"]) < 16 and abs(a["y"] - b["y"]) < 16:
                ok = False    # two consecutive windows on (almost) the same spot
        spots = set((w["x"], w["y"]) for w in new)
        check(ok and len(spots) >= 6, "new windows cascade (consecutive ones differ, >= 6 distinct spots): %s" % sorted(spots))
    # --- focus after a close, twice
    for mk, want in (("after-a", 8), ("after-b", 7)):
        sx = find(mk)
        h = holders(sx, mk) if sx else []
        check(sx is not None and len(sx) == want, "after the close %d windows are left (%s): saw %d" % (want, mk, len(sx) if sx else 0))
        check(len(h) == 1, "the line typed after the close (%s) reached exactly one window: %s" % (mk, h))
        if sx and p9:
            check(all(s in p9 for s in sx), "the survivors are windows that existed before (%s)" % mk)
    s7 = find("after-b")
    if s7:
        for mk in ("two-a", "three-a", "four-a", "five-a", "six-a", "seven-a"):
            check(len(holders(s7, mk)) == 1, "after two closes marker %s is still in one window" % mk)
    # --- slots come back: three more windows
    fin = find("rec-a")
    check(fin is not None and len(fin) == 10, "three more windows after two closes (slots given back): saw %d" % (len(fin) if fin else 0))
    if fin:
        ttys = [w["tty"] for w in fin.values()]
        check(len(set(ttys)) == len(ttys), "final windows have their own ttys: %s" % sorted(ttys))
        hs = [holders(fin, mk) for mk in ("rea-a", "reb-a", "rec-a")]
        check(all(len(h) == 1 for h in hs) and len(set(h[0] for h in hs)) == 3, "the three new markers stand in three different windows: %s" % hs)
    # --- openpty rounds
    txt = open(path, "rb").read().decode("latin1")
    m = re.findall(r"ptytest: ok=(\d+) fail=(\d+)", txt)
    check(bool(m) and m[-1] == ("40", "0"), "ptytest: 40 openpty/close rounds without a failure: %s" % (m[-1] if m else "no line"))
    return 0 if bad == 0 else 1


if __name__ == "__main__":
    sys.exit(main(sys.argv[1]))
