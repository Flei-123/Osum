#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
import re, sys

CTL = re.compile(r"^settings: controls page=(\d+) n=(\d+)$", re.M)
LIMIT = 8


def declared(routes_path, map_path):
    counts, cur = {}, None
    for ln in open(routes_path, encoding="utf-8"):
        w = ln.split()
        if len(w) >= 2 and w[0] == "route":
            cur = w[1]
        elif len(w) == 2 and w[0] == "controls" and cur:
            counts[cur] = int(w[1])
    pages = {}
    for ln in open(map_path, encoding="utf-8"):
        w = ln.split()
        if len(w) == 3 and w[0] == "page":
            pages[int(w[1])] = w[2]
    return counts, pages


def measured(serial):
    txt = open(serial, "rb").read().decode("latin1")
    out = {}
    for m in CTL.finditer(txt):
        p, n = int(m.group(1)), int(m.group(2))
        out[p] = max(out.get(p, 0), n)
    return out


def judge(counts, pages, meas):
    rows, bad = [], 0
    for p in sorted(meas):
        uri = pages.get(p)
        dec = counts.get(uri) if uri else None
        n = meas[p]
        flag = ""
        if dec is None:
            flag = "NO-DECLARATION"
        elif n > dec:
            flag = "UNDER-DECLARED"
        if n > LIMIT:
            flag = (flag + " OVER-LIMIT").strip()
        if flag:
            bad += 1
        rows.append((p, uri, dec, n, flag))
    return rows, bad


def main():
    serial, routes_path, map_path = sys.argv[1:4]
    counts, pages = declared(routes_path, map_path)
    rows, bad = judge(counts, pages, measured(serial))
    for p, uri, dec, n, flag in rows:
        print("page %2d %-42s declared=%s measured=%d %s" % (p, uri, dec, n, flag))
    print("DECLARED: %d pages, %d mismatches" % (len(rows), bad))
    if "--check" in sys.argv and bad:
        sys.exit(1)


main()
