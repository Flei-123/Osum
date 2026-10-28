#!/usr/bin/env python3
import re
import sys


def snapshots(path):
    snaps = []
    cur = None
    for z in open(path, "rb").read().decode("latin1").splitlines():
        m = re.match(r"wm: termwin win=(\d+) tty=(\d+) focus=(\d) cols=(\d+) rows=(\d+)", z)
        if m:
            slot = int(m.group(1))
            if cur is None or slot in cur:
                cur = {}
                snaps.append(cur)
            cur[slot] = {}
            continue
        m = re.match(r"wm: tw(\d+) (\d+) \[(.*)\]\s*$", z)
        if m and cur is not None and int(m.group(1)) in cur:
            cur[int(m.group(1))][int(m.group(2))] = m.group(3)
    return snaps


KEYS = ["mode", "checks", "bad", "unstable", "pending", "skipped", "px", "card_checks", "card_bad", "x0", "y0", "x1", "y1", "win", "us", "renders"]


def keys_in(rows):
    found = []
    for r in sorted(rows):
        m = re.search(r"pixelguard\.(\w+)", rows[r])
        if m:
            found.append(m.group(1))
    return found


def main(path):
    snaps = snapshots(path)
    print("%d snapshot(s)" % len(snaps))
    seen = 0
    last = None
    for n, snap in enumerate(snaps):
        for slot, rows in snap.items():
            found = keys_in(rows)
            if not found:
                continue
            seen += 1
            missing = [k for k in KEYS if k not in found]
            print("snapshot %d win %d: %d pixelguard rows, missing %s" % (n, slot, len(found), missing))
            last = (n, slot, missing)
    if seen == 0:
        print("FAIL no pixelguard rows in any dump")
        return 1
    if last[2]:
        print("FAIL rows lost in the final dump: %s" % last[2])
        return 1
    return 0


sys.exit(main(sys.argv[1]))
