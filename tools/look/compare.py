#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
"""tools/look/compare.py -- two ./test.sh logs, section by section.

    compare.py <before.log> <after.log>

ONLY WHAT IS NEWLY RED COUNTS AS DAMAGE. A section that was already
failing on the branch this round forked from is not this round's doing,
and a round that reports it as its own failure is hiding the ones that
are. So this prints every section that BOTH logs reached, side by side,
and marks only the ones where the after-log has MORE failures.

Exit 0 when nothing is newly red.
"""
import re
import sys


def parse(path):
    out = {}
    cur = None
    for ln in open(path, encoding="utf-8", errors="replace"):
        m = re.match(r"^== (\d+)\. (.*?) ==", ln)
        if m:
            cur = int(m.group(1))
            continue
        m = re.search(r"^\s{0,3}([A-ZÄÖÜ0-9]+): (\d+) "
                      r"(?:passed|bestanden|proofs), (\d+) "
                      r"(?:failed|durchgefallen|failures)", ln)
        if m and cur is not None:
            out.setdefault(cur, []).append(
                (m.group(1), int(m.group(2)), int(m.group(3))))
    return out


def main(a):
    if len(a) < 2:
        print(__doc__)
        return 2
    b, c = parse(a[0]), parse(a[1])
    worse = 0
    both = 0
    for k in sorted(set(b) | set(c)):
        bs, cs = b.get(k), c.get(k)
        fmt = lambda v: ("--" if not v else
                         "  ".join("%s %d/%d" % t for t in v))
        mark = ""
        if bs and cs:
            both += 1
            bf = sum(t[2] for t in bs)
            cf = sum(t[2] for t in cs)
            if cf > bf:
                mark = "   <== NEWLY RED"
                worse += 1
            elif cf < bf:
                mark = "   (improved)"
        elif not cs:
            mark = "   (after: not reached)"
        print("%3d  %-42s | %-42s%s" % (k, fmt(bs), fmt(cs), mark))
    print("")
    print("sections in both logs: %d   newly red: %d" % (both, worse))
    return 0 if worse == 0 else 1


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
