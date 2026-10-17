#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
# tools/termsel/check.py <outdir> -- reads serial.txt + the .ppm pictures of one tools/termsel run (r1014)
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


def cell_bright(img, geo, c, r):
    # share of bright pixels (> 150) in the cell
    if img is None or geo is None:
        return -1.0
    w, h, b = img
    gx, gy, cw, ch = geo
    n = hit = 0
    for dy in range(0, ch, 2):
        for dx in range(0, cw, 2):
            x = gx + c * cw + dx
            y = gy + r * ch + dy
            if 0 <= x < w and 0 <= y < h:
                o = (y * w + x) * 3
                n += 1
                if b[o] > 150 and b[o + 1] > 150:
                    hit += 1
    return hit / n if n else -1.0


# ---- parse the dumps: geo, rows, tcur
geo = None
blocks = []   # (geo, {row: text}, tcur dict)
rows = {}
for ln in ser:
    m = re.search(r'wm: termgeo cx=(\d+) cy=(\d+) cw=(\d+) ch=(\d+)', ln)
    if m:
        geo = tuple(int(v) for v in m.groups())
        rows = {}
        continue
    m = re.search(r'wm: termzeile (\d+) \[(.*)\]', ln)
    if m:
        rows[int(m[1])] = m[2]
        continue
    m = re.search(r'wm: tcur win=\d+ on=(\d) toggle=(\d+) hide=(\d) sel=(\d) copies=(\d+) pastes=(\d+)', ln)
    if m:
        blocks.append((geo, dict(rows), dict(zip(('on', 'toggle', 'hide', 'sel', 'copies', 'pastes'), (int(v) for v in m.groups())))))
tc = [b[2] for b in blocks]
copies = [ln for ln in ser if 'wm: tcopy n=' in ln]
pastes = [ln for ln in ser if 'wm: tpaste t=' in ln]

print('== blink ==')
chk(len(tc) >= 6, 'at least 6 cursor witness lines (%d)' % len(tc))
tg = [t['toggle'] for t in tc]
chk(len(tg) >= 2 and all(a <= b for a, b in zip(tg, tg[1:])) and tg[-1] - tg[0] >= 8,
    'the blink timer runs: toggles %s' % (tg[:1] + tg[-1:]))
chk({t['on'] for t in tc} == {0, 1}, 'the cursor is on in some dumps and off in others')
chk(all(t['hide'] == 0 for t in tc), 'the cursor is not hidden')
# the pictures: the cursor cell (prompt row, column 6) is bright in some and dark in others
pgeo = None
prow = None
for g, rws, t in blocks:
    # the first dump that shows PASTEME: its last bare prompt row is where the cursor stands
    if t['copies'] == 0 and g and any(tx.strip() == 'PASTEME' for tx in rws.values()):
        for r, tx in rws.items():
            if tx.strip() == 'osum$':
                pgeo, prow = g, r
        if pgeo is not None:
            break
if pgeo is None:
    chk(False, 'prompt row found in the cells')
else:
    br = [cell_bright(load('b%02d' % i), pgeo, 6, prow) for i in range(10)]
    on_n = sum(1 for v in br if v > 0.6)
    off_n = sum(1 for v in br if 0 <= v < 0.1)
    chk(on_n >= 1 and off_n >= 1, 'pictures show the cursor block in %d and no cursor in %d of 10 (row %d)' % (on_n, off_n, prow))

print('== selection ==')
sel = [t for g, r, t in blocks if t['sel'] == 1]
chk(len(sel) >= 1, 'a dump shows a standing selection (sel=1)')
res = None
for g, rws, t in blocks:
    for r, tx in rws.items():
        if tx.strip() == 'PASTEME' and res is None:
            res = (g, r)
if res is None:
    chk(False, 'row PASTEME found')
else:
    g, r = res
    a = [cell_bright(load('s0-before'), g, c, r) for c in range(0, 7)]
    b = [cell_bright(load('s1-selected'), g, c, r) for c in range(0, 7)]
    chk(max(a) < 0.5, 'before the drag the row is dark text on dark ground (max %.2f)' % max(a))
    chk(min(b) > 0.5, 'after the drag all 7 cells are reversed (min %.2f)' % min(b))

print('== copy ==')
chk(any('[PASTEME]' in c and 'n=7' in c for c in copies), 'Ctrl+Shift+C copied exactly PASTEME: %s' % (copies[:1],))
chk(any(t['copies'] >= 1 for t in tc), 'the copy counter stands in the dump')

print('== paste ==')
chk(len(pastes) >= 2, 'two pastes were asked for (Ctrl+Shift+V, right click): %d' % len(pastes))
chk(any(tx.strip() == 'osum$ PASTEME' for g, rws, t in blocks for tx in rws.values()),
    'PASTEME stands behind the prompt (typed into the shell)')

print('== Ctrl+C with a selection ==')
chk(len(copies) >= 2, 'Ctrl+C with a selection copied (copies seen: %d)' % len(copies))
chk(tc and tc[-1]['sel'] == 0, 'the selection is gone after it')

print('== Z9: paste redraw + Ctrl+Shift+C without selection ==')
kicks = [ln for ln in ser if 'wm: tpaste kick=' in ln]
chk(len(kicks) >= 2, 'every paste kicked the compositor (wm: tpaste kick=, Ctrl+Shift+V + right click): %d' % len(kicks))
chk(len(copies) == 2, 'Ctrl+Shift+C without a selection copied nothing (copies seen: %d)' % len(copies))
alive = [tx for g, rws, t in blocks[-2:] for tx in rws.values() if tx.strip() == 'ALIVE']
chk(len(alive) >= 1, 'the shell still answers after Ctrl+Shift+C without a selection (echo ALIVE printed ALIVE)')
chk(not any('sh: bye' in tx for g, rws, t in blocks for tx in rws.values()), 'no "sh: bye" in any dump (the shell never exited)')

print('  INFO  %s' % ([ln for ln in ser if 'launcher: uid=' in ln][:2],))

print('TERMSEL: %d ok, %d fail' % (ok, bad))
sys.exit(1 if bad else 0)
