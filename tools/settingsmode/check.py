#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
import re, sys

serial, outdir = sys.argv[1:3]
raw = open(serial, "rb").read().decode("latin1")
CTL = re.compile(r"^settings: controls page=(\d+) n=(\d+)$", re.M)
RECT = re.compile(r"settings: rect name=(\w+) ")
NET = 3
ENTRY_RECTS = ("wcp", "wcq", "wcr")
EXTRA = 3


def runs(txt):
    seq = [int(m.group(2)) for m in CTL.finditer(txt) if int(m.group(1)) == NET]
    out = []
    for n in seq:
        if not out or out[-1] != n:
            out.append(n)
    return out


def judge(txt):
    res = []

    def ok(c, m):
        res.append((bool(c), m))

    r = runs(txt)
    ok(len(r) >= 3, "network page built in 3 states (%s)" % r)
    if len(r) >= 3:
        m, a, b = r[0], r[1], r[2]
        ok(m == a + EXTRA, "fixed address shows %d more controls than automatic (%d vs %d)" % (EXTRA, m, a))
        ok(b == m, "fixed address again returns to %d controls (%d)" % (m, b))
        ok(a <= 8 and m <= 8, "both states within the limit of 8 (%d, %d)" % (a, m))
    names = set(RECT.findall(txt))
    ok(all(n in names for n in ENTRY_RECTS), "address entry rects reported with the fixed address")
    ok(not re.search(r"ABSTURZ|EXCEPTION", txt), "no crash lines")
    return res


def main():
    res = judge(raw)
    for c, m in res:
        print("  %s  %s" % ("OK  " if c else "FAIL", m))
    bad = sum(1 for c, _ in res if not c)
    ok_n = len(res) - bad
    doctored = {
        "same count every state": CTL.sub(lambda m: "settings: controls page=%s n=6" % m.group(1), raw),
        "no controls": "\n".join(l for l in raw.splitlines() if not l.startswith("settings: controls ")),
        "no entry rects": re.sub(r"settings: rect name=wc[pqr] ", "settings: rect name=zzz ", raw),
    }
    for name, d in doctored.items():
        if all(c for c, _ in judge(d)):
            print("  FAIL  counter-proof not red: %s" % name)
            bad += 1
        else:
            print("  OK    counter-proof red: %s" % name)
            ok_n += 1
    print("SETTINGSMODE: %d passed, %d failed" % (ok_n, bad))
    sys.exit(1 if bad else 0)


main()
