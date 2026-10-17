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
chk(kinds.count('new') == 2, 'Ctrl+Shift+T and the plus button each made a tab (%d new)' % kinds.count('new'))
chk(any(t[0] == 'new' and t[3] == 2 for t in tt), 'the first new tab makes a group of 2')
chk(any(t[0] == 'new' and t[3] == 3 for t in tt), 'the second new tab makes a group of 3')
chk(kinds.count('switch') >= 2, 'a click on a tab and Ctrl+Tab switched (%d switches)' % kinds.count('switch'))
chk(kinds.count('close') == 2, 'the x button and Ctrl+Shift+W each closed a tab (%d closes)' % kinds.count('close'))
chk(any(t[0] == 'close' and t[3] == 3 for t in tt) and any(t[0] == 'close' and t[3] == 2 for t in tt), 'closes happen at 3 tabs, then at 2 tabs (the group survives the first)')
chk(len({t[2] for t in tt}) == 1, 'all tabs stay in one group (%s)' % sorted({t[2] for t in tt}))
wins = {t[1] for t in tt if t[0] == 'new'}
chk(len(wins) == kinds.count('new'), 'every new tab is a different window')
chk(kinds[:2] == ['new', 'switch'] and kinds[-2:] == ['close', 'close'], 'order of events: new, switch ... close, close (%s)' % ','.join(kinds))

print('== pictures ==')
names = ['t0-single', 't1-two', 't2-typed', 't3-click1', 't4-switched', 't5-plus', 't6-x', 't7-closed']
img = {n: load(n) for n in names}
chk(all(img[n] is not None for n in names), 'all %d pictures exist' % len(names))
if any(img[n] is None for n in names):
    print('  FAIL  no pictures, cannot measure the strip')
    print('== result ==')
    print('  %d ok, %d fail' % (ok, bad + 1))
    sys.exit(1)
STRIP = (30, 424, 560, 452)
DARK, GREY = (9, 9, 11), (72, 72, 75)


def tabs(n, xs):
    # which tabs look active (dark like the terminal body) / inactive (grey), probed at y=448 inside each tab
    r = []
    for x in xs:
        p = px(img[n], x, 448)
        r.append('A' if max(abs(p[i] - DARK[i]) for i in range(3)) < 12 else ('i' if max(abs(p[i] - GREY[i]) for i in range(3)) < 12 else '?'))
    return ''.join(r)


X2, X3 = (45, 200), (45, 170, 295)
chk(differs(img['t0-single'], img['t1-two'], STRIP) > 400, 'the title strip changes when the second tab opens (%d px)' % differs(img['t0-single'], img['t1-two'], STRIP))
chk(tabs('t1-two', X2) == 'iA', 'new tab is the active one (tab2) [%s]' % tabs('t1-two', X2))
chk(differs(img['t1-two'], img['t2-typed'], (26, 456, 580, 830)) > 300, 'typing shows in the new tab')
chk(tabs('t3-click1', X2) == 'Ai', 'a click on tab1 makes it active [%s]' % tabs('t3-click1', X2))
chk(differs(img['t2-typed'], img['t3-click1'], (26, 456, 580, 830)) > 300, 'the click switches the terminal content (%d px)' % differs(img['t2-typed'], img['t3-click1'], (26, 456, 580, 830)))
chk(tabs('t4-switched', X2) == 'iA', 'Ctrl+Tab goes on to tab2 [%s]' % tabs('t4-switched', X2))
chk(tabs('t5-plus', X3) == 'iiA', 'the plus button opens tab3 and it is active [%s]' % tabs('t5-plus', X3))
chk(differs(img['t4-switched'], img['t5-plus'], STRIP) > 400, 'the strip changes when the third tab opens')
t6 = tabs('t6-x', X2)
chk(sorted(t6) == ['A', 'i'], 'the x on tab3 closes it: two tabs, one active [%s]' % t6)
chk(differs(img['t5-plus'], img['t6-x'], STRIP) > 300, 'the strip changes when tab3 closes (%d px)' % differs(img['t5-plus'], img['t6-x'], STRIP))
chk(differs(img['t0-single'], img['t7-closed'], STRIP) < 200, 'back to one terminal: the strip looks like the start again (%d px)' % differs(img['t0-single'], img['t7-closed'], STRIP))
chk(differs(img['t6-x'], img['t7-closed'], STRIP) > 300, 'Ctrl+Shift+W took the strip away (%d px)' % differs(img['t6-x'], img['t7-closed'], STRIP))
print('== result ==')
print('  %d ok, %d fail' % (ok, bad))
sys.exit(1 if bad else 0)
