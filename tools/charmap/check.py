#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
"""tools/charmap/check.py <outdir> [nocheck] [<other-outdir>] -- judge serial + pictures of tools/charmap/shot.sh (P-015).

The witness for "does the font have this glyph" is NOT the app: it is the cmap of the shipped font file (assets/osum-sans.ttf,
read with fontTools). Counter-proof mode `nocheck`: the app was started with `charmap nocheck` (every code point counts as
present); the same drehbuch must then be CAUGHT by the witness (check passes when the app is wrong)."""
import os, re, sys
from fontTools.ttLib import TTFont

out = sys.argv[1]
counter = len(sys.argv) > 2 and sys.argv[2] == "nocheck"
other = sys.argv[3] if len(sys.argv) > 3 else ""
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

root = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..")
cmap = TTFont(os.path.join(root, "assets", "osum-sans.ttf")).getBestCmap()
ser = open(os.path.join(out, "serial.txt"), "rb").read().decode("latin1").replace("\r", "")
def has(cp): return cp in cmap

if "charmap: ready" not in ser:
    say(False, "the program reported `charmap: ready` (no window?)")
    print("RESULT ok=%d fail=%d" % (ok, fail)); sys.exit(1)
if counter:
    gl = re.findall(r"charmap: goto U\+([0-9A-F]+) present=(\d)", ser)
    em = [p for c, p in gl if int(c, 16) == 0x1F600]
    say(em and em[-1] == "1" and not has(0x1F600),
        "COUNTER-PROOF: with `nocheck` the app claims U+1F600 present=1 while the font file has no such glyph (the witness catches it)")
    blk = re.findall(r"charmap: block (\d+) lo=(\w+) hi=(\w+) shown=(\d+) present=(\d+)", ser)
    wrong = [b for b in blk if int(b[4]) != sum(1 for k in range(int(b[1], 16), int(b[2], 16) + 1) if has(k))]
    say(len(wrong) >= 1, "COUNTER-PROOF: block present counts disagree with the font file in %d block reports" % len(wrong))
    print("RESULT ok=%d fail=%d" % (ok, fail)); sys.exit(1 if fail else 0)

# 1. block reports: counts equal the font file's cmap
blk = re.findall(r"charmap: block (\d+) lo=(\w+) hi=(\w+) shown=(\d+) present=(\d+) only=(\d) page=(\d+)/(\d+) name=(.*)", ser)
say(len(blk) >= 4, "block reports on the serial line (%d)" % len(blk))
bad = []
for i, lo, hi, shown, pres, only, pg, pgs, name in blk:
    exp = sum(1 for k in range(int(lo, 16), int(hi, 16) + 1) if has(k))
    if int(pres) != exp: bad.append((name, pres, exp))
say(not bad, "present= of every block equals the glyph count of the font file (%d reports; mismatches %s)" % (len(blk), bad[:3]))
b0 = blk[0]
say(b0[1] == "0020" and b0[2] == "007F" and b0[3] == "95" and b0[4] == "95", "first block is Basic Latin 0020-007F with 95 of 95 glyphs (%s)" % (b0[1:6],))
# 2. copy: first cell, euro, the missing emoji
cp = re.findall(r"charmap: copy U\+([0-9A-F]+) present=(\d) len=(\d) clip=(\w+)", ser)
say(len(cp) >= 3, "three clicks copied (%d copy lines)" % len(cp))
if len(cp) >= 3:
    say(cp[0] == ("0061", "1", "1", "ok"), "typing one character finds its cell; a grid click copies U+0061, 1 byte UTF-8, clipboard read back ok (%s)" % (cp[0],))
    say(cp[1] == ("20AC", "1", "3", "ok"), "the euro sign copies as 3 UTF-8 bytes, clipboard ok (%s)" % (cp[1],))
    say(cp[2][:2] == ("1F600", "0") and cp[2][2] == "4", "a glyph the font lacks is reported present=0 and still copies 4 bytes (%s)" % (cp[2],))
# 3. search: goto lines agree with the witness
gl = re.findall(r"charmap: goto U\+([0-9A-F]+) present=(\d) block=(\d+)", ser)
for want in (0x20AC, 0x1F600):
    r = [g for g in gl if int(g[0], 16) == want]
    say(bool(r) and int(r[-1][1]) == int(has(want)), "search U+%04X -> present=%s, the font file says %s" % (want, r[-1][1] if r else "-", int(has(want))))
