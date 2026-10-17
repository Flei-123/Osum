#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
# tools/termtabs/check.py <outdir> -- reads serial.txt + the .ppm pictures of one tools/termtabs run (r1014 terminal tabs)
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


def px(img, x, y):
    w, h, b = img
    o = (y * w + x) * 3
    return b[o], b[o + 1], b[o + 2]


def differs(a, b, box):
    # number of pixels in box (x0, y0, x1, y1) that differ clearly between two pictures
    if a is None or b is None:
        return -1
    n = 0
    for y in range(box[1], box[3]):
        for x in range(box[0], box[2]):
            p, q = px(a, x, y), px(b, x, y)
            if abs(p[0] - q[0]) + abs(p[1] - q[1]) + abs(p[2] - q[2]) > 60:
                n += 1
    return n


tt = []
for ln in ser:
    m = re.search(r'tt: (new|switch|close) win=(\d+) grp=(\d+) tabs=(\d+)', ln)
    if m:
        tt.append((m[1], int(m[2]), int(m[3]), int(m[4])))
spawn = [ln for ln in ser if 'wm: tab shell started: ' in ln]
kinds = [t[0] for t in tt]

print('== witnesses ==')
chk(len(spawn) >= 2 and all(not l.endswith(': 0') for l in spawn), 'every new tab started /bin/term (%d spawns, none failed)' % len(spawn))
chk(kinds.count('new') >= 2, 'Ctrl+Shift+T and the plus button each made a tab (%d new)' % kinds.count('new'))
chk(any(t[0] == 'new' and t[3] == 2 for t in tt), 'the first new tab makes a group of 2')
chk(any(t[0] == 'new' and t[3] == 3 for t in tt), 'the second new tab makes a group of 3')
chk(kinds.count('switch') >= 3, 'Ctrl+Tab / Ctrl+Shift+Tab / a click on a tab switched (%d switches)' % kinds.count('switch'))
chk(any(t[0] == 'close' and t[3] >= 1 for t in tt), 'closing a tab leaves the group alive (tabs>=1 after close)')
chk(kinds.count('close') >= 2, 'Ctrl+Shift+W and the x button each closed a tab (%d closes)' % kinds.count('close'))
chk(len({t[2] for t in tt}) == 1, 'all tabs stay in one group (%s)' % sorted({t[2] for t in tt}))
wins = {t[1] for t in tt if t[0] == 'new'}
chk(len(wins) == kinds.count('new'), 'every new tab is a different window')
last = tt[-1] if tt else None
chk(last is not None and last[3] == 1, 'the end state is one terminal again')

print('== pictures ==')
names = ['t0-single', 't1-two', 't2-typed', 't3-switched', 't4-three', 't5-switch-click', 't6-plus-click', 't7-x-click', 't8-closed']
img = {n: load(n) for n in names}
chk(all(img[n] is not None for n in names), 'all %d pictures exist' % len(names))
# the strip: title bar of the terminal window, x 24..585 (window at 24,420), y 422..452
STRIP = (30, 424, 560, 452)
chk(differs(img['t0-single'], img['t1-two'], STRIP) > 400, 'the title strip changes when the second tab opens (%d px)' % differs(img['t0-single'], img['t1-two'], STRIP))
chk(differs(img['t1-two'], img['t4-three'], STRIP) > 400, 'the strip changes when the third tab opens')
chk(differs(img['t2-typed'], img['t3-switched'], (26, 456, 580, 830)) > 300, 'switching tabs changes the terminal content')
chk(differs(img['t0-single'], img['t8-closed'], STRIP) < 200, 'back to one terminal: the strip looks like the start again (%d px)' % differs(img['t0-single'], img['t8-closed'], STRIP))
print('== result ==')
print('  %d ok, %d fail' % (ok, bad))
sys.exit(1 if bad else 0)
