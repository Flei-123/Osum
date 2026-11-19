#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
import os
import re
import sys

out = sys.argv[1]
mode = sys.argv[2] if len(sys.argv) > 2 else ""
mutant = mode == "mutant"
layer_mutant = mode == "layer"
serial = open(os.path.join(out, "serial.txt"), "rb").read().decode("latin1").split("\n")
ok = bad = 0


def check(cond, message, final=False):
    global ok, bad
    if layer_mutant and not final:
        print("  INFO  baseline %s: %s" % ("ok" if cond else "fail", message))
        return
    if cond:
        ok += 1
        print("  OK    " + message)
    else:
        bad += 1
        print("  FAIL  " + message)


def load(name):
    path = os.path.join(out, name + ".ppm")
    if not os.path.exists(path):
        return None
    data = open(path, "rb").read()
    head = re.match(rb"P6\s+(\d+)\s+(\d+)\s+(\d+)\s", data)
    return (int(head[1]), int(head[2]), data[head.end():]) if head else None


DARK_MAX = 20


def dark_percent(img, x0, y0, x1, y1):
    if img is None:
        return -1
    width, _, pix = img
    dark = total = 0
    for y in range(y0, y1, 2):
        for x in range(x0, x1, 2):
            o = (y * width + x) * 3
            total += 1
            if max(pix[o:o + 3]) <= DARK_MAX:
                dark += 1
    return dark * 100 // max(total, 1)


def changed(a, b, box):
    if a is None or b is None:
        return -1
    width = a[0]
    n = 0
    for y in range(box[1], box[3]):
        for x in range(box[0], box[2]):
            o = (y * width + x) * 3
            if a[2][o:o + 3] != b[2][o:o + 3]:
                n += 1
    return n


def lines(pattern):
    return [ln for ln in serial if re.search(pattern, ln)]


def num(line, key):
    m = re.search(key + r"=(\d+)", line)
    return int(m[1]) if m else -1


COVER_MIN_PERCENT = 70


def cover_percent(base, shot, box):
    if base is None or shot is None:
        return -1
    width = base[0]
    total = diff = 0
    for y in range(box[1], box[3], 2):
        for x in range(box[0], box[2], 2):
            o = (y * width + x) * 3
            total += 1
            if base[2][o:o + 3] != shot[2][o:o + 3]:
                diff += 1
    return diff * 100 // max(total, 1)


def start_menu_case():
    cards = lines(r"taskview: preview n=")
    last = cards[-1] if cards else ""
    cx, cy, cw, ch = (num(last, k) for k in ("x", "y", "w", "h"))
    percent = cover_percent(load("b0-start"), load("b1-over-start"), (cx, cy, cx + cw, cy + ch)) if cx >= 0 else -1
    return percent


previews = lines(r"taskview: preview n=")
check(len(previews) >= 2, "preview card opened for explorer and terminal: %d" % len(previews))
first = previews[0] if previews else ""
x, y, w, h = (num(first, k) for k in ("x", "y", "w", "h"))
check(x >= 8 and x + w <= 1280 and y >= 0 and y + h <= 780,
      "card inside the screen and above the bar: x=%d y=%d w=%d h=%d" % (x, y, w, h))
dwell = lines(r"taskbar: preview dwell ms=")
delay = num(dwell[0], "ms") if dwell else -1
check(100 <= delay <= 400, "hover delay before the card: %d ms" % delay)
a1 = load("a1-card")
body = (x + 12, y + 44, x + w - 12, y + h - 14)
dark = dark_percent(a1, *body) if x >= 0 else -1
check(dark >= 30, "the card carries a live thumbnail: %d %% dark window pixels in the thumbnail area" % dark)
if mutant:
    print("== counter-proof: without WM_THUMB the thumbnail area is flat")
    print("RESULT %d %d" % (ok, bad))
    sys.exit(0)
switch = lines(r"taskbar: preview switch")
check(len(switch) >= 1, "moving to the next symbol switches the card at once")
if len(previews) >= 2:
    check(num(previews[1], "x") != x or "app=" in previews[1] and previews[1].split("app=")[1] != first.split("app=")[1],
          "the second card belongs to the neighbour")
a2 = load("a2-neighbor")
check(changed(a1, a2, (x, y, x + w, y + h)) > 500, "picture of the card changed at the switch")
check(len(lines(r"taskview: raise id=\d+ rc=0")) >= 1, "a click on the card raised the window")
fades = [num(ln, "ms") for ln in lines(r"taskview: fade ms=")]
check(bool(fades) and 80 <= max(fades) <= 250, "fade-out lasted %s ms" % fades[:3])
jump = lines(r"taskbar: jumplist n=")
rows = num(jump[0], "n") if jump else -1
check(rows == 6, "jump list rows: launch, unpin, minimise, end task, close, manifest row = %d" % rows)
check(len(lines(r"taskbar: kontext w=1$")) >= 1, "the Minimise row of the jump list ran")
check(len(lines(r"taskbar: kontext w=4096$")) >= 1, "the manifest row (/etc/ctxmenu.conf) is in the jump list and ran")
check(len(lines(r"taskbar: context empty x=.* n=2$")) >= 1, "empty bar menu has two rows")
a3, a4, a5 = load("a3-picked"), load("a4-jump"), load("a5-minimised")
jx, jy, jw, jh = (num(jump[0], k) for k in ("x", "y", "w", "h")) if jump else (0, 0, 0, 0)
check(changed(a3, a4, (jx, jy, jx + jw, jy + jh)) > jw * jh // 3, "jump list is visible in the picture")
check(changed(a3, a4, (x, y, max(jx - 2, x), y + h)) < 1500, "no preview card opens behind the open jump list")
check(changed(a4, a5, (0, 0, 1280, 700)) > 2000, "the explorer window vanished after Minimise")
a6, a7 = load("a6-empty"), load("a7-closed")
check(changed(a6, a7, (640, 640, 900, 780)) > 500, "empty bar menu closed on Escape")
frames = {}
for ln in lines(r"wm: animf id=\d+ kind=4 layer="):
    m = re.search(r"id=(\d+) kind=4 .* p=(\d+) t=(\d+)", ln)
    if m:
        frames.setdefault(m[1], []).append((int(m[2]), int(m[3])))
gaps = []
for seq in frames.values():
    gaps += [b[1] - a[1] for a, b in zip(seq, seq[1:]) if b[0] > a[0]]
gaps.sort()
median = gaps[len(gaps) // 2] if gaps else -1
print("  INFO  pop animation frame gaps: median %d ms, max %d ms (%d gaps)" % (median, gaps[-1] if gaps else -1, len(gaps)))
check(0 < median <= 17, "frame time of the card animation <= 16 ms (median %d)" % median)
cover = start_menu_case()
if layer_mutant:
    check(cover < COVER_MIN_PERCENT, "mutant card stays behind the start menu: %d %% of the card area differs" % cover, final=True)
else:
    check(cover >= COVER_MIN_PERCENT, "the preview card is in front of the open start menu: %d %% of the card area differs" % cover)
print("RESULT %d %d" % (ok, bad))
