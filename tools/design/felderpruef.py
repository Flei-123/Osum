#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
"""tools/design/felderpruef.py -- FELDGROESSE GEGEN IHRE KONSTANTEN.

DIE FEHLERKLASSE, DIE DIESES SKRIPT SUCHT, HAT MERGE-9 UND MERGE-10 JE
EINMAL GETROFFEN und ist von aussen unsichtbar:

    const MAXWN: u64 = 5
    const N_FIELDS: u64 = 14
    static mut wn: [u64; 56] = ...   // MAXWN * N_FIELDS   <-- 56 != 70

Zwei Runden heben je eine der beiden Konstanten, die handgerechnete
Feldgroesse daneben bleibt stehen, und das fuenfte Fenster schreibt
ueber das Feldende -- in die Variable, die zufaellig dahinter liegt.
Im laufenden System faellt das nicht auf; es faellt dem K16-Pruefstand
auf, weil `firnc1` beim Binden umkippt, und das erst Tage spaeter.

Gelesen wird der KOMMENTAR hinter der Feldzeile: steht dort ein Produkt
aus Konstanten derselben Datei, muss es die Feldgroesse ergeben.

    python3 tools/design/felderpruef.py [wurzel]

Rueckgabe 0 = alle Felder stimmen, 1 = mindestens eine Abweichung.
"""
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
        # static mut NAME: [T; N] = ...   // A * B [* C ...]
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
