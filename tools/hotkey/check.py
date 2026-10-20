#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
# tools/hotkey/check.py <outdir> -- reads serial.txt + the .ppm pictures of one tools/hotkey run (r1309: Ctrl+Shift+T as a scancode burst)
import os, re, sys

out = sys.argv[1]
ser = open(os.path.join(out, 'serial.txt'), 'rb').read().decode('latin1').split('\n')
ok = bad = 0


def chk(cond, msg):
    global ok, bad
    if cond:
        ok += 1
        print('  OK    ' + msg)
    else:
        bad += 1
        print('  FAIL  ' + msg)


def load(name):
    p = os.path.join(out, name + '.ppm')
    if not os.path.exists(p):
        return None
    d = open(p, 'rb').read()
    m = re.match(rb'P6\s+(\d+)\s+(\d+)\s+(\d+)\s', d)
    if not m:
        return None
    return int(m[1]), int(m[2]), d[m.end():]


def lit(img, box):
    # pixels in box (x0, y0, x1, y1) that are not black-ish: how much is drawn there
    if img is None:
        return -1
    w, h, b = img
    n = 0
    for y in range(box[1], box[3], 2):
        for x in range(box[0], box[2], 2):
            o = (y * w + x) * 3
            if b[o] + b[o + 1] + b[o + 2] > 60:
                n += 1
    return n


new = [ln for ln in ser if re.search(r'tt: new win=\d+ grp=\d+ tabs=\d+', ln)]
free = [ln for ln in ser if re.search(r'tt: free win=\d+', ln)]
spawn = [ln for ln in ser if 'wm: tab shell started: ' in ln]
print('== witnesses ==')
chk(len(new) >= 1, 'A: Ctrl+Shift+T as a burst on a focused terminal makes a tab (%d tt: new)' % len(new))
chk(len(free) == 1, 'C: Ctrl+Shift+T with no terminal opens a new terminal (%d tt: free)' % len(free))
chk(len(new) >= 2, 'D: Ctrl+Shift+T in the terminal made by C makes a tab (%d tt: new in all)' % len(new))
chk(len(spawn) >= 3 and all(not l.endswith(': 0') for l in spawn), 'every request started /bin/term (%d spawns, none failed)' % len(spawn))
print('== pictures (the terminal area x 0..1000, y 420..1000) ==')
box = (0, 440, 1000, 1000)
b0, c1, d1 = load('b0-none'), load('c1-free'), load('d1-tab')
n_b0, n_c1, n_d1 = lit(b0, box), lit(c1, box), lit(d1, box)
chk(n_b0 >= 0 and n_b0 < 400, 'B: after both terminals are closed the area is empty (%d lit samples)' % n_b0)
chk(n_c1 > n_b0 + 2000, 'C: the new terminal is VISIBLE on the screen (%d lit samples vs %d)' % (n_c1, n_b0))
chk(n_d1 > n_b0 + 2000, 'D: the tab is visible too (%d lit samples)' % n_d1)
print('%d ok, %d fail' % (ok, bad))
sys.exit(1 if bad else 0)
