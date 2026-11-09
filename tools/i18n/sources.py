#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import translit  # noqa: E402

DEKL = re.compile(
    r'^\s*(static\s+mut\s+|static\s+|var\s+|let\s+|const\s+)'
    r'([A-Za-z_][A-Za-z_0-9]*)'
    r'\s*:\s*\[u8;\s*(\d+)\s*\]\s*=\s*"((?:\\.|[^"\\])*)"')
STR = re.compile(r'"(?:\\.|[^"\\])*"')
VERGL = re.compile(r'(?:streq|text\.equal|str_eq|gleich)\s*\(')
TRACE = re.compile(r'(?:^|[^A-Za-z_0-9.])(?:'
                   r'(?:ulib\.)?'
                   r'(?:say|sayn|sayu|say_line|kv|sag|sagn|sagt|kvs|kvt'
                   r'|h_claim)'
                   r'|serial\.[a-z_0-9]+'
                   r')\s*\(')


def inhalt_von(roh):
    s = roh.replace('\\0', '')
    s = s.replace('\\n', '\n').replace('\\t', '\t')
    s = s.replace('\\"', '"').replace('\\\\', '\\')
    return s


PATH = re.compile(r'(?<![A-Za-z0-9_])/[A-Za-z0-9_./+-]+')


FLAGGE = re.compile(r'(?<![A-Za-z0-9_-])--[a-z][a-z0-9-]*')


def without_pfade(t):
    t = PATH.sub(lambda m: ' ' * len(m.group(0)), t)
    return FLAGGE.sub(lambda m: ' ' * len(m.group(0)), t)


def sieht_aus_wie_name(t):
    k = t.strip()
    if not k:
        return True
    if k.startswith(('/', '-', '.')):
        return True
    if ' ' not in k and (k.endswith('=') or '.' in k or '/' in k):
        return t == k
    
    if ' ' not in k and k.isupper() and len(k) > 1:
        return True
    return False


def quelldateien(root):
    for dp, dns, fns in os.walk(os.path.join(root, 'kernel')):
        dns[:] = [d for d in dns if not d.startswith('.')]
        for fn in sorted(fns):
            if fn.endswith(('.fi', '.s')):
                yield os.path.join(dp, fn)


def funde(root):
    aus = []
    for path_2 in sorted(quelldateien(root)):
        rel = os.path.relpath(path_2, root).replace(os.sep, '/')
        txt = open(path_2, encoding='utf-8').read()
        rows = txt.split('\n')
        window = ('import fuiapp.hostui' in txt) or ('import uitheme' in txt)
        kern = not rel.startswith('kernel/user/')
        for nr, z in enumerate(rows, 1):
            if z.lstrip().startswith('//'):
                continue
            code = z.split('//')[0]
            d = DEKL.search(code)
            paare = []
            if d:
                fest = d.group(1).lstrip().startswith(('static', 'const'))
                paare.append((d.group(2), int(d.group(3)), d.group(4), fest))
            else:
                for m in STR.finditer(code):
                    paare.append(('-', 0, m.group(0)[1:-1], False))
            for name, width_2, roh, fest in paare:
                inhalt = inhalt_von(roh)
                if not translit.finde(without_pfade(inhalt)):
                    continue
                kl = klasse(name, inhalt, rows, nr, code, window, kern,
                            fest)
                wire = WIRE.search(z) is not None
                if wire:
                    kl = 'MARKE'
                aus.append(dict(file=rel, line=nr, klasse=kl, name=name,
                                wire=wire,
                                width_2=width_2, inhalt=inhalt, roh=roh,
                                stamm=[s for s, _ in
                                       translit.finde(inhalt)],
                                ersatz=[e for _, e in
                                        translit.finde(inhalt)]))
    return aus


WIRE = re.compile(r'//\s*DRAHT\b')
FNKOPF = re.compile(r'^(?:pub\s+)?fn\s')


def block(rows, nr):
    von = 0
    for i in range(nr - 1, -1, -1):
        if FNKOPF.match(rows[i]):
            von = i + 1
            break
    bis = len(rows)
    for i in range(nr, len(rows)):
        if FNKOPF.match(rows[i]):
            bis = i
            break
    return von, bis


