#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
"""tools/calpop/check.py <outdir> -- judge serial + pictures of tools/calpop/shot.sh (P-011 calendar popup)."""
import calendar, datetime, os, re, sys

out = sys.argv[1]
ok = fail = 0
def say(good, msg):
    global ok, fail
    if good: ok += 1
    else: fail += 1
    print(("  OK    " if good else "  FAIL  ") + msg)

def load_ppm(path):
    d = open(path, "rb").read(); f = []; at = 2
    while len(f) < 3:
        while d[at:at+1].isspace(): at += 1
        s = at
        while not d[at:at+1].isspace(): at += 1
        f.append(int(d[s:at]))
    return f[0], f[1], d[at+1:]

ser = open(os.path.join(out, "serial.txt"), "rb").read().decode("latin1")
opens = re.findall(r"calpop: open today=(\d+)-(\d+)-(\d+) x=(\d+) y=(\d+) w=(\d+) h=(\d+)", ser)
say(len(opens) >= 2, "the clock press opened the calendar (%d opens)" % len(opens))
if not opens:
    print("RESULT ok=%d fail=%d" % (ok, fail)); sys.exit(1)
ty, tm, td, px, py, pw, ph = [int(v) for v in opens[0]]
host = datetime.date.today()
say(abs((datetime.date(ty, tm, td) - host).days) <= 1, "today in the popup (%d-%d-%d) is the system date (host %s)" % (ty, tm, td, host))
# grids: every `calpop: grid first= days=` after a `calpop: month Y-M` matches the real calendar
bad = 0; n = 0
for m in re.finditer(r"calpop: month (\d+)-(\d+)\ncalpop: grid first=(\d+) days=(\d+)", ser.replace("\r", "")):
    y, mo, first, days = [int(v) for v in m.groups()]
    n += 1
    if (calendar.monthrange(y, mo) != (first, days)): bad += 1
say(n >= 4 and bad == 0, "month grids (first weekday Monday=0, days) equal the calendar in all %d reports" % n)
months = [(int(a), int(b)) for a, b in re.findall(r"calpop: month (\d+)-(\d+)", ser)]
def shift(y, m, k):
    t = y * 12 + (m - 1) + k
    return t // 12, t % 12 + 1
say(len(months) >= 4 and months[1] == shift(ty, tm, 1) and months[2] == shift(ty, tm, 0) and months[3] == shift(ty, tm, -1),
    "next, prev, prev walk the months (%s)" % months[:5])
picks = re.findall(r"calpop: pick (\d+)-(\d+)-(\d+)", ser)
say(len(picks) >= 2, "a day press and Today both report a pick (%s)" % picks[:3])
if len(picks) >= 2:
    py_, pm_ = shift(ty, tm, -1)
    say(tuple(int(v) for v in picks[0]) == (py_, pm_, 15), "the pressed cell is day 15 of the shown (previous) month: %s" % (picks[0],))
    say(tuple(int(v) for v in picks[-1]) == (ty, tm, td), "Today marks today: %s" % (picks[-1],))
shuts = re.findall(r"calpop: shut (\w+)", ser)
say(shuts[:2] == ["toggle", "outside"], "closed by a clock press and by an outside press (%s)" % shuts)
print("  INFO  Esc closes the popup: %s (open issue, see roadmap)" % ("yes" if "esc" in shuts else "NO"))
rects = dict((n_, tuple(int(v) for v in r)) for n_, *r in re.findall(r"calpop: rect name=(\w+) x=(\d+) y=(\d+) w=(\d+) h=(\d+)", ser))
say(all(k in rects for k in ("prev", "next", "today", "cell")), "the popup reports its buttons (%s)" % sorted(rects))
# geometry: the card lies above the bar and inside the screen
W, H = 1280, 800
say(px >= 0 and px + pw <= W and py >= 0 and py + ph <= H, "the card is inside the screen (x=%d y=%d w=%d h=%d)" % (px, py, pw, ph))
geom = re.findall(r"taskbar: geom edge=0 x=(\d+) y=(\d+) w=(\d+) h=(\d+)", ser)
if geom:
    by = int(geom[-1][1])
    say(py + ph <= by, "the card ends above the bar (card bottom %d, bar top %d)" % (py + ph, by))
# pictures: the open picture differs from the bar picture inside the card, the closed one does not
def blue(name):
    wa, ha, da = load_ppm(os.path.join(out, name + ".ppm"))
    n = 0
    for yy in range(py, min(py + ph, ha)):
        for xx in range(px, min(px + pw, wa)):
            o = (yy * wa + xx) * 3
            if da[o + 2] > 180 and da[o] < 90 and da[o + 1] < 140: n += 1
    return n
def region_diff(a, b):
    wa, ha, da = load_ppm(os.path.join(out, a + ".ppm")); wb, hb, db = load_ppm(os.path.join(out, b + ".ppm"))
    n = d = 0
    for yy in range(py, min(py + ph, ha), 3):
        for xx in range(px, min(px + pw, wa), 3):
            o = (yy * wa + xx) * 3
            n += 1
            if max(abs(da[o + c] - db[o + c]) for c in range(3)) > 24: d += 1
    return d * 100 // max(n, 1)
try:
    b0, b1 = blue("00-bar"), blue("01-open")
    say(b1 >= 300 and b0 < 50, "the open picture shows the accent plate of today inside the card (%d blue px, %d before)" % (b1, b0))
    say(blue("06-closed") < 50, "after the closes the accent plate is gone (%d blue px)" % blue("06-closed"))
    say(region_diff("01-open", "02-next") >= 3, "next month repaints the grid (%d %% differs)" % region_diff("01-open", "02-next"))
    wa, ha, da = load_ppm(os.path.join(out, "01-open.ppm"))
    say(wa == W and ha == H, "picture size %dx%d" % (wa, ha))
except OSError as e:
    say(False, "pictures missing: %s" % e)
print("RESULT ok=%d fail=%d" % (ok, fail))
sys.exit(1 if fail else 0)
