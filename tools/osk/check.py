#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
import os, re, sys

out = sys.argv[1]
counter = len(sys.argv) > 2 and sys.argv[2] == "badscan"
ok = fail = 0
W, H = 1280, 800
EXPECT = ["a", "aS", "aSD", "aSD1", "aSD1!", "aSD1!z", "aSD1!zy", "aSD1!zy@", "aSD1!zy", "aSD1!zay"]


def say(good, msg):
    global ok, fail
    if good:
        ok += 1
    else:
        fail += 1
    print(("  OK    " if good else "  FAIL  ") + msg)


def load_ppm(path):
    d = open(path, "rb").read()
    f = []
    at = 2
    while len(f) < 3:
        while d[at:at + 1].isspace():
            at += 1
        s = at
        while not d[at:at + 1].isspace():
            at += 1
        f.append(int(d[s:at]))
    return f[0], f[1], d[at + 1:]


def crop(name, r):
    wa, ha, da = load_ppm(os.path.join(out, name + ".ppm"))
    x, y, w, h = r[4], r[5], r[2], r[3]
    return b"".join(da[((y + yy) * wa + x) * 3:((y + yy) * wa + x + w) * 3] for yy in range(h))


def diff(a, b):
    return sum(1 for i in range(0, min(len(a), len(b)), 3) if a[i:i + 3] != b[i:i + 3])


ser = open(os.path.join(out, "serial.txt"), "rb").read().decode("latin1").replace("\r", "")
if "osk: ready" not in ser or "osktest: ready" not in ser:
    say(False, "both programs reported ready (no window?)")
    print("RESULT ok=%d fail=%d" % (ok, fail))
    sys.exit(1)

texts = re.findall(r"osktest: text=([^\n]*)", ser)
if counter:
    say(texts != EXPECT[:len(texts)] or len(texts) < len(EXPECT),
        "COUNTER-PROOF: with `osk badscan` the typed text differs from the expected one (%s)" % texts[:4])
    keys = re.findall(r"osk: key sc=(\d+) cp=(\d+) sh=(\d) alt=(\d) ctl=(\d) inj=(\d)", ser)
    say(keys and all(k[5] == "1" for k in keys), "COUNTER-PROOF: injection itself still succeeded (inj=1 on %d keys), only the scancode was wrong" % len(keys))
    print("RESULT ok=%d fail=%d" % (ok, fail))
    sys.exit(1 if fail else 0)

say(texts[:len(EXPECT)] == EXPECT, "the witness entry received exactly the clicked keys, in order, with Shift, Caps, layout switch, AltGr, Backspace and a cursor arrow (%s)" % texts[:len(EXPECT)])
say(len(texts) > len(EXPECT) and "again" in texts[-1], "the real keyboard still types into the entry while the keyboard window is open (%s)" % texts[-1:])
say(ser.count("osk: ready") == 1 and "osk: toggled" in ser, "a second `osk` start opened no second window and reported the toggle (ready x%d)" % ser.count("osk: ready"))
keys = re.findall(r"osk: key sc=(\d+) cp=(\d+) sh=(\d) alt=(\d) ctl=(\d) inj=(\d)", ser)
say(len(keys) >= 10 and all(k[5] == "1" for k in keys), "every key press was accepted by the kernel (inj=1 on %d key lines)" % len(keys))
shifted = [k for k in keys if k[0] == "31" and k[2] == "1"]
say(len(shifted) == 1 and shifted[0][1] == "83", "Shift+s is reported as code point 83 (S) with sh=1 (%s)" % shifted[:1])
capsd = [k for k in keys if k[0] == "32"]
say(len(capsd) == 1 and capsd[0][1] == "68" and capsd[0][2] == "1", "Caps+d is reported as code point 68 (D), shift applied only because of Caps (%s)" % capsd[:1])
zs = [k for k in keys if k[0] == "44"]
say(len(zs) == 2 and zs[0][1] == "122" and zs[1][1] == "121", "scancode 44 types z on the US layout and y after the layout key (DE) (%s)" % zs)
at = [k for k in keys if k[0] == "16" and k[3] == "1"]
say(len(at) == 1 and at[0][1] == "64", "AltGr+q types code point 64 (@) on DE (%s)" % at)

