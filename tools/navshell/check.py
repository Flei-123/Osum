#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
import os, re, sys

serial, outdir = sys.argv[1:3]
raw = open(serial, "rb").read().decode("latin1")
NAV = re.compile(r"^settings: nav route=(\S+) page=(\d+) crumbs=(\d+) back=(\d) fwd=(\d) up=(\d) depth=(\d+) side=(\d+) hits=(\d+) rawkeys=(\d+)")
CTL = re.compile(r"^settings: controls page=(\d+) n=(\d+)$", re.M)
BASE = os.path.join(os.path.dirname(os.path.abspath(__file__)), "controls.base")
LIMIT = 8
RECT = re.compile(r"settings: rect name=(\w+) x=(\d+) y=(\d+) w=(\d+) h=(\d+)")
PERS = "settings://personalization"
THEMES = "settings://personalization/themes"
POWER = "settings://system/power"
DISPLAY = "settings://display"
DISPADV = "settings://display/advanced"
TASKBAR = "settings://personalization/taskbar"
EFFECTS = "settings://personalization/effects"
WIFI = "settings://network/wifi"
USBNET = "settings://network/usb"


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
    ok(subseq(navs, [lambda n: n[0] == DISPLAY and n[1] == 1, lambda n: n[0] == DISPADV and n[1] == 19, lambda n: n[0] == POWER]),
       "sidebar: Display (page 1) and Advanced display (page 19, SET-7) open their own pages")
    ok(subseq(navs, [lambda n: n[0] == TASKBAR and n[1] == 20, lambda n: n[0] == EFFECTS and n[1] == 21]),
       "sidebar: Taskbar (page 20) and Window effects (page 21, SET-6) open their own pages")
    ok(subseq(navs, [lambda n: n[0] == WIFI and n[1] == 22, lambda n: n[0] == USBNET and n[1] == 23]),
       "sidebar: Wi-Fi (page 22) and USB network (page 23, LW-5) open their own pages")
    for want in ("navback", "navfwd", "navup", "navcrumba", "navcrumbb"):
        ok(want in names, "rect %s reported" % want)
    tabs = [n for n in names if re.fullmatch(r"tab[a-z]", n)]
    ok(len(tabs) >= 18, "sidebar tabs reported (%d)" % len(tabs))
    ctl = {}
    for m in CTL.finditer(txt):
        ctl[int(m.group(1))] = max(ctl.get(int(m.group(1)), 0), int(m.group(2)))
    ok(len(ctl) >= 2, "controls per page reported (%d pages)" % len(ctl))
    base = {}
    if os.path.exists(BASE):
        for ln in open(BASE):
            w = ln.split()
            if len(w) == 2 and w[0].isdigit():
                base[int(w[0])] = int(w[1])
    for p in sorted(ctl):
        cap = base.get(p, LIMIT)
        ok(ctl[p] <= cap, "page %d: %d controls <= %d (%s)" % (p, ctl[p], cap, "ratchet baseline" if p in base else "limit"))
    if os.environ.get("NAVSHELL_CONTROLS_UPDATE") and not quiet:
        merged = dict(base)
        for p, n in ctl.items():
            if p not in merged or n < merged[p]:
                merged[p] = n if p in merged else max(n, 0)
        open(BASE, "w").write("".join("%d %d\n" % (p, merged[p]) for p in sorted(merged)))
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
    "no controls": "\n".join(l for l in raw.splitlines() if not l.startswith("settings: controls ")),
    "more controls": re.sub(r"(settings: controls page=\d+ n=)\d+", r"\g<1>99", raw),
}
red = 0
for k, t in mut.items():
    if any(not c for c, _ in judge(t, True)):
        red += 1
    else:
        print("  FAIL  counter-proof '%s' stayed green" % k)
        bad += 1
print("  OK    counter-proof: %d of %d doctored logs turn red" % (red, len(mut))) if red == len(mut) else None
print("NAVSHELL: %d failed" % bad)
sys.exit(1 if bad else 0)
