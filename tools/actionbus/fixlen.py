#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
# tools/actionbus/fixlen.py -- set the length of every `[u8; N] = "..."`
# string array in a Firn source to the exact number of octets of its
# literal. Firn insists on the exact count, and counting by hand is where
# the mistakes are. Idempotent; prints how many declarations it changed.
#
#   python3 tools/actionbus/fixlen.py kernel/user/act.fi [...]
import re
import sys

PAT = re.compile(r'\[u8; *(\d+)\] = "((?:[^"\\]|\\.)*)"')


def octets(lit: str) -> int:
    n = 0
    i = 0
    while i < len(lit):
        c = lit[i]
        if c == '\\':
            i += 2
            n += 1
            continue
        n += len(c.encode('utf-8'))
        i += 1
    return n


def fix(path: str) -> int:
    src = open(path, encoding='utf-8').read()
    changed = 0

    def rep(m):
        nonlocal changed
        want = octets(m.group(2))
        if int(m.group(1)) != want:
            changed += 1
        return '[u8; %d] = "%s"' % (want, m.group(2))

    out = PAT.sub(rep, src)
    if out != src:
        open(path, 'w', encoding='utf-8').write(out)
    return changed


if __name__ == '__main__':
    for p in sys.argv[1:]:
        print('%s: %d fixed' % (p, fix(p)))
