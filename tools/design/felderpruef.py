#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
import re, sys, os, glob

def consts(txt):
    return {m.group(1): int(m.group(2)) for m in
            re.finditer(r'^const\s+([A-Za-z_]\w*)\s*:\s*u64\s*=\s*(\d+)', txt, re.M)}

def main(root='.'):
    os.chdir(root)
    bad = checked = 0
    files = glob.glob('kernel/**/*.fi', recursive=True) + \
            glob.glob('lib/**/*.fi', recursive=True)
    for p in sorted(files):
        try:
            txt = open(p, encoding='utf-8', errors='surrogateescape').read()
        except OSError:
            continue
        C = consts(txt)
        pat = re.compile(r'^static mut (\w+)\s*:\s*\[[^;]+;\s*(\d+)\s*\]'
                         r'[^\n]*?//\s*([A-Za-z_]\w*(?:\s*\*\s*[A-Za-z0-9_]+)+)', re.M)
        for m in pat.finditer(txt):
            name, size, expr = m.group(1), int(m.group(2)), m.group(3)
            teile = [t.strip() for t in expr.split('*')]
            want = 1
            ok = True
            for t in teile:
                if t.isdigit():
                    want *= int(t)
                elif t in C:
                    want *= C[t]
                else:
                    ok = False
                    break
            if not ok:
                continue
            checked += 1
            if want != size:
                bad += 1
                print(f"MISMATCH {p}: {name}[{size}] -- {expr} = {want}")
    print(f"-- {checked} Felder geprueft, {bad} Abweichungen")
    return 1 if bad else 0

if __name__ == '__main__':
    sys.exit(main(sys.argv[1] if len(sys.argv) > 1 else '.'))
