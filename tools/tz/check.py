#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
# tools/tz/check.py <oracle> -- every zone of lib/tz/zonedata.fi against IANA tzdata.
# Instants: a 2h53m grid over 2024..2040 plus both sides (-1 s, 0, +1 s) of every real
# changeover of every zone (found by bisection). Prints "OK <what>" / "FAIL <what>".
import sys, subprocess, datetime as dt
from zoneinfo import ZoneInfo
sys.path.insert(0, __file__.rsplit("/", 1)[0] if "/" in __file__ else ".")
import tzmodel
from gen import CURATED

ORACLE = sys.argv[1]
UTC = dt.timezone.utc
ids = {name: zid for _, zid, name in CURATED}
fails = 0
def ok(c, what):
    global fails
    print(("OK   " if c else "FAIL ") + what)
    if not c: fails += 1

def run(inp):
    return subprocess.run([ORACLE], input=inp, capture_output=True, text=True, timeout=120).stdout.split("\n")

tab = [l for l in run("table\n") if l]
zones = []
for l in tab:
    idx, rest = l.split(" ", 1)
    reg, rest = rest.split(" ", 1)
    name, base, rule = rest.split("|")
    zones.append((int(idx), reg, name, int(base), int(rule)))
ok(len(zones) >= 70, "table has %d zones" % len(zones))
ok(all(n in ids for _, _, n, _, _ in zones), "every table name is a curated IANA zone")
ok(any(n == "Vienna" and b == 60 and r == 1 for _, _, n, b, r in zones), "Vienna = +60 min, EU rule")
ok(any(n == "New York" and b == -300 and r == 2 for _, _, n, b, r in zones), "New York = -300 min, US rule")
ok(any(n == "Sydney" and b == 600 and r == 3 for _, _, n, b, r in zones), "Sydney = +600 min, AU rule")
ok(any(n == "Auckland" and b == 720 and r == 4 for _, _, n, b, r in zones), "Auckland = +720 min, NZ rule")
ok(any(n == "UTC" and b == 0 and r == 0 for _, _, n, b, r in zones), "UTC = 0, no rule")

t0 = int(dt.datetime(2024, 1, 1, tzinfo=UTC).timestamp())
t1 = int(dt.datetime(2041, 1, 1, tzinfo=UTC).timestamp())
grid = list(range(t0, t1, 2 * 3600 + 53 * 60))

