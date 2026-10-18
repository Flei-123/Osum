#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
"""tools/serline/check.py -- count intact `SL<id>:<i>:<payload>:E` lines of one
section of a serial capture.

  check.py <capture> <section> <workers> <lines>

The section is the text between `==<section>==` and the next `==...==`.
Prints `intact=N expected=M torn=K dup=D done=0|1` (torn = expected - intact).
A line counts when the whole line is one SL record (an optional `OPEN:`
prefix is allowed: the parent leaves that line open on purpose) and the
payload is the letter and length the guest derives from <id> and <i>.
"""
import re
import sys

path, section, workers, lines = sys.argv[1], sys.argv[2], int(sys.argv[3]), int(sys.argv[4])
raw = open(path, 'rb').read().decode('latin1')
raw = ''.join(ch for ch in raw if ch in '\n\r\t' or 32 <= ord(ch) < 127)
raw = raw.replace('\r', '')
m = re.search(r'==%s==\n(.*?)(?:\n==[A-Z]+==|\Z)' % re.escape(section), raw, re.S)
body = m.group(1) if m else ''
rec = re.compile(r'^(?:OPEN:)?SL(\d+):(\d+):([a-z]+):E$')
seen = {}
for ln in body.split('\n'):
    mm = rec.match(ln)
    if not mm:
        continue
    wid, i, pay = int(mm.group(1)), int(mm.group(2)), mm.group(3)
    letter = chr(97 + (wid * 7) % 26)
    plen = 10 + (wid * 13 + i * 37) % 90
    if pay != letter * plen:
        continue
    seen[(wid, i)] = seen.get((wid, i), 0) + 1
expected = workers * lines
intact = len(seen)
dup = sum(v - 1 for v in seen.values())
done = 1 if re.search(r'serline: done w=%d l=%d bad=0' % (workers, lines), body) else 0
print('intact=%d expected=%d torn=%d dup=%d done=%d' % (intact, expected, expected - intact, dup, done))
