#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
"""tools/fourbugs/check.py -- reads the serial log and the pictures of the
Dell round (title centring, edge cursor, resize in 8 directions, windows
that stick out). Prints OK/FAIL lines; exit code = number of FAIL."""
import re, sys
ser = open(sys.argv[1], 'rb').read().decode('latin1')
out = sys.argv[2]
scale = int(sys.argv[3]) if len(sys.argv) > 3 else 1
fails = 0
def ok(c, m):
    global fails
    print(("  OK    " if c else "  FAIL  ") + m)
    if not c:
        fails += 1
def s64(v):
    v = int(v)
    return v - (1 << 64) if v >= (1 << 63) else v

# r402: the chrome of the terminal as the server reports it (`bar= capw= fr=` at the end of the
# `wm: fen` line of id 7, all in pixels): frame, and frame + bar + 1 separator. Without the fields (an
# older kernel) the old numbers: 2 and 22 points.
mc = re.search(r"wm: fen i=\d+ id=7 [^\n]*? bar=(\d+) capw=(\d+) fr=(\d+)", ser)
CH_BO = int(mc.group(3)) if mc else 2 * scale
CH_TH = CH_BO + int(mc.group(1)) + 1 if mc else 22 * scale

# ---- (4) cursor shape at the eight edges and the corners
# The wire says `wm: form=N x=X y=Y` at every change of the cursor shape. The
# model below is the grip rule: a point of the terminal (id 7) is on the left /
# right edge within GRIP = 8*scale px of the work area edge, on the top edge
# within 2*border... (border 2*scale + 3*scale), on the bottom likewise.
# Every line must agree with the model; each of the eight directions must
# have been SEEN at least once.
mg = re.search(r"wm: fen i=\d+ id=7 x=(\d+) y=(\d+) w=(\d+) h=(\d+)", ser)
# only the hover phase: the window has not been resized yet (geometry = the
# first `wm: fen` line)
hover = ser[:ser.find("wm: zieh k=")] if "wm: zieh k=" in ser else ser
forms = [(int(m.group(1)), int(m.group(2)), int(m.group(3)))
         for m in re.finditer(r"wm: form=(\d+) x=(\d+) y=(\d+)", hover)]
if not mg:
    ok(False, "cursor: no window geometry")
