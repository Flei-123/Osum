#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
import re, sys

serial, outdir = sys.argv[1:3]
raw = open(serial, "rb").read().decode("latin1")
NAV = re.compile(r"^settings: nav route=(\S+) page=(\d+) crumbs=(\d+) back=(\d) fwd=(\d) up=(\d) depth=(\d+) side=(\d+) hits=(\d+) rawkeys=(\d+)$")
RECT = re.compile(r"settings: rect name=(\w+) x=(\d+) y=(\d+) w=(\d+) h=(\d+)")
PERS = "settings://personalization"
THEMES = "settings://personalization/themes"
POWER = "settings://system/power"


def parse(txt):
    navs = []
    names = set()
    for ln in txt.splitlines():
        m = NAV.match(ln)
        if m:
            g = m.groups()
            navs.append((g[0],) + tuple(int(x) for x in g[1:]))
        for m in RECT.finditer(ln):
            names.add(m.group(1))
    return navs, names


def subseq(navs, want):
    i = 0
    for n in navs:
        if i < len(want) and want[i](n):
            i += 1
    return i == len(want)


def judge(txt, quiet=False):
    results = []

    def ok(c, m):
        results.append((bool(c), m))

    navs, names = parse(txt)
    ok(len(navs) > 0, "nav lines reported (%d)" % len(navs))
    if not navs:
        return results
    first = navs[0]
    ok(first[0] == PERS and first[1] == 0, "opens on %s, page 0" % PERS)
    ok(first[2] == 2 and first[3] == 0 and first[4] == 0, "first state: 2 crumbs, nothing to go back or forward to")
    ok(first[7] >= 18, "sidebar lists the mapped pages from the route table (side=%d)" % first[7])
    ok(all(n[9] == 0 for n in navs), "no route title shows its raw catalogue key (rawkeys=0 on every line)")
    ok(subseq(navs, [
        lambda n: n[0] == PERS,
        lambda n: n[0] == THEMES and n[1] == 7 and n[2] == 3 and n[3] == 1,
        lambda n: n[0] == PERS and n[1] == 0 and n[3] == 1,
        lambda n: n[0] == THEMES and n[1] == 7 and n[4] == 1,
        lambda n: n[0] == PERS and n[1] == 0 and n[4] == 1,
        lambda n: n[0] == THEMES and n[1] == 7 and n[6] == 3,
        lambda n: n[0] == PERS and n[1] == 0 and n[6] == 3,
    ]), "tab click, Up, Back, Back, Forward, breadcrumb: routes, pages, crumbs, flags in order")
    ok(any(n[0] == THEMES and n[6] == 3 for n in navs), "stack depth 3 after pers, themes, up")
    ok(any(n[8] >= 1 for n in navs), "search for 'power' finds a route (hits>=1)")
    ok(subseq(navs, [lambda n: n[8] >= 1, lambda n: n[0] == POWER and n[1] == 16]), "Enter opens the best hit: %s on page 16" % POWER)
    for want in ("navback", "navfwd", "navup", "navcrumba", "navcrumbb"):
        ok(want in names, "rect %s reported" % want)
    tabs = [n for n in names if re.fullmatch(r"tab[a-z]", n)]
    ok(len(tabs) >= 18, "sidebar tabs reported (%d)" % len(tabs))
    ok(not re.search(r"ABSTURZ|EXCEPTION|panic", txt), "no crash lines")
    return results


def show(results):
    bad = 0
    for c, m in results:
        print(("  OK    " if c else "  FAIL  ") + m)
        if not c:
            bad += 1
    return bad


bad = show(judge(raw))
mut = {
    "no back": re.sub(r"back=1", "back=0", raw),
    "no nav lines": "\n".join(l for l in raw.splitlines() if not l.startswith("settings: nav ")),
    "wrong page": raw.replace("page=7 ", "page=3 "),
    "raw keys": raw.replace("rawkeys=0", "rawkeys=2"),
    "no crumbs": raw.replace("crumbs=3", "crumbs=1"),
    "no search": re.sub(r"hits=[1-9]", "hits=0", raw),
}
red = 0
for k, t in mut.items():
    if any(not c for c, _ in judge(t)):
        red += 1
    else:
        print("  FAIL  counter-proof '%s' stayed green" % k)
        bad += 1
print("  OK    counter-proof: %d of %d doctored logs turn red" % (red, len(mut))) if red == len(mut) else None
print("NAVSHELL: %d failed" % bad)
sys.exit(1 if bad else 0)
