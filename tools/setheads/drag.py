# SPDX-License-Identifier: GPL-2.0-only
import re
import sys


def rect(text, name):
    m = None
    for m in re.finditer(r"settings: rect name=%s x=(\d+) y=(\d+) w=(\d+) h=(\d+) ax=(\d+) ay=(\d+)" % name, text):
        pass
    if not m:
        raise SystemExit("rect %s missing" % name)
    return [int(v) for v in m.groups()]


def heads(text):
    line = [l for l in text.splitlines() if l.startswith("settings: arrange cv=")][-1]
    cv = [int(v) for v in re.search(r"cv=(\d+),(\d+),(\d+),(\d+)", line).groups()]
    hs = {}
    for m in re.finditer(r" h(\d)=(\d+),(\d+),(\d+),(\d+),(\d+),(\d+)", line):
        hs[int(m.group(1))] = [int(m.group(i)) for i in range(2, 8)]
    return cv, hs


def go(x, y):
    out = ["mouse_move -120 -120"] * 14
    dx, dy = x, y
    while dx > 0 or dy > 0:
        sx, sy = min(dx, 120), min(dy, 120)
        out.append("mouse_move %d %d" % (sx, sy))
        dx -= sx
        dy -= sy
    return out


def move_rel(out, x0, y0, x1, y1):
    dx, dy = x1 - x0, y1 - y0
    steps = min(max((max(abs(dx), abs(dy), 1) + 19) // 20, 1), 30)
    vx = vy = 0
    for i in range(1, steps + 1):
        nx, ny = dx * i // steps, dy * i // steps
        out.append("mouse_move %d %d" % (nx - vx, ny - vy))
        vx, vy = nx, ny


def drag(p0, p1):
    out = go(*p0)
    out += ["warte 1", "mouse_button 1", "warte 1"]
    move_rel(out, p0[0], p0[1], p1[0], p1[1])
    out += ["warte 1", "mouse_button 0", "warte 2"]
    return out


def click(p):
    return go(*p) + ["warte 1", "mouse_button 1", "mouse_button 0", "warte 2"]


def main():
    text = open(sys.argv[1], errors="replace").read()
    mode = sys.argv[2]
    ax, ay = rect(text, "arr")[4:6]
    cv, hs = heads(text)
    offx, offy = ax - cv[0], ay - cv[1]
    f = (hs[0][2] / 640.0) if 0 in hs else 1.0
    def center(i):
        h = hs[i]
        return (offx + h[0] + h[2] // 2, offy + h[1] + h[3] // 2)
    if mode in ("below", "overlap", "detached"):
        h0, h1 = hs[0], hs[1]
        scale = h0[2] / 640.0
        c1 = center(1)
        if mode == "below":
            tgt = (offx + h0[0] + h0[2] // 2, offy + h0[1] + h0[3] + h1[3] // 2 + 2)
        elif mode == "overlap":
            tgt = (offx + h0[0] + h0[2] // 2 + 6, offy + h0[1] + h0[3] // 2 + 6)
        else:
            tgt = (c1[0], offy + h0[1] + int(600 * scale) + h1[3] // 2)
        print("\n".join(drag(c1, tgt)))
        return
    if mode == "scale":
        hx, hy, hw, hh, hax, hay = rect(text, "hsc")
        pt = (hax + hw // 2, hay + hh // 2)
        out = click(pt)
        out += ["sendkey down", "warte 1", "sendkey down", "warte 1", "sendkey ret", "warte 2"]
        print("\n".join(out))
        return
    raise SystemExit("mode?")


main()
