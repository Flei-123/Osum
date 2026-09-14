#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
"""tools/codec/fixstr.py -- die Laengen der Textfelder nachrechnen.
Firn verlangt, dass [u8; N] und der Text GENAU gleich lang sind, und
zaehlt in Oktetten (ein Umlaut ist zwei). Von Hand gezaehlt ist das
eine Fehlerquelle ohne Erkenntniswert, also rechnet es hier jemand aus.
    python3 tools/codec/fixstr.py DATEI...
"""
import re, sys
pat=re.compile(r'(static mut (\w+): \[u8; )(\d+)(\] =\s*\n?\s*)"((?:[^"\\]|\\.)*)"')
for p in sys.argv[1:]:
    s=open(p,encoding='utf-8').read()
    def fix(m):
        n=len(m.group(5).replace('\\0','\x00').encode('utf-8'))
        return m.group(1)+str(n)+m.group(4)+'"'+m.group(5)+'"'
    s2,c=pat.subn(fix,s)
    if s2!=s:
        open(p,'w',encoding='utf-8').write(s2)
    print("%s: %d Textfelder geprueft" % (p, c))
