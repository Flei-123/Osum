#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
"""tools/umlaut/schriftprobe.py -- HAT DIE SCHRIFT DIE ZEICHEN, DIE WIR
SCHREIBEN?

Runde UMLAUT2. Eine Zeichenkette auf echte Umlaute umzustellen ist die
halbe Arbeit; die andere Haelfte ist, dass die AUSGELIEFERTE Schrift
diese Zeichen auch kennt. `assets/osum-sans.ttf` ist aus DejaVu
GESCHNITTEN -- 339 Zeichen, nicht die ganze Datei -- und was nicht im
Schnitt liegt, malt der Rasterer gar nicht. Auf dem Bild steht dann
nichts, und im Quelltext sieht alles richtig aus.

Also: JEDES Zeichen ueber ASCII, das irgendwo in sichtbarem Text
vorkommt, muss in der `cmap` beider Schriften stehen. Gelesen wird die
Tabelle so, wie `kernel/ttf.fi` sie liest -- Format 4 und Format 12.

Quellen des sichtbaren Textes:

    locale/de/*                 jeder Wert rechts vom "="
    assets/apps/*.osp/INFO      name= und info=
    kernel/**/*.fi              jede Zeichenkette der Klasse SICHTBAR
                                (tools/i18n/quellen.py)

  schriftprobe.py

rc=0 alles da, rc=1 ein Zeichen fehlt.
"""
import glob
import os
import re
import struct
import sys

HIER = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HIER, '..', 'i18n'))
import quellen      # noqa: E402
import translit     # noqa: E402

SCHRIFTEN = ['assets/osum-sans.ttf', 'assets/osum-mono.ttf']


def tabellen(roh):
    n = struct.unpack('>H', roh[4:6])[0]
    aus = {}
    for i in range(n):
        o = 12 + i * 16
        tag = roh[o:o + 4].decode('latin1')
        off, ln = struct.unpack('>II', roh[o + 8:o + 16])
        aus[tag] = (off, ln)
    return aus


def cmap(pfad):
    """Die Menge der Codepunkte, die diese Schrift abbildet."""
    roh = open(pfad, 'rb').read()
    t = tabellen(roh)
    if 'cmap' not in t:
        raise SystemExit('%s: keine cmap' % pfad)
    base = t['cmap'][0]
    anzahl = struct.unpack('>H', roh[base + 2:base + 4])[0]
    aus = set()
    for i in range(anzahl):
        o = base + 4 + i * 8
        off = struct.unpack('>I', roh[o + 4:o + 8])[0]
        s = base + off
        art = struct.unpack('>H', roh[s:s + 2])[0]
        if art == 4:
            segx2 = struct.unpack('>H', roh[s + 6:s + 8])[0]
            seg = segx2 // 2
            ende = s + 14
            anf = ende + segx2 + 2
            delta = anf + segx2
            rng = delta + segx2
            for k in range(seg):
                e = struct.unpack('>H', roh[ende + k * 2:ende + k * 2 + 2])[0]
                a = struct.unpack('>H', roh[anf + k * 2:anf + k * 2 + 2])[0]
                d = struct.unpack('>h', roh[delta + k * 2:delta + k * 2 + 2])[0]
                r = struct.unpack('>H', roh[rng + k * 2:rng + k * 2 + 2])[0]
                if a == 0xFFFF:
                    continue
                for c in range(a, min(e, 0xFFFE) + 1):
                    if r == 0:
                        g = (c + d) & 0xFFFF
                    else:
                        at = rng + k * 2 + r + (c - a) * 2
                        if at + 2 > len(roh):
                            continue
                        g = struct.unpack('>H', roh[at:at + 2])[0]
                        if g:
                            g = (g + d) & 0xFFFF
                    if g:
                        aus.add(c)
        elif art == 12:
            gr = struct.unpack('>I', roh[s + 12:s + 16])[0]
            for k in range(gr):
                o2 = s + 16 + k * 12
                a, e, _g = struct.unpack('>III', roh[o2:o2 + 12])
                if e - a > 0x10000:
                    continue
                for c in range(a, e + 1):
                    aus.add(c)
    return aus


def sichtbarer_text(wurzel):
    """-> Liste (herkunft, text) fuer allen Bildschirmtext des Systems."""
    aus = []
    for pfad in sorted(glob.glob(os.path.join(wurzel, 'locale/de/*'))):
        rel = os.path.relpath(pfad, wurzel)
        for nr, z in enumerate(open(pfad, encoding='utf-8').read().split('\n'),
                               1):
            if z.lstrip().startswith('#') or '=' not in z:
                continue
            aus.append(('%s:%d' % (rel, nr), z.split('=', 1)[1]))
    for d in sorted(glob.glob(os.path.join(wurzel, 'assets/apps/*.osp'))):
        p = os.path.join(d, 'INFO')
        if not os.path.exists(p):
            continue
        rel = os.path.relpath(p, wurzel)
        for nr, z in enumerate(open(p, encoding='utf-8').read().split('\n'),
                               1):
            if z.startswith(('name=', 'info=')):
                aus.append(('%s:%d' % (rel, nr), z.split('=', 1)[1]))
    for r in quellen.funde(wurzel):
        aus.append(('%s:%d' % (r['datei'], r['zeile']), r['inhalt']))
    # Und jede Zeichenkette des Quelltexts, die ein Zeichen ueber ASCII
    # traegt -- die interessiert hier unabhaengig von ihrer Klasse.
    STR = re.compile(r'"(?:\\.|[^"\\])*"')
    for dp, dns, fns in os.walk(os.path.join(wurzel, 'kernel')):
        dns[:] = [x for x in dns if not x.startswith('.')]
        for fn in sorted(fns):
            if not fn.endswith('.fi'):
                continue
            p = os.path.join(dp, fn)
            rel = os.path.relpath(p, wurzel).replace(os.sep, '/')
            for nr, z in enumerate(open(p, encoding='utf-8').read().split('\n'),
                                   1):
                if z.lstrip().startswith('//'):
                    continue
                for m in STR.finditer(z.split('//')[0]):
                    t = quellen.inhalt_von(m.group(0)[1:-1])
                    if any(ord(c) > 127 for c in t):
                        aus.append(('%s:%d' % (rel, nr), t))
    return aus


def main(argv):
    wurzel = os.environ.get('OSUM_ROOT', '.')
    decken = {}
    for s in SCHRIFTEN:
        p = os.path.join(wurzel, s)
        if not os.path.exists(p):
            print('schriftprobe: %s fehlt' % s)
            return 1
        decken[s] = cmap(p)
    text = sichtbarer_text(wurzel)
    gebraucht = {}
    for herkunft, t in text:
        for c in t:
            if ord(c) > 127:
                gebraucht.setdefault(c, herkunft)
    fehlt = []
    for c, herkunft in sorted(gebraucht.items()):
        for s in SCHRIFTEN:
            if ord(c) not in decken[s]:
                fehlt.append('%s U+%04X %r fehlt in %s (z. B. %s)'
                             % (herkunft, ord(c), c, s, herkunft))
    print('schriftprobe: %d Textstellen, %d verschiedene Zeichen ueber '
          'ASCII, %s' % (len(text), len(gebraucht),
                         ' '.join('%s=%d' % (os.path.basename(s),
                                             len(decken[s]))
                                  for s in SCHRIFTEN)))
    print('schriftprobe: benutzt werden %s'
          % ' '.join(sorted(gebraucht)))
    for z in fehlt:
        print('    FEHLT  ' + z)
    return 1 if fehlt else 0


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