r = [g for g in gl if int(g[0], 16) == 0x20AC]
say(bool(r) and any(b[0] == r[-1][2] and b[1] == "20A0" for b in blk), "U+20AC opens the block Currency Symbols (20A0-20CF)")
say("charmap: nomatch" in ser, "a search that matches nothing reports `nomatch`")
# 4. pages: Latin Extended-B has 208 code points = 2 pages, `Next` shows page 2; the font has none of them
eb = [b for b in blk if b[1] == "0180"]
say(any(b[7] == "2" for b in eb) and any(b[6] == "1" for b in eb), "Latin Extended-B: 2 pages, Next shows page 2 (%s)" % [(b[6], b[7]) for b in eb][:3])
say(eb and all(b[4] == "0" for b in eb), "Latin Extended-B: the font has none of it, present=0 for every report")
# 5. the checkbox: `only` 1 hides, 0 shows everything
oc = [(b[5], b[3], b[4]) for b in blk if b[1] == "20A0"]
say(any(o == "1" and s == p for o, s, p in oc) and any(o == "0" and s == "48" for o, s, p in oc),
    "Currency Symbols: only=1 shows just the present glyphs, only=0 all 48 (%s)" % oc[:4])
# 6. geometry + pictures
rects = {}
for n_, *v in re.findall(r"charmap: rect name=(\w+) x=(\d+) y=(\d+) w=(\d+) h=(\d+) ax=(\d+) ay=(\d+)", ser):
    rects[n_] = tuple(int(x) for x in v)
say(all(k in rects for k in ("cell0", "search", "only", "next", "prev")), "the window reports its widgets (%s)" % sorted(rects))
W, H = 1280, 800
bad = [k for k, v in rects.items() if not (0 <= v[4] and v[4] + v[2] <= W and 0 <= v[5] and v[5] + v[3] <= H)]
say(not bad, "every widget lies inside the screen (%s)" % bad)
def crop(name, x, y, w, h):
    wa, ha, da = load_ppm(os.path.join(out, name + ".ppm")); r = []
    for yy in range(y, y + h):
        r.append(da[(yy * wa + x) * 3:(yy * wa + x + w) * 3])
    return b"".join(r)
def ink(buf):  # dark pixels (glyph strokes) in an RGB crop
    return sum(1 for i in range(0, len(buf), 3) if buf[i] < 110 and buf[i + 1] < 110 and buf[i + 2] < 140)
try:
    g = rects.get("cell0")
    # the euro picture: its one cell has dark ink (the glyph is drawn); the missing-glyph cell differs from it
    d_open, d_eur = crop("00-open", g[4], g[5], g[2], g[3]), crop("02-euro", g[4], g[5], g[2], g[3])
    say(ink(d_eur) >= 8, "02-euro: the first cell shows the euro glyph (%d ink px)" % ink(d_eur))
    say(d_open != d_eur, "02-euro: the grid changed after the search")
    # the selected cell AT THE TIME of the emoji search (the last `sel` line belongs to a later layout)
    at = ser.index("charmap: goto U+1F600")
    ms = re.search(r"charmap: rect name=sel x=(\d+) y=(\d+) w=(\d+) h=(\d+) ax=(\d+) ay=(\d+)", ser[at:])
    s = tuple(int(v) for v in ms.groups()) if ms else None
    em = crop("05-emoji", s[4], s[5], s[2], s[3]) if s else b""
    flat = len(set(em[i:i + 3] for i in range(0, len(em), 3)))
    say(em and flat >= 3 and ink(em) >= 8, "05-emoji: the missing-glyph cell is drawn with a mark (%d colours, %d ink px)" % (flat, ink(em)))
    if other:
        wa, ha, da = load_ppm(os.path.join(other, "05-emoji.ppm"))
        ob = b"".join(da[((s[5] + yy) * wa + s[4]) * 3:((s[5] + yy) * wa + s[4] + s[2]) * 3] for yy in range(s[3]))
        dif = sum(1 for i in range(0, len(em), 3) if em[i:i + 3] != ob[i:i + 3])
        say(dif >= 10, "05-emoji: missing-glyph cell differs from the nocheck run (%d px): the cross/grey marking is real" % dif)
except (OSError, TypeError) as e:
    say(False, "pictures missing/incomplete: %s" % e)
print("RESULT ok=%d fail=%d" % (ok, fail))
sys.exit(1 if fail else 0)
