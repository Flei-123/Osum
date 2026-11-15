#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
import os, re, sys

out = sys.argv[1]
mode = sys.argv[2] if len(sys.argv) > 2 else 'new'
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
    return (int(m[1]), int(m[2]), d[m.end():]) if m else None


def lit(img, x0, y0, x1, y1):
    if img is None:
        return -1
    w, h, b = img
    n = 0
    for y in range(y0, y1):
        for x in range(x0, x1):
            o = (y * w + x) * 3
            if b[o] + b[o + 1] + b[o + 2] > 150:
                n += 1
    return n


def diff(a, b, box):
    if a is None or b is None:
        return -1
    w, h, pa = a
    pb = b[2]
    n = 0
    for y in range(box[1], box[3]):
        for x in range(box[0], box[2]):
            o = (y * w + x) * 3
            if abs(pa[o] - pb[o]) + abs(pa[o + 1] - pb[o + 1]) + abs(pa[o + 2] - pb[o + 2]) > 60:
                n += 1
    return n


def last_fen(wins_from):
    rows = {}
    for ln in ser[wins_from:]:
        m = re.search(r'wm: fen i=\d+ id=(\d+) x=(-?\d+) y=(-?\d+) w=(\d+) h=(\d+) lay=(\d+) fl=(\d+) .* tf=0x([0-9a-f]+)', ln)
        if m:
            rows[int(m[1])] = (int(m[2]), int(m[3]), int(m[4]), int(m[5]), int(m[6]), m[8])
    return rows


starts = [i for i, ln in enumerate(ser) if 'launcher: start /apps/terminal.osp/start' in ln]
fok = [(i, int(re.search(r'id=(\d+)', ln)[1])) for i, ln in enumerate(ser) if ln.startswith('wm: fokus id=')]
print('== witnesses ==')
chk(len(starts) == 2, 'two terminal starts from the search (%d)' % len(starts))
if len(starts) == 2:
    for n, s in enumerate(starts):
        after = [f for f in fok if f[0] > s]
        before_next = [f for f in after if n == 1 or f[0] < starts[1]]
        newest = max([f[1] for f in fok if f[0] > s] or [0])
        chk(bool(before_next) and before_next[-1][1] == newest and newest > 24,
            'start %d: the last focus change before the next action went to the NEW window (id %d)' % (n + 1, before_next[-1][1] if before_next else 0))
    third = max([f[1] for f in fok if f[0] > starts[1]] or [0])
    rows = last_fen(starts[1])
    fl_rows = {k: v for k, v in rows.items() if v[4] == 1}
    top_id = third
    chk(top_id in fl_rows, 'the third terminal is a normal window in the wm list (id %d)' % top_id)
    if top_id in fl_rows:
        active = fl_rows[top_id][5]
        others = [v[5] for k, v in fl_rows.items() if k != top_id]
        chk(active == 'fafafa', 'the new window has the ACTIVE title colour (%s)' % active)
        chk(all(c == 'd4d4d8' for c in others), 'every older terminal has the INACTIVE title colour (%s)' % ','.join(others))
    chk(sum(1 for ln in ser if re.match(r'key: [HI]$', ln)) >= 2, 'keys H and I were delivered')
    btn = [ln for ln in ser[starts[1]:] if ln.startswith('taskbar: btn i=') and 'focus=1' in ln]
    chk(bool(btn) and ('id=%d ' % top_id) in btn[-1], 'the task bar marks the NEW window active (%s)' % (btn[-1].split(' t=')[0] if btn else 'no button line'))

s2, s3 = load('s2-third'), load('s3-control')
nx = None
if len(starts) == 2:
    rows = last_fen(starts[1])
    wins = sorted((k, v) for k, v in rows.items() if v[4] == 1)
    if wins:
        k, v = wins[-1]
        nx = v
if nx:
    x, y, w, h = nx[0], nx[1], nx[2], nx[3]
    typed = lit(s2, x + 10, y + 100, x + w - 10, y + 140)
    chk(typed > 120, 'the typed text appears in the new window (%d lit px)' % typed)
    ctrl = lit(s3, x + 10, y + 100, x + w - 10, y + 140)
    chk(diff(s2, s3, (x + 140, y + 70, x + 150, y + 130)) >= 0, 'control picture present')
    chk(any('wm: fokus id=' in ln for ln in ser[starts[1] + 1:]) and fok[-1][1] != top_id,
        'CONTROL: clicking the first terminal moves the focus away from the new window (id %d)' % fok[-1][1])
    rows3 = last_fen(len(ser) - 400)
    chk(rows3.get(top_id, (0, 0, 0, 0, 0, ''))[5] == 'd4d4d8', 'CONTROL: the new window reads inactive after the click (title colour measures focus)')

print('== menu over a repainting window ==')
m0, m1, m2, m3 = load('m0-taskmgr'), load('m1-open'), load('m2-later'), load('m3-closed')
menu = (5, 300, 172, 420)
chk(lit(m1, *menu) > 1500, 'the menu is drawn over the task manager (%d lit px)' % lit(m1, *menu))
ghost_before = lit(m0, 0, 0, 20, 125) + lit(m0, 0, 0, 170, 16)
ghost = lit(m1, 0, 0, 20, 125) + lit(m1, 0, 0, 170, 16)
chk(ghost <= ghost_before + 300, 'no stale menu picture at the top left while the menu is open (%d lit px, before %d)' % (ghost, ghost_before))
d = diff(m1, m2, menu)
chk(0 <= d <= 300, 'the menu survives 6 s of task manager repaints (%d px differ)' % d)
chk(lit(m3, *menu) < lit(m1, *menu) // 3, 'Esc closes the menu (%d lit px left)' % lit(m3, *menu))
chk(not any('launcher: start refused' in ln for ln in ser), 'no refused start')
print('launchfocus: %d passed, %d failed' % (ok, bad))
sys.exit(1 if bad else 0)