rects = {}
for n_, *v in re.findall(r"osk: rect name=(\w+) x=(\d+) y=(\d+) w=(\d+) h=(\d+) ax=(\d+) ay=(\d+)", ser):
    rects.setdefault(n_, tuple(int(x) for x in v))
say(len(rects) >= 60, "the keyboard reported %d key rectangles" % len(rects))
bad = [k for k, v in rects.items() if not (v[4] >= 0 and v[4] + v[2] <= W and v[5] >= 0 and v[5] + v[3] <= H - 30)]
say(not bad, "every key lies inside the screen and above the task bar band (%s)" % bad[:3])
say(max(v[5] + v[3] for v in rects.values()) > H // 2, "the keyboard sits in the lower half of the screen (bottom %d)" % max(v[5] + v[3] for v in rects.values()))
entry = re.findall(r"osktest: rect name=entry x=\d+ y=\d+ w=(\d+) h=(\d+) ax=(\d+) ay=(\d+)", ser)
if entry:
    ew, eh, ex, ey = (int(v) for v in entry[0])
    cover = [k for k, v in rects.items() if v[4] < ex + ew and v[4] + v[2] > ex and v[5] < ey + eh and v[5] + v[3] > ey]
    say(not cover, "no key covers the witness entry (%s)" % cover[:3])
xs = [v[4] for v in rects.values()]
ys = [v[5] for v in rects.values()]
say(min(xs) > 100 and max(v[4] + v[2] for v in rects.values()) < W - 100, "the keyboard is centred (x %d..%d)" % (min(xs), max(v[4] + v[2] for v in rects.values())))
sp = rects.get("space")
say(sp is not None and sp[2] >= 8 * 10, "the space bar is wide (%s)" % (sp,))

try:
    k1e, sh, k20, caps, k2c, k10, lay = (rects[n] for n in ("key1e", "shift", "key20", "caps", "key2c", "key10", "lay"))
    d_shift_key = diff(crop("00-open", k1e), crop("01-shift", k1e))
    say(d_shift_key >= 30, "latched Shift redraws the letter key (a -> A, %d px differ)" % d_shift_key)
    d_shift_self = diff(crop("00-open", sh), crop("01-shift", sh))
    say(d_shift_self >= 300, "the latched Shift key is drawn with the accent fill (%d px differ)" % d_shift_self)
    d_caps = diff(crop("00-open", caps), crop("02-caps", caps))
    say(d_caps >= 300, "Caps shows its state (%d px differ)" % d_caps)
    d_de = diff(crop("00-open", k2c), crop("03-de", k2c))
    say(d_de >= 20, "the layout key relabels the keys (z -> y, %d px differ)" % d_de)
    d_alt = diff(crop("00-open", k10), crop("04-altgr", k10))
    say(d_alt >= 20, "latched AltGr relabels the keys (q -> @, %d px differ)" % d_alt)
    d_lay = diff(crop("00-open", lay), crop("03-de", lay))
    say(d_lay >= 20, "the layout key shows the layout in force (US -> DE, %d px differ)" % d_lay)
    d_gone = diff(crop("05-end", k1e), crop("06-gone", k1e))
    say(d_gone >= 30, "the second start closed the keyboard: its key area changed (%d px differ)" % d_gone)
    colours = len(set(crop("00-open", k1e)[i:i + 3] for i in range(0, len(crop("00-open", k1e)), 3)))
    say(colours >= 3, "a key is drawn (face, border, glyph: %d colours)" % colours)
except (KeyError, OSError, TypeError) as e:
    say(False, "pictures or rectangles missing: %s" % e)
print("RESULT ok=%d fail=%d" % (ok, fail))
sys.exit(1 if fail else 0)
