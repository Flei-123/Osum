#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
# tools/termtabs/alive.py <serial.txt> -- reads one tools/termtabs/alive.sh run (r1088: the shell that stays after a tab close still works)
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


kinds = [m[1] for m in (re.search(r'tt: (new|switch|close) win=', l) for l in ser) if m]
chk(kinds.count("new") == 4 and kinds.count("close") == 4, 'four tabs made, four closed (%s)' % ','.join(kinds))
# every terminal row the kernel dumped: `wm: tw<row> [text]` (all windows) and `wm: termzeile [text]` (the first one)
rows = [m[1].rstrip() for m in (re.search(r'wm: (?:tw\d+|termzeile) \d+ \[(.*)\]', l) for l in ser) if m]
chk(len(rows) > 0, 'the terminal contents were dumped to the serial line (%d rows)' % len(rows))
for n in range(11):
    word = 'OK%d' % n
    # the answer is a row that is exactly the word (the typed command row reads `... echo OKn`)
    hit = any(r.strip() == word for r in rows)
    if n in (0, 4, 6, 10):
        chk(hit, 'echo %s was answered' % word)
    else:
        print('  INFO  echo %s %s (its tab may close before the next serial dump)' % (word, 'answered' if hit else 'not seen'))
bye = [r for r in rows if 'sh: bye' in r]
chk(not bye, 'no terminal says `sh: bye` (%d rows)' % len(bye))
print('== result ==')
print('  %d ok, %d fail' % (ok, bad))
sys.exit(1 if bad else 0)