def real(zi, t):
    return int(dt.datetime.fromtimestamp(t, UTC).astimezone(zi).utcoffset().total_seconds() // 60)

def changes(zi):
    out = []
    prev = real(zi, grid[0])
    for a, b in zip(grid, grid[1:]):
        cur = real(zi, b)
        if cur != prev:
            lo, hi = a, b
            while hi - lo > 1:
                m = (lo + hi) // 2
                if real(zi, m) == prev: lo = m
                else: hi = m
            out.append(hi)
        prev = cur
    return out

total = 0
bad_zones = []
for idx, reg, name, base, rule in zones:
    zi = ZoneInfo(ids[name])
    ch = changes(zi)
    pts = grid + [c + d for c in ch for d in (-1, 0, 1)]
    want = [real(zi, t) for t in pts]
    got = run("".join("%d %d\n" % (idx, t) for t in pts))
    got = [int(x) for x in got if x != ""]
    total += len(pts)
    if got != want:
        n = sum(1 for a, b in zip(got, want) if a != b)
        bad_zones.append("%s (%d of %d differ)" % (name, n, len(pts)))
    # the python twin agrees too (second reading of the same rules)
    twin = [tzmodel.offset_min(t, base, rule) for t in pts]
    if twin != want:
        bad_zones.append("%s (python twin)" % name)
ok(not bad_zones, "all %d zones x changeovers = %d instants equal IANA tzdata %s" % (len(zones), total, "; ".join(bad_zones[:4])))

# negative controls: the oracle must be able to disagree
def raw(base_w, rule, t):
    return int(run("raw %s%d %d %d\n" % ("w" if base_w < 0 else "", abs(base_w), rule, t))[0])
vi = ZoneInfo("Europe/Vienna"); ny = ZoneInfo("America/New_York")
t = int(dt.datetime(2026, 7, 1, 12, tzinfo=UTC).timestamp())
ok(raw(60, 1, t) == 120 and raw(60, 0, t) == 60, "control: rule EU adds an hour in July, rule none does not")
ok(raw(-300, 2, t) == -240 and raw(-300, 0, t) == -300, "control: negative base + US rule (west of Greenwich)")
ok(raw(-300, 1, int(dt.datetime(2026, 3, 29, 1, 30, tzinfo=UTC).timestamp())) == -240, "control: EU rule on a west base still follows the UTC instant")
mar = int(dt.datetime(2026, 3, 15, 12, tzinfo=UTC).timestamp())
ok(raw(60, 2, mar) == 120 and raw(60, 1, mar) == 60, "control: 15 Mar 2026 US rule already summer, EU not yet")
# the changeover instants, exact to the second
eu = int(dt.datetime(2026, 3, 29, 1, 0, 0, tzinfo=UTC).timestamp())
ok(raw(60, 1, eu - 1) == 60 and raw(60, 1, eu) == 120, "EU: switch at 01:00:00 UTC on 29 Mar 2026")
us = int(dt.datetime(2026, 3, 8, 7, 0, 0, tzinfo=UTC).timestamp())
ok(raw(-300, 2, us - 1) == -300 and raw(-300, 2, us) == -240, "US: switch at 02:00 local (07:00 UTC) on 8 Mar 2026")
def utc(y, m, d, h, mi=0):
    return int(dt.datetime(y, m, d, h, mi, tzinfo=UTC).timestamp())
ok(raw(-240, 5, utc(2026, 9, 6, 4) - 1) == -240 and raw(-240, 5, utc(2026, 9, 6, 4)) == -180, "Chile: switch at 04:00 UTC on the first Sunday on/after 2 Sep (6 Sep 2026)")
ok(raw(-240, 5, utc(2027, 4, 4, 3) - 1) == -180 and raw(-240, 5, utc(2027, 4, 4, 3)) == -240, "Chile: back at 03:00 UTC on the first Sunday on/after 2 Apr (4 Apr 2027)")
ok(raw(-300, 6, utc(2026, 3, 8, 5) - 1) == -300 and raw(-300, 6, utc(2026, 3, 8, 5)) == -240, "Cuba: switch at 00:00 local standard time on 8 Mar 2026")
ok(raw(120, 7, utc(2026, 3, 27, 0) - 1) == 120 and raw(120, 7, utc(2026, 3, 27, 0)) == 180, "Israel: switch on the Friday before the last Sunday of March at 02:00 local (27 Mar 2026 00:00 UTC)")
ok(raw(120, 8, utc(2026, 4, 23, 22) - 1) == 120 and raw(120, 8, utc(2026, 4, 23, 22)) == 180, "Egypt: switch at Friday 00:00 local standard time (24 Apr 2026)")
ok(raw(120, 8, utc(2026, 10, 29, 21) - 1) == 180 and raw(120, 8, utc(2026, 10, 29, 21)) == 120, "Egypt: back at the last Thursday of October 24:00 local summer time (29 Oct 2026)")
for zone, name in (("America/Santiago", "Santiago"), ("America/Havana", "Havana"), ("Asia/Jerusalem", "Jerusalem"), ("Africa/Cairo", "Cairo")):
    ok(any(n == name for _, _, n, _, _ in zones), "%s is in the table now" % name)
ok(not any(n == "Casablanca" for _, _, n, _, _ in zones), "Casablanca stays out (its offset follows Ramadan)")
print("RESULT %s" % ("FAIL" if fails else "OK"))
sys.exit(1 if fails else 0)
