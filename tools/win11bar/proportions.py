#!/usr/bin/env python3
import re
import sys

ICON_NUM = 3
ICON_DEN = 5
PILL_H = 3
PILL_IDLE_W = 6
PILL_ACTIVE_W = 16
PILL_GAP_MIN = 4
PILL_FOOT = 1


def fields(line):
    return {k: int(v) for k, v in re.findall(r"(\w+)=(\d+)", line)}


def last_by_index(path, prefix):
    rows = {}
    for line in open(path, errors="replace"):
        if line.startswith(prefix):
            f = fields(line)
            rows[f["i"] if "i" in f else f.get("btn", -1)] = f
    return rows


def pins(path):
    rows = {}
    for line in open(path, errors="replace"):
        m = re.match(r"taskbar: pin (\w+) .*? x=(\d+) y=(\d+) w=(\d+) h=(\d+)", line)
        if m:
            rows[m.group(1)] = tuple(int(v) for v in m.groups()[1:])
    return rows


def check(path, scale):
    pills = last_by_index(path, "taskbar: pille ")
    syms = last_by_index(path, "taskbar: sym btn=")
    results = []
    if not pills:
        return [("a running pin carries a pill", False, "pills=0")]
    widths = sorted(p["w"] for p in pills.values())
    if len(widths) > 1:
        results.append(("idle pill is %d px wide" % (PILL_IDLE_W * scale), widths[0] == PILL_IDLE_W * scale, "w=%d" % widths[0]))
    results.append(("active pill is %d px wide" % (PILL_ACTIVE_W * scale), widths[-1] == PILL_ACTIVE_W * scale, "w=%d" % widths[-1]))
    for i, s in syms.items():
        ratio_ok = s["gemalt"] * ICON_DEN <= s["button"] * ICON_NUM + ICON_DEN
        results.append(("pin %d icon is at most 3/5 of its tile" % i, ratio_ok, "icon=%d tile=%d" % (s["gemalt"], s["button"])))
    for i, p in pills.items():
        if "sy" not in p:
            results.append(("pin %d pill geometry is traced" % i, False, "no sy/sz"))
            continue
        gap = p["y"] - (p["sy"] + p["sz"])
        results.append(("pin %d gap icon to pill >= %d px" % (i, PILL_GAP_MIN * scale), gap >= PILL_GAP_MIN * scale, "gap=%d" % gap))
        results.append(("pin %d pill is %d px high" % (i, PILL_H * scale), p["h"] == PILL_H * scale, "h=%d" % p["h"]))
        if i in syms:
            results.append(("pin %d icon sits inside its tile" % i, p["sz"] <= syms[i]["button"], "sz=%d" % p["sz"]))
    return results


def main():
    path, scale, expect_icon = sys.argv[1], int(sys.argv[2]), int(sys.argv[3])
    bad = 0
    results = check(path, scale)
    if expect_icon:
        syms = last_by_index(path, "taskbar: sym btn=")
        sizes = {s["gemalt"] for s in syms.values()}
        results.append(("icon is %d px (Windows 11 at this bar)" % expect_icon, sizes == {expect_icon}, "sizes=%s" % sorted(sizes)))
    for name, ok, info in results:
        print("%s %s (%s)" % ("OK  " if ok else "FAIL", name, info))
        bad += 0 if ok else 1
    sys.exit(1 if bad else 0)


main()