def ask(rows, name, ausser, fest):
    such = re.compile(r'(?<![A-Za-z_0-9])%s(?![A-Za-z_0-9])'
                      % re.escape(name))
    if not fest:
        von, bis = block(rows, ausser)
    else:
        von, bis = 0, len(rows)
    aus = []
    for i in range(von, bis):
        nr = i + 1
        if nr == ausser or rows[i].lstrip().startswith('//'):
            continue
        code = rows[i].split('//')[0]
        if such.search(code):
            aus.append(code)
    return aus


def klasse(name, inhalt, rows, nr, code, window, kern, fest):
    if sieht_aus_wie_name(inhalt):
        return 'MARKE'
    benutzt = ask(rows, name, nr, fest) if name != '-' else [code]
    for z in benutzt:
        if VERGL.search(z):
            return 'MARKE'
    field = False
    if name != '-':
        wieerst = re.compile(
            r'(?:sag|sagn|kv|kvs|kvt|say_line|h_claim|emit|say|say_kt|say_kv)\s*\(\s*\(?\s*&%s\s*\['
            % re.escape(name))
        field = any(wieerst.search(z) for z in benutzt)
    if window or kern or field:
        if not benutzt:
            return 'MITSCHNITT' if (window or kern) else 'SICHTBAR'
        for z in benutzt:
            if not TRACE.search(z):
                return 'SICHTBAR'
        return 'MITSCHNITT'
    return 'SICHTBAR'


def marken(root):
    klagen = []
    n = 0
    for r in funde(root):
        if r['klasse'] != 'MARKE' or r['name'] == '-' or r.get('draht'):
            continue
        path_2 = os.path.join(root, r['file'])
        txt = open(path_2, encoding='utf-8').read()
        rows = txt.split('\n')
        fest = re.match(r'^\s*(?:static|const)\b',
                        rows[r['line'] - 1]) is not None
        benutzt = ask(rows, r['name'], r['line'], fest)
        if not any(VERGL.search(z) for z in benutzt):
            continue
        n += 1
        soll = r['inhalt']
        for stamm, ersatz in translit.finde(soll):
            soll = soll.replace(stamm, ersatz)
        gefunden = None
        for nr, z in enumerate(rows, 1):
            if z.lstrip().startswith('//'):
                continue
            d = DEKL.search(z.split('//')[0])
            if d and inhalt_von(d.group(4)) == soll:
                gefunden = d.group(2)
                break
        if gefunden is None:
            klagen.append('%s:%d  %s = %r  -- es gibt keine Kette %r, '
                          'also nimmt das Programm die Umlautform nicht an'
                          % (r['file'], r['line'], r['name'],
                             r['inhalt'], soll))
            continue
        zw = ask(rows, gefunden, 0, True)
        if not any(VERGL.search(z) for z in zw):
            klagen.append('%s  %s = %r steht da, wird aber mit nichts '
                          'verglichen' % (r['file'], gefunden, soll))
    return n, klagen


def main(argv):
    root = os.environ.get('OSUM_ROOT', '.')
    everything = '--everything' in argv
    if '--streng' in argv:
        f = funde(root)
        s = [r for r in f if r['klasse'] == 'SICHTBAR']
        print('quellen: %d Umschriften, davon %d SICHTBAR'
              % (len(f), len(s)))
        for r in s:
            print('    UMSCHRIFT  %s:%d  %-12s %-11s %s'
                  % (r['file'], r['line'], r['name'],
                     '/'.join(r['stamm']),
                     r['inhalt'].replace('\n', '\\n')[:60]))
        return 1 if s else 0
    if '--marken' in argv:
        n, klagen = marken(root)
        print('marks: %d typed marks with transliteration, %d without '
              'Umlautform' % (n, len(klagen)))
        for k in klagen:
            print('    FEHLT  ' + k)
        return 1 if klagen else 0
    f = funde(root)
    n = {'SICHTBAR': 0, 'MITSCHNITT': 0, 'MARKE': 0}
    for r in f:
        n[r['klasse']] += 1
    print('quellen: %d Umschriften in kernel/**  --  SICHTBAR=%d '
          'MITSCHNITT=%d MARKE=%d'
          % (len(f), n['SICHTBAR'], n['MITSCHNITT'], n['MARKE']))
    if '--numbers' in argv:
        return 0
    for r in f:
        if not everything and r['klasse'] != 'SICHTBAR':
            continue
        print('  %-11s %-26s %5d  %-12s %-11s %s'
              % (r['klasse'], r['file'], r['line'], r['name'],
                 '/'.join(r['stamm']),
                 r['inhalt'].replace('\n', '\\n').replace('\t', '\\t')[:60]))
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
