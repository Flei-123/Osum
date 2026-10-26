#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
# tools/settingswin11/check.py <cfg> <serial.txt> <outdir> -- checks of tools/settingswin11/run.sh.
# cfg flat is the counter-proof: the accordion checks must be RED there (exit 0 only when they are).
import re, sys, os

cfg, serial, outdir = sys.argv[1:4]
txt = open(serial, "rb").read().decode("latin1")
txt = re.sub(r"(?<=[^\n])wm: schlieren grow=\d+ alpha=\d+ blur=\d+ aus=\d+ unterpx=\d+\n", "", txt)
rect_re = re.compile(r"settings: rect name=(\w+) x=(\d+) y=(\d+) w=(\d+) h=(\d+)")
reports = []
cur = None
for ln in txt.splitlines():
    m = rect_re.search(ln)
    if not m:
        continue
    n = m.group(1)
    if n == "waa" or cur is None:
        cur = {}
        reports.append(cur)
    cur[n] = tuple(int(m.group(i)) for i in range(2, 6))

fails = []
passes = []


def check(c, msg):
    (passes if c else fails).append(msg)
    print(("  OK    " if c else "  FAIL  ") + msg)


def tabs(r):
    return {n for n in r if n.startswith("tab")}


def ppm(n):
    p = os.path.join(outdir, n + ".ppm")
    return open(p, "rb").read() if os.path.exists(p) else None


check(len(reports) > 0, "rect reports present (%d)" % len(reports))
check(not re.search(r"ABSTURZ|EXCEPTION|^panic", txt, re.M), "no crash lines")
check(os.path.exists(os.path.join(outdir, "00-start.ppm")), "start picture taken")
first = reports[0] if reports else {}
check("wdu" in first, "search field reported")
if "wdu" in first and tabs(first):
    top = min(first[t][1] for t in tabs(first))
    check(first["wdu"][1] < top, "search field sits above the sidebar (y %d < %d)" % (first["wdu"][1], top))
after = None
for r in reports[1:]:
    if "tabq" in r:
        after = r
        break
acc = []
n0 = len(tabs(first))
acc.append(("sidebar shows few pages at start (%d <= 17)" % n0, n0 <= 17 and n0 >= 5))
acc.append(("sub-pages of other categories are hidden at start (no tabq)", "tabq" not in first))
acc.append(("opening System shows its sub-pages (tabq appears)", after is not None))
if after is not None:
    acc.append(("opening System collapses Personalization (tab24 gone)", "tab24" not in after))
else:
    acc.append(("opening System collapses Personalization (tab24 gone)", False))
if cfg == "flat":
    bad = [m for m, c in acc if not c]
    check(len(bad) >= 2, "counter-proof: accordion checks are red in flat mode (%d red)" % len(bad))
    print("SETTINGSWIN11 flat: %s" % ("OK" if not fails else "FAIL"))
    sys.exit(1 if fails else 0)
for m, c in (acc[:1] if cfg == "narrow" else acc):
    check(c, m)
if cfg in ("light", "dark"):
    for n in ("01-system", "02-power", "03-search"):
        check(ppm(n) is not None, "picture %s taken" % n)
    if ppm("00-start") and ppm("01-system"):
        check(ppm("00-start") != ppm("01-system"), "System page looks different from the start page")
    if ppm("02-power") and ppm("03-search"):
        check(ppm("02-power") != ppm("03-search"), "search changes the sidebar")
print("SETTINGSWIN11 %s: %s" % (cfg, "FAIL" if fails else "OK"))
sys.exit(1 if fails else 0)
