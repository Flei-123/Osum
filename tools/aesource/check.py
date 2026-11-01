#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
import re
import sys

PREFIX = re.compile(r"^AE\d ")


def last_dump(path):
    rows = {}
    wide = {}
    previous = -1
    for line in open(path, "rb").read().decode("latin1").splitlines():
        m = re.match(r"wm: termzeile (\d+) \[(.*)\]\s*$", line)
        if m:
            row = int(m.group(1))
            if row <= previous:
                rows = {}
                wide = {}
            previous = row
            rows[row] = m.group(2)
            continue
        m = re.match(r"wm: termwide (\d+) (\d+) (\d+)\s*$", line)
        if m:
            wide[(int(m.group(1)), int(m.group(2)))] = int(m.group(3))
    return rows, wide


def rebuild(rows, wide):
    out = {}
    for row, text in rows.items():
        cells = []
        for col, ch in enumerate(text):
            cp = wide.get((row, col))
            cells.append(chr(cp) if cp is not None else ch)
        out[row] = "".join(cells)
    return out


def main(serial, source):
    expected = [l.rstrip("\n") for l in open(source, encoding="utf-8")]
    rows, wide = last_dump(serial)
    lines = rebuild(rows, wide)
    bad = 0
    print("wide cells in the last dump: %d" % len(wide))
    for want in expected:
        hit = [r for r, t in lines.items() if t == want]
        if hit:
            print("ROW %d %s" % (hit[-1], want))
        else:
            bad += 1
            print("MISSING %s" % want)
    return 1 if bad or not wide else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1], sys.argv[2]))
