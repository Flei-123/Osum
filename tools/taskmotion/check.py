#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
import os
import re
import sys

out = sys.argv[1]
off = len(sys.argv) > 2 and sys.argv[2] == "off"
off_dir = sys.argv[2] if len(sys.argv) > 2 and not off else None
serial = open(os.path.join(out, "serial.txt"), "rb").read().decode("latin1").split("\n")
ok = bad = 0

K_HOLD, K_REBOUND, K_POP, K_WAIT, K_GHOST = 1, 2, 3, 4, 5
PRESS_MAX_PM = 900
PRESS_MIN_PM = 850
SHRINK_MAX_RATIO = 0.95
KEEP_MIN_RATIO = 0.98
INK_THRESHOLD = 120
POP_MS = (250, 450)
GHOST_MS = (100, 200)
CLOSE_MS = (100, 150)
MAX_PAINT_US = 16000
MIN_FRAMES = 3


def check(cond, message):
    global ok, bad
    if cond:
        ok += 1
        print("  OK    " + message)
    else:
        bad += 1
        print("  FAIL  " + message)


def load(name, base=None):
    path = os.path.join(base or out, name + ".ppm")
    if not os.path.exists(path):
        return None
    data = open(path, "rb").read()
    head = re.match(rb"P6\s+(\d+)\s+(\d+)\s+(\d+)\s", data)
    return (int(head[1]), int(head[2]), data[head.end():]) if head else None


def lines(pattern):
    return [ln for ln in serial if re.search(pattern, ln)]


def spliced(pattern):
    return [m[0] for m in re.finditer(pattern, "\n".join(serial))]


def field(line, key):
    m = re.search(key + r"=(\d+)", line)
    return int(m[1]) if m else -1


def events(phase, kind, app=None):
    found = []
    for ln in spliced(r"taskbar: motion %s kind=%d app=\S+[^\n]*" % (phase, kind)):
        name = re.search(r"app=(\S+)", ln)[1]
        if app is None or name == app:
            found.append(ln)
    return found


def ink_width(img, box, face):
    width, _, pix = img
    xs = []
    for y in range(box[1], box[3]):
        for x in range(box[0], box[2]):
            o = (y * width + x) * 3
            if sum(abs(pix[o + c] - face[c]) for c in range(3)) > INK_THRESHOLD:
                xs.append(x)
    return (max(xs) - min(xs) + 1) if xs else 0


def pressed_width(directory):
    text = "\n".join(serial) if directory == out else "\n".join(
        open(os.path.join(directory, "serial.txt"), "rb").read().decode("latin1").split("\n"))
    geom = re.findall(r"taskbar: geom edge=\d+ x=(\d+) y=(\d+) w=(\d+) h=(\d+)", text)
    pins = re.findall(r"taskbar: pin settings x=(\d+) y=(\d+) w=(\d+) h=(\d+)", text)
    img = load("m1-pressed", directory)
    if not geom or not pins or img is None:
        return -1
    bx, by = int(geom[-1][0]), int(geom[-1][1])
    px, py, pw, ph = (int(v) for v in pins[-1])
    box = (bx + px + 4, by + py + 4, bx + px + pw - 4, by + py + ph - 4)
    o = ((by + py + ph // 2) * img[0] + bx + px + 2) * 3
    return ink_width(img, box, tuple(img[2][o:o + 3]))


pressed_w = pressed_width(out)
reference_w = pressed_width(off_dir) if off_dir else -1
ratio = pressed_w / reference_w if reference_w > 0 else -1
starts = spliced(r"taskbar: motion start kind=\d+ app=\S+")
if off:
    check(len(starts) == 0, "motion off: no motion animation started (%d lines)" % len(starts))
    print("  INFO  pressed ink width with motion off: %d px" % pressed_w)
    print("RESULT %d %d" % (ok, bad))
    sys.exit(0)
check(len(events("start", K_HOLD, "settings")) >= 1, "press on the icon starts the shrink")
rebound = events("start", K_REBOUND, "settings")
pm = field(rebound[0], "pm") if rebound else -1
wait = events("start", K_WAIT, "settings")
if pm < 0 and wait:
    pm = field(wait[0], "pm")
check(PRESS_MIN_PM <= pm <= PRESS_MAX_PM, "icon reached the pressed scale before the release: %d per mille" % pm)
check(reference_w > 0 and 0 < ratio <= SHRINK_MAX_RATIO, "the pressed icon is smaller than with motion off: ink %d vs %d px" % (pressed_w, reference_w))
check(len(wait) >= 1, "launching a pinned app starts the launch indicator")
pop = events("start", K_POP, "settings")
check(len(pop) >= 1, "the window arriving pops the icon")
done_pop = events("done", K_POP, "settings")
pop_ms = field(done_pop[0], "ms") if done_pop else -1
check(POP_MS[0] <= pop_ms <= POP_MS[1], "pop lasted %d ms" % pop_ms)
close = [ln for ln in lines(r"wm: animf id=\d+ kind=2 ")]
close_ms = field(close[0], "ms") if close else -1
check(len(close) >= 2 and CLOSE_MS[0] <= close_ms <= CLOSE_MS[1], "window close animation: %d frames of %d ms" % (len(close), close_ms))
ghost = events("start", K_GHOST)
check(len(ghost) >= 1, "an unpinned app's icon shrinks away when its last window closes")
done_ghost = events("done", K_GHOST)
ghost_ms = field(done_ghost[0], "ms") if done_ghost else -1
check(GHOST_MS[0] <= ghost_ms <= GHOST_MS[1], "icon shrink lasted %d ms" % ghost_ms)
dones = spliced(r"taskbar: motion done kind=\d+ app=\S+[^\n]*")
paints = [field(ln, "paint_max_us") for ln in dones]
averages = [field(ln, "paint_avg_us") for ln in dones]
print("  INFO  loop gaps %s ms, paint avg %s us" % ([field(ln, "gap") for ln in dones], averages))
check(bool(paints) and max(paints) <= MAX_PAINT_US, "bar paint during motion stays under the frame budget: max %s us" % (max(paints) if paints else -1))
check(bool(dones) and all(field(ln, "frames") >= MIN_FRAMES for ln in dones), "every animation ran at least %d frames" % MIN_FRAMES)
print("RESULT %d %d" % (ok, bad))
