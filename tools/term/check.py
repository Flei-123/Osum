#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
"""tools/term/check.py <serial.txt> -- read the cell dumps of the terminal window (`wm: termzeile N [text]`) and judge them.

A dump is a block of consecutive `wm: termzeile` lines (rows of one moment). For every dump: a row that contains an
escape-sequence remnant as plain text (`[7m`, `[K`, `[?25h`, `[19;1H`, `[m`) is a failure. The last dump that shows the editor's
help line (`^O Write`) proves the editor was on screen. Exit code 0 = good.
"""
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


def main(path):
    bad = 0
    saw_editor = False
    ds = dumps(path)
    print("%d dump(s) of the window" % len(ds))
    for n, d in enumerate(ds):
        raw = [(r, t) for r, t in d if REMNANT.search(t)]
        ed = any("^O Write" in t for r, t in d)
        if ed:
            saw_editor = True
            print("EDITOR-SCREEN dump %d (%d rows)" % (n, len(d)))
        for r, t in raw:
            print("RAW dump %d row %d: %s" % (n, r, t[:100]))
            bad += 1
    if not saw_editor:
        print("no dump shows the editor (`^O Write`)")
        return 1
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1]))
