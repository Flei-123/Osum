#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
import re
import sys

FIELD = re.compile(r"taskbar: field (net|snd|battery|mic) x=(\d+) y=\d+ w=(\d+)")
END = re.compile(r"traydrag: end slot=(\d+) saved=(\d+) order=(\d+) hidden=(\d+)")


def read(path):
    return open(path, errors="replace").read().splitlines()


def bar_order(lines):
    last = {}
    for line in lines:
        m = FIELD.search(line)
        if m:
            last[m.group(1)] = (int(m.group(2)), int(m.group(3)))
    shown = [(x, k) for k, (x, w) in last.items() if w > 0]
    return [k for _, k in sorted(shown)]


def window(lines, first_end):
    ends = [i for i, line in enumerate(lines) if END.search(line)]
    if first_end:
        return lines[:ends[0] + 1] if ends else []
    return lines


def main():
    mode, path = sys.argv[1], sys.argv[2]
    lines = read(path)
    if mode == "ends":
        for line in lines:
            m = END.search(line)
            if m:
                print(m.group(1), m.group(2), m.group(3), m.group(4))
    elif mode == "after-first":
        print(" ".join(bar_order(window(lines, True))))
    elif mode == "final":
        print(" ".join(bar_order(lines)))
    elif mode == "count":
        print(sum(1 for line in lines if "traydrag: begin" in line))


if __name__ == "__main__":
    main()
