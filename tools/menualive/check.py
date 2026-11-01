#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
import re
import sys


def blocks(path):
    dumps, cur = [], []
    for l in open(path, errors="replace"):
        m = re.match(r"wm: termzeile (\d+) \[(.*)\]\s*$", l)
        if m:
            cur.append(m.group(2))
        elif cur:
            dumps.append(cur)
            cur = []
    if cur:
        dumps.append(cur)
    out = []
    for dmp in dumps:
        d = {}
        for l in dmp:
            m = re.match(r"\s*(\d+)\s+(\d+)\s+(\w+)\s+(\w+)\s+(\d+)\s+(\d+)\s+real\s*(\S*)", l)
            if m:
                d[int(m.group(1))] = (m.group(4), int(m.group(6)), m.group(7))
        if len(d) >= 5 and (not out or out[-1] != d):
            out.append(d)
    return out


def cpu(path, name):
    bl = blocks(path)
    if len(bl) < 2:
        print("share=-1 (fewer than two ps listings: %d)" % len(bl))
        return 1
    a, b = bl[0], bl[-1]
    span = sum(max(0, b[k][1] - a[k][1]) for k in b if k in a)
    if name.startswith("notkind:"):
        gain = sum(b[k][1] - a[k][1] for k in b if k in a and b[k][0] != name[8:])
    elif name.startswith("pid:"):
        gain = sum(b[k][1] - a[k][1] for k in b if k in a and k == int(name[4:]))
    elif name.startswith("kind:"):
        gain = sum(b[k][1] - a[k][1] for k in b if k in a and b[k][0] == name[5:])
    else:
        gain = sum(b[k][1] - a[k][1] for k in b if k in a and b[k][2] == name)
    if span <= 0:
        print("share=-1 (no idle gain)")
        return 1
    print("task=%s gain=%d span=%d share=%.1f" % (name, gain, span, 100.0 * gain / span))
    return 0


def table(path):
    bl = blocks(path)
    if len(bl) < 2:
        print("share=-1 (fewer than two ps listings: %d)" % len(bl))
        return 1
    a, b = bl[0], bl[-1]
    span = sum(max(0, b[k][1] - a[k][1]) for k in b if k in a)
    if span <= 0:
        print("share=-1 (no idle gain)")
        return 1
    rows = []
    for k in b:
        if k in a and b[k][0] != "idle" and b[k][1] > a[k][1]:
            rows.append((100.0 * (b[k][1] - a[k][1]) / span, k, b[k][0], b[k][2]))
    for sh, k, kind, nm in sorted(rows, reverse=True):
        print("pid=%d kind=%s name=%s share=%.1f" % (k, kind, nm, sh))
    return 0


def diff(a, b, x0, y0, x1, y1):
    from PIL import Image
    ia = Image.open(a).convert("RGB")
    ib = Image.open(b).convert("RGB")
    pa, pb = ia.load(), ib.load()
    n = 0
    for y in range(y0, min(y1, ia.size[1])):
        for x in range(x0, min(x1, ia.size[0])):
            if pa[x, y] != pb[x, y]:
                n += 1
    print("changed=%d" % n)
    return 0


if __name__ == "__main__":
    if sys.argv[1] == "cpu":
        sys.exit(cpu(sys.argv[2], sys.argv[3]))
    if sys.argv[1] == "table":
        sys.exit(table(sys.argv[2]))
    if sys.argv[1] == "diff":
        sys.exit(diff(sys.argv[2], sys.argv[3], *[int(v) for v in sys.argv[4:8]]))
    sys.exit(2)
