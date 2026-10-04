#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
"""tools/zreap/check.py <serial.txt> <label>: tasks and corpses of the last two
`ps` listings (raw lines or the terminal dump `wm: termzeile N [ ... ]`)."""
import re, sys
t = open(sys.argv[1], errors="replace").read().split("\n")
heads = [i for i, l in enumerate(t) if "PID PPID STATE" in l]
row = re.compile(r"(\d+)\s+(\d+)\s+(ready|run|sleep|wait|zombie|new|stop|poll)\s+(\w+)")
for n, h in enumerate(heads[-2:]):
    rows = []
    for l in t[h + 1:h + 80]:
        m = row.search(l)
        if m:
            rows.append(m)
        elif rows and not l.strip().startswith(("wm: termzeile", "osum$")):
            break
    z = sum(m.group(3) == "zombie" for m in rows)
    print("%s ps (%d of %d): %d tasks, %d corpses" % (sys.argv[2], n + 1, len(heads), len(rows), z))
