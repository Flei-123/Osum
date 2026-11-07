#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
import re
import sys

TARGET = {3: (8, 336), 5: (21, 37)}

t = open(sys.argv[1], "rb").read().decode("latin1")
phases = []
cur = {"rects": 0, "px": 0}
for line in t.splitlines():
    m = re.match(r"wm: frame n=(\d+) mittel=([\d.,]+)\D.*?max=([\d.,]+)\D.*?over16=(\d+)", line)
    if m:
        cur.update(n=int(m.group(1)), mean=m.group(2), mx=m.group(3), o16=int(m.group(4)))
        phases.append(cur)
        cur = {"rects": 0, "px": 0}
        continue
    r = re.search(r"wm: dmg (\d+) (\d+) (\d+) (\d+) ", line)
    if r:
        cur["dmg"] = cur.get("dmg", 0) + (1 if (int(r.group(3)) - int(r.group(1))) * (int(r.group(4)) - int(r.group(2))) > 16384 else 0)
    r = re.search(r"wm: crect (\d+) (\d+) (\d+) (\d+) ", line)
    if r:
        cur["rects"] += 1
        cur["px"] += (int(r.group(3)) - int(r.group(1))) * (int(r.group(4)) - int(r.group(2)))
        cur.setdefault("org", {})
        o = (int(r.group(1)), int(r.group(2)))
        cur["org"][o] = cur["org"].get(o, 0) + 1
names = ["boot rest", "idle", "start menu opens", "pointer over the open menu", "Settings opens", "pointer over Settings"]
bad = 0
for i, p in enumerate(phases):
    nm = names[i] if i < len(names) else "phase %d" % (i + 1)
    print("  phase %d %-28s frames=%s mean=%s max=%s over16=%s composed_large_rects=%d px=%d large_damage_calls=%d" %
          (i + 1, nm, p["n"], p["mean"], p["mx"], p["o16"], p["rects"], p["px"], p.get("dmg", 0)))
for i in (3, 5):
    if i < len(phases):
        p = phases[i]
        mine = p.get("org", {}).get(TARGET[i], 0)
        lim = 100 if i == 5 else 50
        ok = p["n"] == 0 or mine * lim <= max(p["n"], 1)
        print("  %s  %s: %d composed large rects of the window under test in %d frames (need <= 1 per %d; %d of other windows ignored)" %
              ("OK  " if ok else "FAIL", names[i], mine, p["n"], lim, p["rects"] - mine))
        bad += 0 if ok else 1
if len(phases) < 6:
    print("  FAIL  only %d phases measured" % len(phases))
    bad += 1
sys.exit(1 if bad else 0)
