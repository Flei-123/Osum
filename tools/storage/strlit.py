#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
"""Usage:
    python3 tools/storage/strlit.py <file.fi> [--verify]
"""
import re
import sys

MUSTER = re.compile(
    r'^(\s*(?:var|static mut)\s+\w+\s*:\s*\[u8;\s*(\d+)\s*\]\s*=\s*)"(.*)"(\s*)$'
)


def oktette(lit):
    n = 0
    i = 0
    while i < len(lit):
        if lit[i] == '\\':
            i += 2
        else:
            i += 1
        n += 1
    return n


def main(argv):
    if len(argv) < 2:
        print(__doc__)
        return 2
    path_2 = argv[1]
    only_check = "--verify" in argv
    rows = open(path_2, encoding="utf-8").read().split("\n")
    aus = []
    geaendert = 0
    zu_lang = []
    for nr, z in enumerate(rows, 1):
        m = MUSTER.match(z)
        if not m:
            aus.append(z)
            continue
        header, will, lit, tail = (m.group(1), int(m.group(2)),
                                    m.group(3), m.group(4))
        ist = oktette(lit)
        if ist > will:
            zu_lang.append((nr, ist, will, lit))
            aus.append(z)
            continue
        if ist == will:
            aus.append(z)
            continue
        aus.append('%s"%s"%s' % (header, lit + "\\0" * (will - ist), tail))
        geaendert += 1
    for nr, ist, will, lit in zu_lang:
        print("%s:%d: %d octets, but [u8; %d] -- too long: %s"
              % (path_2, nr, ist, will, lit), file=sys.stderr)
    if zu_lang:
        return 1
    if geaendert and not only_check:
        open(path_2, "w", encoding="utf-8").write("\n".join(aus))
    print("%s: %d Literale aufgefuellt" % (path_2, geaendert))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
