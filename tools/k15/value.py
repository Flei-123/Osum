#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
"""Usage:
    value.py <mitschnitt> <zeilenanfang> <key> [rgb]
"""
import re
import sys


def main():
    if len(sys.argv) < 4:
        print(__doc__)
        return 2
    path_2, begin, key = sys.argv[1], sys.argv[2], sys.argv[3]
    alsrgb = len(sys.argv) > 4 and sys.argv[4] == "rgb"
    pat = re.compile(r"(?:^|\s)%s=(-?\d+)" % re.escape(key))
    treffer = None
    with open(path_2, "rb") as f:
        for roh in f:
            z = roh.decode("latin-1").rstrip("\n")
            if not z.startswith(begin):
                continue
            m = pat.search(z)
            if m:
                treffer = int(m.group(1))
    if treffer is None:
        return 1
    if alsrgb:
        print("%d %d %d" % ((treffer >> 16) & 255, (treffer >> 8) & 255,
                            treffer & 255))
    else:
        print(treffer)
    return 0


if __name__ == "__main__":
    sys.exit(main())
