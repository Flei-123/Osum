#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
import re, sys

ser = open(sys.argv[1], errors='replace').read().split('\n')
cyc = int(sys.argv[2])
ok = bad = 0


def chk(cond, msg):
    global ok, bad
    if cond:
        ok += 1
        print('  OK    ' + msg)
    else:
        bad += 1
        print('  FAIL  ' + msg)


new = sum(1 for l in ser if re.search(r'tt: new win=\d+', l))
cls = sum(1 for l in ser if re.search(r'tt: close win=\d+', l))
chk(new == cyc, 'every Ctrl+Shift+T made a tab (%d of %d)' % (new, cyc))
chk(cls == cyc, 'every Ctrl+Shift+W closed a tab (%d of %d)' % (cls, cyc))
hups = [int(m.group(1)) for l in ser for m in [re.search(r'kgui: hangup tty=\d+ hit=(\d+)', l)] if m]
chk(len(hups) >= cyc, 'every closed window hung up its tty (%d of %d)' % (len(hups), cyc))
chk(len(hups) >= cyc and all(h >= 2 for h in hups[:cyc]), 'each hangup reached the shell and the foreground ping (hits %s)' % hups[:cyc])
row = re.compile(r'(\d+)\s+(\d+)\s+(ready|run|sleep|wait|zombie|new|stop|poll)\s+(\w+)')
heads = [i for i, l in enumerate(ser) if 'PID PPID STATE' in l]
chk(len(heads) >= 2, 'two ps listings (%d)' % len(heads))
if len(heads) >= 2:
    lists = []
    for h in (heads[0], heads[-1]):
        rows = []
        for l in ser[h + 1:h + 80]:
            m = row.search(l)
            if m:
                rows.append(m)
            elif rows and not l.strip().startswith(('wm: termzeile', 'osum$')):
                break
        lists.append(rows)
    a, b = lists
    names = lambda r: sorted(m.group(4) for m in r)
    print('  ps first: %d tasks; ps last: %d tasks; ping tasks last: %d' % (len(a), len(b), names(b).count('ping')))
    chk(names(b).count('ping') == 0, 'no ping task survives its closed window (%d left)' % names(b).count('ping'))
    chk(len(b) <= len(a) + 1, 'the task count is back at the start (%d before, %d after)' % (len(a), len(b)))
    za = sum(m.group(3) == 'zombie' for m in a)
    zb = sum(m.group(3) == 'zombie' for m in b)
    chk(zb <= za, 'no corpse left behind (%d before, %d after)' % (za, zb))
print('== result ==')
print('  %d ok, %d fail' % (ok, bad))
sys.exit(1 if bad else 0)
