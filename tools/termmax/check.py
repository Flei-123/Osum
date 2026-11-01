#!/usr/bin/env python3
import re, sys

ser = open(sys.argv[1], 'rb').read().decode('latin1').split('\n')
ok = bad = 0


def chk(cond, msg):
    global ok, bad
    if cond:
        ok += 1
        print('  OK    ' + msg)
    else:
        bad += 1
        print('  FAIL  ' + msg)


rows = [m[1].rstrip() for m in (re.search(r'wm: (?:tw\d+|termzeile) \d+ \[(.*)\]', l) for l in ser) if m]
chk(len(rows) > 0, 'terminal contents dumped to the serial line (%d rows)' % len(rows))
bye = [r for r in rows if 'sh: bye' in r]
chk(not bye, 'no terminal row says `sh: bye` (%d)' % len(bye))
names = ['start', 'maximise button', 'restore button', 'title double click (maximise)', 'title double click (restore)', 'right edge drag', 'title drag to the left edge']
for n, what in enumerate(names):
    word = 'M%d' % n
    chk(any(r.strip() == word for r in rows), 'echo %s answered after %s' % (word, what))
cols = [int(m[1]) for m in (re.search(r'kgui: winch win=\d+ .*cols=(\d+)', l) for l in ser) if m]
print('  INFO  grid columns after each size change: %s' % cols)
chk(len(cols) >= 5, 'the shell was told about every size change (%d SIGWINCH rounds)' % len(cols))
if len(cols) >= 5:
    small = cols[1]
    chk(cols[0] > 150 and cols[0] > small * 2, 'maximised grid is wide (%d columns vs %d)' % (cols[0], small))
    chk(cols[2] == cols[0] and cols[3] == small, 'double click maximises and restores the same grid (%d, %d)' % (cols[2], cols[3]))
    chk(len(cols) >= 5 and cols[4] > small + 10, 'edge drag widens the grid (%d > %d)' % (cols[4], small))
shells = [l for l in ser if re.search(r'sh: ready', l)]
print('  INFO  `sh: ready` lines on the serial line: %d' % len(shells))
print('== result ==')
print('  %d ok, %d fail' % (ok, bad))
sys.exit(1 if bad else 0)
