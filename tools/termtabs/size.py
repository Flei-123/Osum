#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
# tools/termtabs/size.py <outdir> -- reads one tools/termtabs/size.sh run (W-X2: every tab of a group follows a size change)
import os, re, sys

out = sys.argv[1]
ser = open(os.path.join(out, 'serial.txt'), errors='replace').read().split('\n')
ok = bad = 0


def chk(cond, msg):
    global ok, bad
    if cond:
        ok += 1
        print('  OK    ' + msg)
    else:
        bad += 1
        print('  FAIL  ' + msg)


ev = []  # ('tt', kind, win) / ('winch', win, cols, rows) in serial order
for l in ser:
    m = re.search(r'tt: (new|switch|close) win=(\d+) grp=(\d+) tabs=(\d+)', l)
    if m:
        ev.append(('tt', m[1], int(m[2])))
    # (a serial line can be glued to the output of another task: `rows=` may be cut off, so only the columns are compared)
    m = re.search(r'kgui: winch win=(\d+) .*cols=(\d+)', l)
    if m:
        ev.append(('winch', int(m[1]), int(m[2]), 0))
news = [e for e in ev if e[0] == 'tt' and e[1] == 'new']
sws = [e for e in ev if e[0] == 'tt' and e[1] == 'switch']
chk(len(news) == 1 and len(sws) == 2, 'one new tab, two switches (%d new, %d switch)' % (len(news), len(sws)))
if len(news) != 1 or len(sws) != 2:
    print('== result ==')
    print('  %d ok, %d fail' % (ok, bad + 1))
    sys.exit(1)
b = news[0][2]            # the second tab
a = sws[0][2]             # the first tab (switched to first)
def after(idx, win):
    """first winch of `win` after event index idx"""
    for e in ev[idx + 1:]:
        if e[0] == 'winch' and e[1] == win:
            return e
    return None
i_new = ev.index(news[0])
i_s1 = ev.index(sws[0])
i_s2 = ev.index(sws[1])
# winch of the shown tab when it was maximised (between new and the first switch): biggest grid there
big = [e for e in ev[i_new:i_s1] if e[0] == 'winch' and e[1] == b]
chk(len(big) >= 1, 'maximising tab2 woke its shell (SIGWINCH, %d)' % len(big))
bigg = (big[-1][2], big[-1][3]) if big else None
wa = after(i_s1, a)
chk(wa is not None and bigg is not None and (wa[2], wa[3]) == bigg, 'the other tab got the maximised grid when it came forward (%s vs %s)' % (wa and (wa[2], wa[3]), bigg))
# restore: winch of tab1 (shown) between first and second switch gives small grid; then tab2 comes back with the same
small = [e for e in ev[i_s1:i_s2] if e[0] == 'winch' and e[1] == a]
chk(len(small) >= 2, 'restoring tab1 woke its shell again (%d winch of tab1)' % len(small))
sg = (small[-1][2], small[-1][3]) if small else None
chk(sg is not None and bigg is not None and sg[0] < bigg[0], 'the restored grid is smaller than the maximised (%s < %s columns)' % (sg[0] if sg else None, bigg[0] if bigg else None))
wb = after(i_s2, b)
chk(wb is not None and sg is not None and (wb[2], wb[3]) == sg, 'tab2 came back with the restored grid (%s vs %s)' % (wb and (wb[2], wb[3]), sg))
print('== result ==')
print('  %d ok, %d fail' % (ok, bad))
sys.exit(1 if bad else 0)
