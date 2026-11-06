#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
import re
import sys

path, section = sys.argv[1], sys.argv[2]
raw = open(path, 'rb').read().decode('latin1')
raw = ''.join(ch for ch in raw if ch in '\n\r\t' or 32 <= ord(ch) < 127)
raw = raw.replace('\r', '')
m = re.search(r'==%s==\n(.*?)(?:\n==[A-Z]+==|\Z)' % re.escape(section), raw, re.S)
body = m.group(1) if m else ''
whole = re.compile(r'^KT:(\d+):k{12}:E$')
intact = 0
torn = 0
for ln in body.split('\n'):
    if whole.match(ln):
        intact += 1
    elif 'KT:' in ln or 'kkkk' in ln:
        torn += 1
sl = len(re.findall(r'^SL\d+:\d+:[a-z]+:E$', body, re.M))
done = 1 if re.search(r'serline: done w=1 l=\d+ bad=0', body) else 0
print('kt_intact=%d kt_torn=%d sl=%d done=%d' % (intact, torn, sl, done))
