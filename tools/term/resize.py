#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
"""resize.py <serial.txt>: the last cell dump must hold the editor help line on the LAST row, and the grid must have grown."""
import re, sys
sys.path.insert(0, __file__.rsplit("/", 1)[0])
import check
ds = check.dumps(sys.argv[1])
grids = []
for z in open(sys.argv[1], "rb").read().decode("latin1").splitlines():
    m = re.search(r"wm: term win=\d+\s+cols=(\d+)\s+rows=(\d+)", z)
    if m:
        grids.append((int(m.group(1)), int(m.group(2))))
    m = re.search(r"kgui: winch win=\d+ .*cols=(\d+) rows=(\d+)", z)
    if m:
        grids.append((int(m.group(1)), int(m.group(2))))
print("grids seen:", grids[-4:])
helps = [d for d in ds if any("^O Write" in t for _, t in d)]
if not helps or not grids:
    print("no editor dump"); sys.exit(1)
last = helps[-1]
row = [r for r, t in last if "^O Write" in t][0]
rows = max(r for r, _ in last) + 1
print("help line on row %d of %d" % (row, rows), "grid rows", grids[-1][1])
sys.exit(0 if row >= grids[-1][1] - 2 and grids[-1][1] > 20 else 1)
