#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
import os, re, sys

root = sys.argv[1] if len(sys.argv) > 1 else os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', '..')
PAGE = 0x2000
ok = bad = 0
src = {}


def chk(cond, msg):
    global ok, bad
    if cond:
        ok += 1
    else:
        bad += 1
        print('  FAIL  ' + msg)


def text(f):
    if f not in src:
        src[f] = open(os.path.join(root, f), encoding='latin-1').read()
    return src[f]


def value(f, name, env):
    m = re.search(r'^const %s: u64 = ([^\n/]+)' % re.escape(name), text(f), re.M)
    if not m:
        return None
    total = 0
    for tok in m.group(1).split('+'):
        tok = tok.strip()
        if tok in env:
            total += env[tok]
        elif re.fullmatch(r'0x[0-9A-Fa-f]+|\d+', tok):
            total += int(tok, 0)
        else:
            return None
    return total


rows = []
for line in open(os.path.join(os.path.dirname(os.path.abspath(__file__)), 'slots.tsv')):
    c = line.rstrip('\n').split('\t')
    if len(c) < 3:
        continue
    c += [''] * (5 - len(c))
    rows.append(c)

items = []
for f, name, size, base, group in rows:
    v = value(f, name, {'pci.K2_SCALARS': 0x12000})
    chk(v is not None, '%s: const %s not found' % (f, name))
    if v is None:
        continue
    if base and base != "0":
        b = value(f, base, {})
        chk(b is not None, '%s: const %s not found' % (f, base))
        if b is None:
            continue
        v += b
    if v >= 0x12000:
        v -= 0x12000
    items.append((v, int(size), f, name, group))

groups = {}
spans = []
for v, size, f, name, group in items:
    chk(v + size <= PAGE, '%s %s at 0x%X+%d leaves the K2 scalar area' % (f, name, v, size))
    chk(v % 8 == 0, '%s %s at 0x%X is not word aligned' % (f, name, v))
    if group:
        g = groups.setdefault(group, (v, size, f, name))
        chk(g[0] == v and g[1] == size, 'alias group %s disagrees: %s %s=0x%X vs %s %s=0x%X' % (group, g[2], g[3], g[0], f, name, v))
        if g[2:] == (f, name):
            spans.append((v, size, f, name))
    else:
        spans.append((v, size, f, name))

spans.sort()
for i in range(len(spans) - 1):
    a, b = spans[i], spans[i + 1]
    chk(a[0] + a[1] <= b[0], 'overlap: %s %s [0x%X..0x%X) and %s %s [0x%X..0x%X)' % (a[2], a[3], a[0], a[0] + a[1], b[2], b[3], b[0], b[0] + b[1]))

for f in sorted({r[0] for r in rows}):
    listed = {r[1] for r in rows if r[0] == f}
    if f.endswith(('hw.fi', 'wg.fi', 'inet.fi', 'nvme.fi', 'virtio.fi', 'apic.fi', 'netsvc.fi')):
        for m in re.finditer(r'^const (S_[A-Z0-9_]+): u64 = (0x[0-9A-Fa-f]+)', text(f), re.M):
            chk(m.group(1) in listed, '%s: const %s is not in tools/k2slots/slots.tsv' % (f, m.group(1)))

if len(sys.argv) > 2 and sys.argv[2] == '--map':
    prev = 0
    for v, size, f, name in spans:
        if v > prev:
            print('FREE 0x%04X..0x%04X (%d)' % (prev, v, v - prev))
        print('0x%04X..0x%04X %s %s' % (v, v + size, os.path.basename(f), name))
        prev = max(prev, v + size)
    print('FREE 0x%04X..0x%04X (%d)' % (prev, PAGE, PAGE - prev))
print('== result ==')
print('  %d ok, %d fail' % (ok, bad))
sys.exit(1 if bad else 0)
