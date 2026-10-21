#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
"""tools/settingsaudit/runtime.py -- runtime control inventory from the Settings serial trace.

Reads the serial log of tools/settingsui/run.sh (uitrace=yes). The app prints one
`settings: rect name=wXX x= y= w= h=` line per scene control after every page build; a build starts
with the `waa` rect (first node). Per build it counts controls, checks overlaps and out-of-window rects.

  python3 -I tools/settingsaudit/runtime.py <serial.txt> [--limit N] [--md]
"""
import re, sys

R = re.compile(r"settings: rect name=(\w+) x=(-?\d+) y=(-?\d+) w=(\d+) h=(\d+)")
def main():
    path = sys.argv[1]
    limit = int(sys.argv[sys.argv.index("--limit") + 1]) if "--limit" in sys.argv else 12
    md = "--md" in sys.argv
    builds, cur = [], None
    win = None
    for ln in open(path, encoding="latin1", errors="replace"):
        m = R.search(ln)
        if not m:
            continue
        n, x, y, w, h = m.group(1), *map(int, m.groups()[1:])
        if n == "win":
            win = (x, y, w, h)
            continue
        if not re.fullmatch(r"w[a-z]{2}", n):
            continue
        if n == "waa":
            cur = []
            builds.append(cur)
        if cur is not None:
            cur.append((n, x, y, w, h))
    rows = []
    for i, b in enumerate(builds):
        # the search field (wdu-like, x < 260) and sidebar are not page content: keep rects right of the sidebar
        page = [r for r in b if r[1] >= 250 and r[0] != "waa"]
        ov = 0
        for a in range(len(page)):
            for c in range(a + 1, len(page)):
                A, B = page[a], page[c]
                if A[1] < B[1] + B[3] and B[1] < A[1] + A[3] and A[2] < B[2] + B[4] and B[2] < A[2] + A[4]:
                    ov += 1
        rows.append((i, len(page), ov))
    # build 0 = initial window, builds 1..19 = sidebar clicks a..s (PAGE_IDS), the rest = search typing (empty result)
    ids = ["appearance", "screen", "time", "network", "users", "netview", "language", "presets", "accounts", "sync",
           "bridge", "system", "approights", "log", "updates", "mouse", "power", "about", "apps"]
    bad = 0
    for i, n, ov in rows:
        name = "(initial)" if i == 0 else (ids[i - 1] if i - 1 < len(ids) else "(search)")
        print(f"build {i:2d} {name:11s}: page controls={n:3d} overlaps={ov}")
        if ov or (0 < i <= len(ids) and n > limit):
            bad += 1
    pg = [r for r in rows[1:len(ids) + 1]]
    print(f"pages={len(pg)} over_limit({limit})={sum(1 for r in pg if r[1] > limit)} max={max((r[1] for r in pg), default=0)} sum={sum(r[1] for r in pg)}")
    if "--check" in sys.argv and bad:
        sys.exit(1)
main()
