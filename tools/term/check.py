#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
import re
import sys

REMNANT = re.compile(r"\[[0-9;?]*[A-Za-z]")


def dumps(path):
    cur = []
    out = []
    for z in open(path, "rb").read().decode("latin1").splitlines():
        m = re.match(r"wm: termzeile (\d+) \[(.*)\]\s*$", z)
        if m:
            if cur and int(m.group(1)) <= cur[-1][0]:
                out.append(cur)
                cur = []
            cur.append((int(m.group(1)), m.group(2)))
        elif cur and not z.startswith("wm: termzeile"):
            pass
    if cur:
        out.append(cur)
    return out


def grid_size(path):
    cols = rows = 0
    for z in open(path, "rb").read().decode("latin1").splitlines():
        m = re.search(r"wm: term win=\d+\s+cols=(\d+)\s+rows=(\d+)", z)
        if m:
            cols, rows = int(m.group(1)), int(m.group(2))
    return cols, rows


def main(path):
    bad = 0
    saw_editor = False
    ds = dumps(path)
    cols, rows = grid_size(path)
    print("window grid: %d columns x %d rows" % (cols, rows))
    print("%d dump(s) of the window" % len(ds))
    for n, d in enumerate(ds):
        raw = [(r, t) for r, t in d if REMNANT.search(t)]
        ed = any("^O Write" in t for r, t in d)
        if ed:
            saw_editor = True
            print("EDITOR-SCREEN dump %d (%d rows)" % (n, len(d)))
            hrow = max(r for r, t in d if "^O Write" in t)
            last = max(r for r, t in d)
            if rows and not (rows - 2 <= hrow <= rows - 1):
                print("SIZE dump %d: the help line stands on row %d, the window has %d rows" % (n, hrow, rows))
                bad += 1
            if rows and last > rows - 1:
                print("SIZE dump %d: a row %d beyond the window" % (n, last))
                bad += 1
            for r, t in d:
                if cols and len(t.rstrip()) > cols:
                    print("SIZE dump %d row %d: %d characters in a window of %d columns" % (n, r, len(t.rstrip()), cols))
                    bad += 1
        for r, t in raw:
            print("RAW dump %d row %d: %s" % (n, r, t[:100]))
            bad += 1
    if not saw_editor:
        print("no dump shows the editor (`^O Write`)")
        return 1
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1]))
