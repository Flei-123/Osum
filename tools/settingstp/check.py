#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
import re, sys

serial = sys.argv[1]
raw = open(serial, "rb").read().decode("latin1")
CTL = re.compile(r"^settings: controls page=(\d+) n=(\d+)$", re.M)
TP = re.compile(r"^settings: touchpad ((?:\d+,){10}\d+) i=(\d+) ok=(\d)", re.M)
RECT = re.compile(r"settings: rect name=(\w+) ")
PAGE = 30
NAMES = ("tptap", "tptap2", "tpdrag", "tpcorner", "tpnat", "tpscroll", "tpmom", "tppinch", "tpspd", "tpsw3", "tpsw4")


def rows(txt):
    return [([int(x) for x in m.group(1).split(",")], int(m.group(2)), int(m.group(3))) for m in TP.finditer(txt)]


def judge(txt):
    res = []

    def ok(c, m):
        res.append((bool(c), m))

    ctl = [int(m.group(2)) for m in CTL.finditer(txt) if int(m.group(1)) == PAGE]
    ok(ctl, "Touchpad page built (page=30)")
    ok(ctl and max(ctl) == 11, "Touchpad page has 11 controls (%s)" % ctl)
    names = set(RECT.findall(txt))
    for n in NAMES:
        ok(n in names, "control rect %s reported" % n)
    r = rows(txt)
    ok(len(r) >= 4, "four changes reported (%d)" % len(r))
    by = {}
    for v, i, o in r:
        by.setdefault(i, []).append((v, o))
    ok(0 in by and by[0][-1][0][0] == 0, "tap toggled off (i=0)")
    ok(4 in by and by[4][-1][0][4] == 1, "natural scrolling toggled on (i=4)")
    ok(8 in by and 10 <= by[8][-1][0][8] <= 500 and by[8][-1][0][8] != 100,
       "speed slider click sets a new value in 10..500 (%s)" % (by.get(8, [])[-1:],))
    ok(9 in by and by[9][-1][0][9] == 0, "3-finger swipe toggled off (i=9)")
    ok(r and r[-1][0][0] == 0 and r[-1][0][4] == 1 and r[-1][0][9] == 0,
       "last line carries all four changes together (%s)" % (r[-1:],))
    ok(r and all(o == 1 for _, _, o in r), "every change stored (ok=1: bus or file)")
    ok(r and all(len(v) == 11 and all(x >= 0 for x in v) for v, _, _ in r), "eleven sane values per line")
    ok(r and all(x in (0, 1) for v, _, _ in r for x in v[:8]), "toggles are 0 or 1")
    ok(not re.search(r"ABSTURZ|EXCEPTION", txt), "no crash lines")
    return res


def main():
    res = judge(raw)
    for c, m in res:
        print("  %s  %s" % ("OK  " if c else "FAIL", m))
    bad = sum(1 for c, _ in res if not c)
    ok_n = len(res) - bad
    doctored = {
        "no touchpad lines": "\n".join(l for l in raw.splitlines() if not l.startswith("settings: touchpad ")),
        "store failed": re.sub(r"( i=\d+ ok=)1", r"\g<1>0", raw),
        "tap stays on": re.sub(r"(settings: touchpad )0,", r"\g<1>1,", raw),
        "speed default": re.sub(r"(settings: touchpad (?:\d,){8})\d+", r"\g<1>100", raw),
        "no speed rect": raw.replace("settings: rect name=tpspd ", "settings: rect name=zzz "),
        "page too small": CTL.sub(lambda m: "settings: controls page=%s n=3" % m.group(1), raw),
    }
    for name, d in doctored.items():
        if all(c for c, _ in judge(d)):
            print("  FAIL  counter-proof not red: %s" % name)
            bad += 1
        else:
            print("  OK    counter-proof red: %s" % name)
            ok_n += 1
    print("SETTINGSTP: %d passed, %d failed" % (ok_n, bad))
    sys.exit(1 if bad else 0)


main()
