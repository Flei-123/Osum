#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
# tools/termtabs/zombie.py <serial.txt> <cycles> -- reads one tools/termtabs/zombie.sh run (W-X2: tabs leave no corpse behind)
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
fail = [l for l in ser if 'wm: tab shell started: ' in l and l.rstrip().endswith(': 0')]
chk(new == cyc, 'every Ctrl+Shift+T made a tab (%d of %d)' % (new, cyc))
chk(cls == cyc, 'every Ctrl+Shift+W closed a tab (%d of %d)' % (cls, cyc))
chk(not fail, 'no tab shell failed to start (%d failures)' % len(fail))
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
    za = sum(m.group(3) == 'zombie' for m in a)
    zb = sum(m.group(3) == 'zombie' for m in b)
    print('  ps first: %d tasks, %d corpses; ps last: %d tasks, %d corpses' % (len(a), za, len(b), zb))
    chk(zb <= za, 'no corpse left by %d tab cycles (%d before, %d after)' % (cyc, za, zb))
    chk(len(b) <= len(a) + 1, 'the task count is back at the start (%d before, %d after)' % (len(a), len(b)))
    names = lambda r: sorted(m.group(4) for m in r)
    chk(names(b).count('sh') <= names(a).count('sh') + 1 and names(b).count('term') == names(a).count('term'),
        'no extra shell or term task (sh %d -> %d, term %d -> %d)' % (names(a).count('sh'), names(b).count('sh'), names(a).count('term'), names(b).count('term')))
print('== result ==')
print('  %d ok, %d fail' % (ok, bad))
sys.exit(1 if bad else 0)
