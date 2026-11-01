#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
"""Usage:
    shotcheck.py <shot.ppm|png> <serial.txt> --window=x,y,w,h [--win=N]
"""
import re
import sys
import os
sys.path.insert(0, os.path.join(os.environ.get("FIRN", "/root/firn"), "tools/testkit"))
from testkit import read_ppm


def read_any(path):
    if path.endswith(".ppm"):
        return read_ppm(path)
    from PIL import Image
    im = Image.open(path).convert("RGB")
    return im.size[0], im.size[1], im.tobytes()


class Pic(object):
    def __init__(self, path):
        self.w, self.h, self.d = read_any(path)

    def at(self, x, y):
        if x < 0 or y < 0 or x >= self.w or y >= self.h:
            return None
        o = (y * self.w + x) * 3
        return (self.d[o], self.d[o + 1], self.d[o + 2])


TEXT = re.compile(
    r"wlib: text win=(\d+) kind=(\d+) x=(\d+) base=(\d+) fg=(\d+) bg=(\d+)"
    r" tw=(\d+)(?: [a-z]+=-?\d+)* t=(.*)")

WINRE = re.compile(
    r"wlib: win id=(\d+) x=(\d+) y=(\d+) w=(\d+) h=(\d+) cx=(\d+) cy=(\d+)")

FONTRE = re.compile(r"wlib: font ui px=(\d+) asc=(\d+) h=(\d+)")


def parse(path, brand="settings: rect name=waa "):
    body = open(path, "rb").read().decode("latin1")
    cut = body.rfind(brand)
    tail = body[cut:] if cut >= 0 else body
    out = []
    for raw in tail.splitlines():
        m = TEXT.search(raw)
        if not m:
            continue
        out.append(dict(win=int(m.group(1)), kind=int(m.group(2)),
                        x=int(m.group(3)), base=int(m.group(4)),
                        fg=int(m.group(5)), bg=int(m.group(6)),
                        tw=int(m.group(7)), t=m.group(8)))
    wins = {}
    for m in WINRE.finditer(body):
        wins[int(m.group(1))] = dict(x=int(m.group(2)), y=int(m.group(3)),
                                     w=int(m.group(4)), h=int(m.group(5)),
                                     cx=int(m.group(6)), cy=int(m.group(7)))
    font = None
    for m in FONTRE.finditer(body):
        font = (int(m.group(2)), int(m.group(3)) - int(m.group(2)))
    return out, wins, font


def rgb(v):
    return ((v >> 16) & 255, (v >> 8) & 255, v & 255)


def near(a, b, tol):
    return max(abs(a[i] - b[i]) for i in range(3)) <= tol


def inkbox(pic, x0, y0, x1, y1, bg, tol):
    lo_x = lo_y = hi_x = hi_y = None
    pts = set()
    for y in range(max(y0, 0), min(y1, pic.h)):
        for x in range(max(x0, 0), min(x1, pic.w)):
            p = pic.at(x, y)
            if p is None or near(p, bg, tol):
                continue
            pts.add((x, y))
            lo_x = x if lo_x is None or x < lo_x else lo_x
            hi_x = x if hi_x is None or x > hi_x else hi_x
            lo_y = y if lo_y is None or y < lo_y else lo_y
            hi_y = y if hi_y is None or y > hi_y else hi_y
    if not pts:
        return None
    return (lo_x, lo_y, hi_x, hi_y, len(pts), pts)


def main(argv):
    if len(argv) < 3:
        print(__doc__)
        return 2
    pic = Pic(argv[1])
    brand = "settings: rect name=waa "
    for a in argv[3:]:
        if a.startswith("--cut="):
            brand = a[6:]
    texts, wins, font = parse(argv[2], brand)
    ox = oy = 0
    forced = False
    ww, wh = pic.w, pic.h
    want_win = None
    for a in argv[3:]:
        if a.startswith("--window="):
            ox, oy, ww, wh = (int(v) for v in a.split("=", 1)[1].split(","))
            forced = True
        elif a.startswith("--win="):
            want_win = int(a.split("=", 1)[1])
        elif a.startswith("--winat="):
            wx, wy = (int(v) for v in a.split("=", 1)[1].split(","))
            for k, v in wins.items():
                if v["x"] == wx and v["y"] == wy:
                    want_win = k
    if want_win is None and texts:
        count = {}
        for t in texts:
            count[t["win"]] = count.get(t["win"], 0) + 1
        want_win = max(count, key=lambda k: count[k])
    texts = [t for t in texts if t["win"] == want_win and t["t"].strip()]
    last = {}
    for t in texts:
        last[(t["kind"], t["t"])] = t
    texts = list(last.values())

    if not forced and want_win in wins:
        w = wins[want_win]
        ox, oy, ww, wh = w["cx"], w["cy"], w["w"], w["h"]
    asc, desc = font if font else (16, 6)
    bad = []
    boxes = []
    empty = 0
    for t in texts:
        x = ox + t["x"]
        y0 = oy + t["base"] - asc
        y1 = oy + t["base"] + desc
        x1 = x + t["tw"]
        box = inkbox(pic, x, y0, min(x1, ox + ww), y1, rgb(t["bg"]), 10)
        if box is None:
            empty += 1
            bad.append("EMPTY  '%s' at %d,%d w=%d (bg %06x): no pixel differs"
                       % (t["t"][:32], x, oy + t["base"], t["tw"], t["bg"]))
            continue
        boxes.append((t["t"], box, x, x1))
    cut = 0
    for name, b, x, x1 in boxes:
        if x < ox or b[1] < oy or x1 > ox + ww or b[3] >= oy + wh:
            cut += 1
            bad.append("CUT    '%s' at %d..%d (ink %s) leaves the window "
                       "%d,%d %dx%d"
                       % (name[:32], x, x1, b[:4], ox, oy, ww, wh))
    over = 0
    for i in range(len(boxes)):
        for j in range(i + 1, len(boxes)):
            a, b = boxes[i][1], boxes[j][1]
            if a[0] > b[2] or b[0] > a[2] or a[1] > b[3] or b[1] > a[3]:
                continue
            if not (a[5] & b[5]):
                continue
            over += 1
            if over <= 12:
                bad.append("OVER   '%s' %s and '%s' %s"
                           % (boxes[i][0][:24], a[:4],
                              boxes[j][0][:24], b[:4]))
    print("shotcheck: win %s  texts %d  measured %d  empty %d  cut %d  "
          "overlapping %d" % (want_win, len(texts), len(boxes), empty, cut,
                              over))
    for line in bad[:30]:
        print("  " + line)
    return 0 if (empty == 0 and cut == 0 and over == 0) else 1


if __name__ == "__main__":
    sys.exit(main(sys.argv))