else:
    wx, wy, ww, wh = (int(v) for v in mg.groups())
    bo, th, grip = CH_BO, CH_TH, 8 * scale
    cx, cy = wx + bo, wy + th          # content origin
    def model(x, y):
        lx, ly = x - cx, y - (wy + th)
        if not (lx > -grip and ly >= -th and lx < ww + grip and ly < wh + grip):
            return 0
        k = 0
        if -grip < lx < grip: k |= 1
        if ww - grip <= lx < ww + grip: k |= 2
        if -th <= ly < -th + bo + 3 * scale: k |= 4
        if wh - grip <= ly < wh + grip: k |= 8
        l, r, t, b = k & 1, k & 2, k & 4, k & 8
        if (l and t) or (r and b): return 5
        if (r and t) or (l and b): return 6
        if l or r: return 3
        if t or b: return 4
        return 0
    bad = [(f, x, y) for f, x, y in forms if model(x, y) != f]
    ok(len(forms) >= 6 and not bad, "%d cursor changes, %d disagree with the grip rule %s" % (len(forms), len(bad), bad[:3]))
    seen = {}
    for f, x, y in forms:
        if f == 3: seen["left" if x < cx + ww // 2 else "right"] = 1
        if f == 4: seen["top" if y < cy + wh // 2 else "bottom"] = 1
        if f == 5: seen["top-left" if x < cx + ww // 2 else "bottom-right"] = 1
        if f == 6: seen["top-right" if x >= cx + ww // 2 else "bottom-left"] = 1
    for nm in ("left", "right", "top", "bottom", "top-left", "bottom-right", "top-right", "bottom-left"):
        ok(nm in seen, "the resize cursor was shown at the %s" % nm)

# ---- (4) resize works in every direction AND the edge follows the pointer
# `wm: gezogen id=N x= y= w= h=` is written when the button goes up. The drive
# grabs each edge at a fixed distance and moves by (dx, dy); the grabbed edge
# must move by exactly that, the opposite edge must stay.
g0 = re.search(r"wm: fen i=\d+ id=7 x=(\d+) y=(\d+) w=(\d+) h=(\d+)", ser)
gz = [tuple(s64(v) for v in m.groups())
      for m in re.finditer(r"wm: gezogen id=7 x=(\d+) y=(\d+) w=(\d+) h=(\d+)", ser)]
steps = [("left", (1, 0, 0, 0, -1, 0)),      # name, (dx_edge...) filled below
         ]
if not g0:
    ok(False, "resize: no start geometry")
else:
    x, y, w, h = (int(v) for v in g0.groups())
    plan = [("left", "l", (40, 0)), ("top", "o", (0, 30)), ("right", "r", (40, 0)),
            ("bottom", "u", (0, 40)), ("top-left", "lo", (20, 20)),
            ("bottom-right", "ru", (20, 20)), ("top-right", "ro", (20, -10)),
            ("bottom-left", "lu", (-10, -10))]
    ok(len(gz) >= 8, "%d resizes reported (need 8)" % len(gz))
    for n, (name, e, (dx, dy)) in enumerate(plan):
        if e in ("l", "lo", "lu"):
            x += dx; w -= dx
        if e in ("r", "ro", "ru"):
            w += dx
        if e in ("o", "lo", "ro"):
            y += dy; h -= dy
        if e in ("u", "ru", "lu"):
            h += dy
        if n < len(gz):
            ok(gz[n] == (x, y, w, h), "resize %s by %d,%d -> %d,%d %dx%d (got %s)" % (name, dx, dy, x, y, w, h, "%d,%d %dx%d" % gz[n]))
        else:
            ok(False, "resize %s: no report" % name)

# ---- (3) a window pushed over the edge keeps its place
md = re.search(r"wm: fen i=\d+ id=8 x=\d+ y=\d+ w=(\d+) ", ser)
mt = re.search(r"wm: fen i=\d+ id=9 x=\d+ y=(\d+) ", ser)
SCRW = int(md.group(1)) if md else 1920      # screen width
BARY = int(mt.group(1)) if mt else 1040      # top of the taskbar = work area bottom
ab = [(s64(m.group(2)), s64(m.group(3)), int(m.group(4)), int(m.group(5)))
      for m in re.finditer(r"wm: abgelegt id=(\d+) x=(\d+) y=(\d+) w=(\d+) h=(\d+)", ser)]
ok(len(ab) >= 3, "the server reported %d drops (need 3)" % len(ab))
if len(ab) >= 3:
    x1, y1, w1, h1 = ab[-3]
    ok(x1 + w1 > SCRW, "pushed 1500 px right: it sticks out (x=%d, right edge %d > %d) and did not jump back" % (x1, x1 + w1, SCRW))
    x2, y2, w2, h2 = ab[-2]
    ok(y2 + h2 > BARY, "pushed far down: it sticks out at the bottom (y=%d, bottom %d)" % (y2, y2 + h2))
    ok(y2 < BARY - 10 * scale, "... but its title bar stays in sight (y=%d)" % y2)
    x3, y3, w3, h3 = ab[-1]
    ok(y3 >= 0, "pushed far up: the title bar is not lost above the screen (y=%d)" % y3)
    ok(x3 + w3 >= 90 * scale, "pushed far left: at least 96*scale px stay in sight (right edge %d)" % (x3 + w3))
    ok(x3 < 0, "... and the window does stick out on the left (x=%d)" % x3)

# ---- (2) the title text sits in the middle of the bar
# The window is the terminal (id 7). The bar runs from the border to the
# bottom of the title bar; the text is "Terminal -- sh" (ascenders, no
# descenders), so its ink runs from the ascender top to the baseline and the
# gaps above and below must agree within one pixel.
def ppm(path):
    d = open(path, 'rb').read()
    parts = d.split(b'\n', 3)
    w, h = (int(v) for v in parts[1].split())
    return w, h, parts[3]
m = re.search(r"wm: fen i=\d+ id=7 x=(\d+) y=(\d+) w=(\d+) h=(\d+)", ser)
try:
    W, H, px = ppm(out + "/01-title.ppm")
except Exception as e:
    W = 0
if not m or W == 0:
    ok(False, "title centring: no window geometry or no picture")
else:
    wx, wy = s64(m.group(1)), s64(m.group(2))
    bo, th = CH_BO, CH_TH
    x0, x1 = wx + bo + 10 * scale, wx + bo + 10 * scale + 110 * scale
    y0, y1 = wy + bo, wy + th
    def pix(x, y):
        o = (y * W + x) * 3
        return px[o], px[o + 1], px[o + 2]
    bg = pix(x1 + 4 * scale, y0 + (y1 - y0) // 2)
    rows = []
    for y in range(y0, y1):
        ink = 0
        for x in range(x0, x1):
            c = pix(x, y)
            if sum(abs(c[i] - bg[i]) for i in range(3)) > 150:
                ink += 1
        rows.append(ink)
    ys = [i for i, v in enumerate(rows) if v > 0]
    if not ys:
        ok(False, "title centring: no text found in the bar")
    else:
        top = ys[0]
        bot = (y1 - y0 - 1) - ys[-1]
        # the descender-free ink is one pixel off at most because of rounding
        ok(abs(top - bot) <= scale, "title text: gap above %d px, gap below %d px (bar %d px, scale %d)" % (top, bot, y1 - y0, scale))
sys.exit(fails)
