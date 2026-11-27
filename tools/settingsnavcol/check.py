#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
import os
import re
import sys

cfg, serial, outdir = sys.argv[1:4]
root = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..")
txt = open(serial, "rb").read().decode("latin1")
rect_re = re.compile(r"settings: rect name=(\w+) x=(\d+) y=(\d+) w=(\d+) h=(\d+)")
nav_re = re.compile(r"settings: nav route=(\S+) page=(\d+) crumbs=(\d+)")

routes = [ln.split()[1] for ln in open(os.path.join(root, "kernel/user/settings.d/settings.routes")) if ln.startswith("route ")]
pagemap = {}
for ln in open(os.path.join(root, "kernel/user/settings.d/settings.pagemap")):
    f = ln.split()
    if len(f) == 3 and f[0] == "page":
        pagemap[f[2]] = int(f[1])
heads = [r for r in routes if r.count("/") == 2]
head_pages = {pagemap[h] for h in heads if h in pagemap}
landing_pages = {pagemap[r] for r in routes if r.count("/") == 3 and r.rsplit("/", 1)[0] not in pagemap and r in pagemap}


def tab_name(p):
    return "tab" + (chr(97 + p) if p < 26 else "%02d" % p)


reports = []
cur = None
for ln in txt.splitlines():
    m = rect_re.search(ln)
    if not m:
        continue
    if m.group(1) == "waa":
        cur = {}
        reports.append(cur)
    if cur is not None:
        cur[m.group(1)] = tuple(int(m.group(i)) for i in range(2, 6))

fails = []


def check(c, msg):
    if not c:
        fails.append(msg)
    print(("  OK    " if c else "  FAIL  ") + msg)


def tabs(r):
    return {n for n in r if re.fullmatch(r"tab([a-z]|\d\d)", n)}


check(len(reports) > 0, "rect reports present (%d)" % len(reports))
check(not re.search(r"CRASH|EXCEPTION|^panic", txt, re.M), "no crash lines")
first = reports[0] if reports else {}
want = {tab_name(p) for p in head_pages}
lone = {tab_name(p) for p in landing_pages}
side = tabs(first)
check(len(side) == len(heads), "navigation column holds exactly %d main categories (%d)" % (len(heads), len(side)))
check(side <= want | lone, "navigation column holds no sub-page: %s" % sorted(side - want - lone))
for r in reports:
    check(tabs(r) <= want | lone | {tab_name(p) for p in pagemap.values()} and len([t for t in tabs(r) if t in side]) == len(side), "sidebar entries stay the same after navigation")
    break
sub = [r for r in reports if "tab32" in r and "tabb" in r]
check(bool(sub), "display page offers the monitors page as a row in the content")
if sub:
    x_side = max(sub[0][t][0] + sub[0][t][2] for t in side if t in sub[0])
    check(sub[0]["tab32"][0] >= x_side, "sub-page row sits right of the navigation column")
    check(sum(1 for t in tabs(sub[0]) if t not in side) == len(tabs(sub[0]) - side), "sub-page rows are the only extra entries")
    extra = tabs(sub[0]) - side
    check(len(extra) >= 2, "display page lists its sub-pages as rows (%d)" % len(extra))
navs = [nav_re.search(ln) for ln in txt.splitlines()]
navs = [m for m in navs if m]
check(any(m.group(1) == "settings://display/monitors" for m in navs), "clicking the row opens the monitors page")
check(all(int(m.group(3)) <= 3 for m in navs), "breadcrumb path has at most 3 segments")
dup = len(re.findall(r"System > |Settings > ", txt))
check(dup == 0, "no second path text in the page (%d)" % dup)
print("SETTINGSNAVCOL %s: %s" % (cfg, "FAIL" if fails else "OK"))
sys.exit(1 if fails else 0)
