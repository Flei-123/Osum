#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
import os
import re
import sys

out = sys.argv[1]
off = len(sys.argv) > 2 and sys.argv[2] == "off"
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
MAX_GAP_MS = 60
MIN_FRAMES = 3


def check(cond, message):
    global ok, bad
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


def lines(pattern):
    return [ln for ln in serial if re.search(pattern, ln)]


def field(line, key):
    m = re.search(key + r"=(\d+)", line)
    return int(m[1]) if m else -1


def events(phase, kind, app=None):
    found = []
    for ln in lines(r"^taskbar: motion %s kind=%d app=" % (phase, kind)):
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


def icon_widths():
    geom = re.findall(r"taskbar: geom edge=\d+ x=(\d+) y=(\d+) w=(\d+) h=(\d+)", "\n".join(serial))
    pins = re.findall(r"taskbar: pin settings x=(\d+) y=(\d+) w=(\d+) h=(\d+)", "\n".join(serial))
    idle, pressed = load("m0-idle"), load("m1-pressed")
    if not geom or not pins or idle is None or pressed is None:
        return -1, -1
    bx, by = int(geom[-1][0]), int(geom[-1][1])
    px, py, pw, ph = (int(v) for v in pins[-1])
    box = (bx + px + 4, by + py + 4, bx + px + pw - 4, by + py + ph - 4)
    results = []
    for img in (idle, pressed):
        o = ((by + py + ph // 2) * img[0] + bx + px + 2) * 3
        results.append(ink_width(img, box, tuple(img[2][o:o + 3])))
    return results[0], results[1]


idle_w, pressed_w = icon_widths()
ratio = pressed_w / idle_w if idle_w > 0 else -1
starts = lines(r"^taskbar: motion start")
if off:
    check(len(starts) == 0, "motion off: no motion animation started (%d lines)" % len(starts))
    check(idle_w > 0 and ratio >= KEEP_MIN_RATIO, "motion off: the pressed icon keeps its size (ink %d -> %d)" % (idle_w, pressed_w))
    print("RESULT %d %d" % (ok, bad))
    sys.exit(0)
check(len(events("start", K_HOLD, "settings")) >= 1, "press on the icon starts the shrink")
rebound = events("start", K_REBOUND, "settings")
pm = field(rebound[0], "pm") if rebound else -1
check(PRESS_MIN_PM <= pm <= PRESS_MAX_PM, "icon reached the pressed scale before the release: %d per mille" % pm)
check(idle_w > 0 and 0 < ratio <= SHRINK_MAX_RATIO, "the pressed icon is smaller on the picture: ink %d -> %d px" % (idle_w, pressed_w))
done_rebound = events("done", K_REBOUND, "settings")
check(len(done_rebound) >= 1 and field(done_rebound[0], "frames") >= MIN_FRAMES, "rebound ran %s frames" % (field(done_rebound[0], "frames") if done_rebound else -1))
wait = events("start", K_WAIT, "settings")
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
gaps = [field(ln, "gap") for ln in lines(r"^taskbar: motion done")]
check(bool(gaps) and max(gaps) <= MAX_GAP_MS, "frame gaps of the bar loop during motion: max %s ms" % (max(gaps) if gaps else -1))
print("RESULT %d %d" % (ok, bad))
