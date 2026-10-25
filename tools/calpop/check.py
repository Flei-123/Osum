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
keys = re.findall(r"calpop: key (\d+)", ser)
say("esc" in shuts and "27" in keys, "Esc reaches the popup and closes it (shuts %s, keys %s)" % (shuts, keys))
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
evs = re.findall(r"calpop: event (add|del) (\d+) n=(\d+) (ok|refused)", ser)
tk = ty * 10000 + tm * 100 + td
say([e[0] for e in evs] == ["add", "add", "del"] and all(int(e[1]) == tk for e in evs), "event lines add, add, del for today's key %d (%s)" % (tk, evs))
say(len(evs) == 3 and [(e[2], e[3]) for e in evs] == [("1", "ok"), ("1", "refused"), ("0", "ok")], "store counts: 1 after add, empty add refused (still 1), 0 after del (%s)" % [(e[2], e[3]) for e in evs])
def cell_diff(a, b):
    r_ = rects.get("tday")
    if not r_: return -1
    wa, ha, da = load_ppm(os.path.join(out, a + ".ppm")); wb, hb, db = load_ppm(os.path.join(out, b + ".ppm"))
    x0, y0, w0, h0 = r_
    d = 0
    for yy in range(y0, y0 + h0):
        for xx in range(x0, x0 + w0):
            o = (yy * wa + xx) * 3
            if max(abs(da[o + c] - db[o + c]) for c in range(3)) > 24: d += 1
    return d
try:
    on = cell_diff("05-today", "05a-event")
    off = cell_diff("05-today", "05b-deleted")
    say(on >= 6, "the event dot appears in today's cell (%d px differ)" % on)
    say(0 <= off <= 1, "COUNTER-PROOF: after del the cell is as before, so the dot is not noise (%d px differ)" % off)
    say(region_diff("05-today", "05a-event") >= 1, "the event line and entry repaint the card (%d %% differs)" % region_diff("05-today", "05a-event"))
except OSError as e:
    say(False, "event pictures missing: %s" % e)
cn = re.findall(r"calpop: contacts (\d+)", ser)
say(len(cn) >= 2 and all(int(v) == 4 for v in cn), "every open reports the 4 seeded contacts (%s)" % cn)
def ink(name, y0, y1):
    wa, ha, da = load_ppm(os.path.join(out, name + ".ppm"))
    base = da[(py + 2) * wa * 3 + (px + 2) * 3:(py + 2) * wa * 3 + (px + 2) * 3 + 3]
    n = 0
    for yy in range(max(y0, 0), min(y1, ha)):
        for xx in range(px + 4, min(px + pw - 4, wa)):
            o = (yy * wa + xx) * 3
            if max(abs(da[o + c] - base[c]) for c in range(3)) > 90: n += 1
    return n
sk_ = max(pw // 296, 1)
pad, gap, add_h, ct_h, ev_h = 10 * sk_, 4 * sk_, 36 * sk_, 26 * sk_, 26 * sk_
ct_y1 = py + ph - pad - add_h - gap
ct_y0 = ct_y1 - ct_h
ev_y1 = ct_y0 - gap
ev_y0 = ev_y1 - ev_h
try:
    ci, ei = ink("01-open", ct_y0, ct_y1), ink("01-open", ev_y0, ev_y1)
    say(ci >= 40, "the contact line shows names inside its band (%d ink px)" % ci)
    say(ei <= 4, "COUNTER-PROOF: the empty event line band right above has no ink, so the band test is not noise (%d ink px)" % ei)
except OSError as e:
    say(False, "open picture missing: %s" % e)
print("RESULT ok=%d fail=%d" % (ok, fail))
sys.exit(1 if fail else 0)
