#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
"""tools/zreap/check.py <serial.txt> <label>: prints the number of tasks and
corpses of the last two `ps` listings."""
import re, sys
t = open(sys.argv[1], errors="replace").read()
blocks = [m.start() for m in re.finditer(r"  PID PPID STATE", t)]
for k, b in enumerate(blocks[-2:]):
    rows = []
    for l in t[b:b + 6000].split("\n")[1:]:
        if not l[:5].strip().isdigit():
            break
        rows.append(l)
    z = sum(" zombie " in l for l in rows)
    print("%s ps #%d: %d tasks, %d corpses" % (sys.argv[2], len(blocks) - 1 + k - (1 if len(blocks) > 1 else 0), len(rows), z))
