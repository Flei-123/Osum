#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
import re
import sys


def best_after(lines, marker, nth, query):
    start = 0
    if nth > 0:
        seen = 0
        start = None
        for i, line in enumerate(lines):
            if re.search(marker, line):
                seen += 1
                if seen == nth:
                    start = i
                    break
        if start is None:
            return None
    for i in range(start, len(lines)):
        if lines[i].startswith("launcher: search [%s]" % query):
            for line in lines[i + 1:]:
                if line.startswith("launcher: search ["):
                    break
                m = re.match(r"launcher: best name=\[(.*)\]", line)
                if m:
                    return m.group(1)
            return ""
    return None


def main():
    lines = [l.rstrip("\n") for l in open(sys.argv[1], errors="replace")]
    got = best_after(lines, sys.argv[2], int(sys.argv[3]), sys.argv[4])
    print("best=%s" % ("MISSING" if got is None else got))
    return 0 if got is not None else 1


sys.exit(main())
