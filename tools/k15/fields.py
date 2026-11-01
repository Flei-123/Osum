#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
"""Usage:
    fields.py <mitschnitt> e1|e2
"""
import re
import sys

PAT = re.compile(r"e1=\[([^\]]*)\] e2=\[([^\]]*)\]")


def main():
    if len(sys.argv) < 3:
        print(__doc__)
        return 2
    welches = sys.argv[2]
    treffer = None
    with open(sys.argv[1], "rb") as f:
        for roh in f:
            m = PAT.search(roh.decode("latin-1"))
            if m:
                treffer = m
    if treffer is None:
        return 1
    print(treffer.group(1) if welches == "e1" else treffer.group(2))
    return 0


if __name__ == "__main__":
    sys.exit(main())
