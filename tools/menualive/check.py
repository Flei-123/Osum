#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
"""tools/menualive/check.py -- measurements for tools/menualive/run.sh.

    check.py cpu  <serial.txt> <task-name>   share of one core, from two `ps`
    check.py diff <a.ppm> <b.ppm> x0 y0 x1 y1  changed pixels in a rectangle

`cpu`: the last two `ps` listings on the serial line. Every task's ticks are
subtracted; the time that passed is the sum of all gains (one core), so the
share is gain(task) / sum -- no clock of the host involved. Prints `share=<percent>`, exit 0 always (the caller decides).
"""
import re
import sys


def blocks(path):
    """The `ps` listings the terminal showed. The kernel copies the terminal
    window to the serial line every five seconds as `wm: termzeile N [text]`
    (one dump = the lines in a row); a dump with the ps header is a listing."""
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
    # One core (the eh6 machine): everything that ran adds up to the time that
    # passed. With more cores the sum is larger and the share comes out
    # SMALLER, so a pass is never faked by it.
    span = sum(max(0, b[k][1] - a[k][1]) for k in b if k in a)
    gain = sum(b[k][1] - a[k][1] for k in b if k in a and b[k][2] == name)
    if span <= 0:
        print("share=-1 (no idle gain)")
        return 1
    print("task=%s gain=%d span=%d share=%.1f" % (name, gain, span, 100.0 * gain / span))
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
    if sys.argv[1] == "diff":
        sys.exit(diff(sys.argv[2], sys.argv[3], *[int(v) for v in sys.argv[4:8]]))
    sys.exit(2)
