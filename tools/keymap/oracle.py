#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
"""tools/keymap/oracle.py -- compare the kernel keyboard engine (dump of tools/keymap/host.fi) with libxkbcommon.

    oracle.py <dump.txt>

Prints one line per section: "OK <what> (<n> checks)" or "FAIL <what> (<bad> of <n>)" plus the first mismatches.
Exit status 1 if any section failed.
"""
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, "..", "hid"))
import kbdgen
import xkbq

SLOT_SET = set(kbdgen.SLOTS)
DEAD_FLAG = kbdgen.DEAD_FLAG
SHOW = 6


def parse(path):
    rows = {"L": [], "D": [], "DD": [], "DX": [], "C": [], "S": []}
    head = None
    with open(path) as fh:
        for line in fh:
            parts = line.split()
            if not parts:
                continue
            if parts[0] == "COUNT":
                head = {parts[i]: int(parts[i + 1]) for i in range(0, len(parts), 2)}
            elif parts[0] in rows:
                rows[parts[0]].append([int(x) for x in parts[1:]])
    return head, rows


class Report:
    def __init__(self):
        self.failed = 0

    def section(self, what, total, bad):
        if bad:
            self.failed += 1
            print("FAIL %s (%d of %d)" % (what, len(bad), total))
            for b in bad[:SHOW]:
                print("     " + b)
        else:
            print("OK   %s (%d checks)" % (what, total))


def expected_entry(km, scan, shift, altgr, caps):
    if scan not in SLOT_SET:
        return 0
    return kbdgen.entry_of(km.sym(scan, shift, altgr, caps))


def check_layouts(rows, spacing, rep):
    maps = {}
    bad = []
    total = 0
    for lay, code, level, entry, ch in rows:
        if lay not in maps:
            name, layout, variant = kbdgen.LAYOUTS[lay]
            maps[lay] = (name, xkbq.Keymap(layout, variant))
        name, km = maps[lay]
        want = expected_entry(km, code, level & 1, (level >> 1) & 1, (level >> 2) & 1)
        want_ch = want
        if want & DEAD_FLAG:
            sp = spacing.get(want & 0xFFFF, 0)
            if sp == 0:
                want = 0
                want_ch = 0
            else:
                want_ch = sp
        total += 1
        if entry != want or ch != want_ch:
            bad.append("%s code=0x%02X level=%d: kernel entry=%d char=%d, xkb entry=%d char=%d"
                       % (name, code, level, entry, ch, want, want_ch))
    rep.section("layout tables: every key x every level x caps vs xkb (%d layouts)" % len(maps), total, bad)
    return len(maps)


def check_dead(rows, dd, dx, spacing, comp, rep):
    bad = []
    total = 0
    skipped = 0
    for ident, base, pend, first, second in rows:
        sp = spacing[ident]
        sym = xkbq.DEAD_FIRST + ident
        ks = xkbq.cp_keysym(base)
        if base == 32:
            want = (0, sp, 0)
        else:
            status, text = comp.run([sym, ks])
            if status == xkbq.COMPOSED and len(text) == 1 and ord(text) != base:
                want = (0, ord(text), 0)
            elif status == xkbq.COMPOSED:
                skipped += 1
                continue
            elif status == xkbq.CANCELLED or status == 0:
                want = (0, sp, base)
            else:
                skipped += 1
                continue
        total += 1
        if (pend, first, second) != want:
            bad.append("dead id=%d base=U+%04X: kernel=%s want=%s" % (ident, base, (pend, first, second), want))
    rep.section("dead key + base char vs xkb compose, both ways (skipped %d multi-char/prefix)" % skipped, total, bad)
    bad = []
    for ident, a, b in dd:
        if (a, b) != (0, spacing[ident]):
            bad.append("double dead id=%d: kernel=%s want spacing %d" % (ident, (a, b), spacing[ident]))
    rep.section("dead key twice gives the accent alone", len(dd), bad)
    bad = []
    for i1, i2, x0, x1, x2 in dx:
        sym2 = xkbq.DEAD_FIRST + i2
        status, text = comp.run([sym2, xkbq.cp_keysym(65)])
        if status == xkbq.COMPOSED and len(text) == 1:
            want2 = ord(text)
        else:
            want2 = spacing[i2] | (65 << 24)
        if (x0, x1, x2) != (0, spacing[i1], want2):
            bad.append("dead %d then dead %d then A: kernel=%s want=%s" % (i1, i2, (x0, x1, x2), (0, spacing[i1], want2)))
    rep.section("two different dead keys: first accent out, second stays pending", len(dx), bad)


def check_compose(rows, comp, rep):
    bad = []
    composed = 0
    for a, b, r0, r1, after in rows:
        status, text = comp.run([xkbq.MULTI_KEY, xkbq.cp_keysym(a), xkbq.cp_keysym(b)])
        want = 0
        if status == xkbq.COMPOSED and len(text) == 1:
            want = ord(text)
            composed += 1
        if (r0, r1, after) != (0, want, 97):
            bad.append("compose %s %s: kernel=%s want=%s" % (chr(a), chr(b), (r0, r1, after), (0, want, 97)))
    rep.section("compose key + 2 chars vs xkb compose (%d sequences compose)" % composed, len(rows), bad)
    return composed


def main():
    head, rows = parse(sys.argv[1])
    spacing = {r[0]: r[1] for r in rows["S"]}
    rep = Report()
    comp = xkbq.Compose()
    check_layouts(rows["L"], spacing, rep)
    check_dead(rows["D"], rows["DD"], rows["DX"], spacing, comp, rep)
    composed = check_compose(rows["C"], comp, rep)
    if composed < 200:
        rep.failed += 1
        print("FAIL too few compose sequences (%d)" % composed)
    sys.exit(1 if rep.failed else 0)


if __name__ == "__main__":
    main()
