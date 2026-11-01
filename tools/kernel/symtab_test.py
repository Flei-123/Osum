#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
import bisect, os, random, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import symtab

elf = sys.argv[1]
lns = symtab.lines(elf)
files = {}
ents = []
for adr, file_2, nr in lns:
    f = files.setdefault(file_2, len(files))
    ents.append((adr & 0xFFFFFFFF, (min(f, 0xFFF) << 20) | min(nr, 0xFFFFF)))
idx, st = symtab.pack_lines(ents)
n = len(ents)
addrs = [a for a, _ in ents]


def flat(a):
    if a < addrs[0]:
        return 0
    return ents[bisect.bisect_right(addrs, a) - 1][1]


bad = 0
probes = [x for a in addrs for x in (a - 1, a, a + 1)]
random.seed(1)
probes += [random.randint(addrs[0] - 100, addrs[-1] + 5000) for _ in range(200000)]
for a in probes:
    if a < 0:
        continue
    if symtab.unpack_line(idx, st, n, a) != flat(a):
        bad += 1
        if bad < 5:
            print("MISMATCH at", hex(a))
print("symtab_test: %d entries, flat %d B -> %d B (index %d + stream %d), %d probes, %d mismatches"
      % (n, n * 8, len(idx) + len(st), len(idx), len(st), len(probes), bad))
sys.exit(1 if bad else 0)
