#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
"""tools/cursor/gen_tables.py -- writes the outline tables of tools/wm/zeiger2.py
into kernel/gfx/cursor.fi (the .fi file itself carries the hand-kept
rasteriser; only the table lines and their sizes are generated).
  python3 tools/cursor/gen_tables.py          # patch in place
  python3 tools/cursor/gen_tables.py --check  # exit 1 if the file is stale"""
import os, re, sys
here = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(here, "..", "wm"))
import zeiger2
kopf, daten = zeiger2.tafel()
kb = []
for (off, n, hx, hy) in kopf:
    assert off % 2 == 0 and off // 2 < 256 and n < 256
    kb += [off // 2, n, hx, hy]
assert all(0 <= b <= 255 for b in daten)
nf, nk, nd = len(zeiger2.FORMEN), len(kb), len(daten)
path = os.path.normpath(os.path.join(here, "..", "..", "kernel", "gfx", "cursor.fi"))
s = open(path, encoding="utf-8").read()
o = s
def sub(pat, rep, cnt=1):
    global s
    s, n = re.subn(pat, rep, s, count=cnt)
    assert n >= 1, pat
esc = lambda b: "".join("\\x%02x" % x for x in b)
sub(r'const FORMEN: u64 = \d+', 'const FORMEN: u64 = %d' % nf)
sub(r'static mut kopf: \[u8; \d+\] = \[0 as u8; \d+\]', 'static mut kopf: [u8; %d] = [0 as u8; %d]' % (nk, nk))
sub(r'static mut punkte: \[u8; \d+\] = \[0 as u8; \d+\]', 'static mut punkte: [u8; %d] = [0 as u8; %d]' % (nd, nd))
sub(r'var tk: \[u8; \d+\] = b"[^"]*"', lambda m: 'var tk: [u8; %d] = b"%s"' % (nk, esc(kb)))
sub(r'var tp: \[u8; \d+\] = b"[^"]*"', lambda m: 'var tp: [u8; %d] = b"%s"' % (nd, esc(daten)))
sub(r'while i < \d+ \{\n        kopf', 'while i < %d {\n        kopf' % nk)
sub(r'while i < \d+ \{\n        punkte', 'while i < %d {\n        punkte' % nd)
sub(r'static mut kcache: \[u8; \d+\] = \[0 as u8; \d+\]', 'static mut kcache: [u8; %d] = [0 as u8; %d]' % (nf * 6912, nf * 6912))
sub(r'static mut kc_gr: \[u64; \d+\] = \[0 as u64; \d+\]', 'static mut kc_gr: [u64; %d] = [0 as u64; %d]' % (nf, nf))
if "F_NO:" not in s:
    sub(r'(const F_WARTEN: u64 = 8\n)', r'\1const F_NO: u64 = 9       // forbidden: ring with a slash\n')
    sub(r'F_CROSS, F_WARTEN,', 'F_CROSS, F_WARTEN, F_NO,')
if "--check" in sys.argv:
    sys.exit(0 if s == o else 1)
open(path, "w", encoding="utf-8").write(s)
print("cursor.fi: %d shapes, %d head bytes, %d point bytes" % (nf, nk, nd))
