#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
import os
import re
import sys

out, state, pct, scale = sys.argv[1], sys.argv[2], int(sys.argv[3]), int(sys.argv[4])
results = []


def say(good, msg):
    results.append(good)
    print(("  OK    " if good else "  FAIL  ") + msg)


def load_ppm(path):
    data = open(path, "rb").read()
    head = re.match(rb"P6\s+(\d+)\s+(\d+)\s+255\s", data)
    return int(head.group(1)), int(head.group(2)), data[head.end():]


serial = open(os.path.join(out, "serial.txt"), "rb").read().decode("latin1")
bar_part = serial[:serial.find("taskbar: click")] if "taskbar: click" in serial else serial
icon = re.findall(r"taskbar: icon field=bat id=(\d+) x=(\d+) y=(\d+) px=(\d+)", bar_part)
geom = re.findall(r"taskbar: geom edge=0 x=(\d+) y=(\d+) w=(\d+) h=(\d+)", bar_part)
field = re.findall(r"taskbar: field battery x=(\d+) y=(\d+) w=(\d+) h=(\d+)", bar_part)
say(bool(icon and geom and field), "the bar reports the battery picture, its field and the bar geometry")
if not (icon and geom and field):
    print("RESULT ok=%d fail=%d" % (results.count(True), results.count(False)))
    sys.exit(1)

icon_id, ix, iy, px = [int(v) for v in icon[-1]]
gy = int(geom[-1][1])
fy, fh = int(field[-1][1]), int(field[-1][3])
say(px == 16 * scale, "the picture is drawn at %d px (16 x scale %d)" % (px, scale))
expected_id = {"discharging": 45057, "charging": 45058, "plugged": 45059, "low": 45060}[state]
say(icon_id == expected_id, "the bar draws the %s picture (id %d)" % (state, icon_id))

width, height, data = load_ppm(os.path.join(out, "00-bar.ppm"))
x0, y0 = ix, gy + iy


def pixel(x, y):
    i = (y * width + x) * 3
    return data[i], data[i + 1], data[i + 2]


bg = pixel(x0 - 3 * scale, y0)


def dist(c):
    return abs(c[0] - bg[0]) + abs(c[1] - bg[1]) + abs(c[2] - bg[2])


def is_green(c):
    return c[1] - c[0] >= 50 and c[1] - c[2] >= 30


def is_red(c):
    return c[0] - c[1] >= 60 and c[0] - c[2] >= 40


box = [(x, y, pixel(x, y)) for y in range(y0, y0 + px) for x in range(x0, x0 + px)]
ink = [(x, y) for x, y, c in box if dist(c) >= 150]
xs = [p[0] for p in ink]
ys = [p[1] for p in ink]
ink_w = max(xs) - min(xs) + 1
ink_h = max(ys) - min(ys) + 1
say(ink_w >= 0.8 * px and ink_h >= 0.4 * px and ink_w >= 1.5 * ink_h, "a landscape battery: ink %dx%d in a %d px box" % (ink_w, ink_h, px))
centre = (min(ys) + max(ys) + 1) / 2.0
field_centre = gy + fy + fh / 2.0
say(abs(centre - field_centre) <= 1.0, "ink centre %.1f vs field centre %.1f (<= 1 px)" % (centre, field_centre))

green = sum(1 for _, _, c in box if is_green(c))
red = sum(1 for _, _, c in box if is_red(c))
unit = px / 24.0
fill_l = x0 + int(round(4.5 * unit))
fill_r = x0 + int(round(18.0 * unit))
probe = y0 + int(9.4 * unit)
strong = [x for x in range(fill_l, fill_r) if dist(pixel(x, probe)) >= 150]
fraction = (max(strong) - min(strong) + 1) / float(fill_r - fill_l) if strong else 0.0
wanted = min(pct, 100) / 100.0
say(abs(fraction - wanted) <= 0.17, "fill %.2f of the inner width, wanted %.2f" % (fraction, wanted))

fill_box = [(x, y, c) for x, y, c in box if fill_l <= x < fill_r and y0 + int(9 * unit) <= y < y0 + int(15 * unit)]
if state == "discharging":
    say(green == 0 and red == 0, "plain battery: no green and no red (green %d, red %d)" % (green, red))
elif state == "charging":
    say(green >= 20 * scale * scale, "charging: green fill (%d green px)" % green)
    bolt = sum(1 for _, _, c in fill_box if not is_green(c) and dist(c) >= 450)
    say(bolt >= 4 * scale * scale, "charging: a bolt over the fill (%d dark px)" % bolt)
    say(red == 0, "charging: no red")
elif state == "plugged":
    holes = sum(1 for _, _, c in fill_box if dist(c) < 60)
    say(holes >= 6 * scale * scale, "plugged: a plug symbol cut into the fill (%d light px)" % holes)
    say(green == 0 and red == 0, "plugged: neither green nor red")
elif state == "low":
    say(red >= 5 * scale * scale, "low: red fill (%d red px)" % red)
    say(green == 0, "low: no green")
print("RESULT ok=%d fail=%d" % (results.count(True), results.count(False)))
sys.exit(1 if False in results else 0)
