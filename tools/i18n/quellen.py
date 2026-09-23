#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
"""tools/i18n/quellen.py -- WO IM BAUM BILDSCHIRMTEXT STEHT.

Runde UMLAUT2. `translit.py` hat bis hierher zwei Quellen gekannt:
`locale/de/*` und `assets/apps/*.osp/INFO`. Beide waren sauber, als im
Starter trotzdem "Text schreiben und aendern" stand -- dieser Satz kam
aus dem BUENDEL, und die Beschriftungen der Programme selbst kommen aus
dem QUELLTEXT. Eine Pruefung, die nur den Katalog liest, sieht davon
nichts. Deshalb dieses Stueck.

Es liest `kernel/**/*.fi`, findet JEDE Zeichenkette, die eine deutsche
Umschrift traegt, und sagt zu jeder, WAS sie ist:

  SICHTBAR     Text, den ein Mensch liest -- Beschriftung, Ausgabe,
               Fehlermeldung. HIER gehoeren echte Umlaute hin.

  MITSCHNITT   Was ein FENSTERPROGRAMM oder der Kernel auf die serielle
               Leitung schreibt ("leiste: knopf i=0 id=5"). docs/I18N.md
               nimmt diese Zeilen ausdruecklich aus -- sie sind ein
               Messwert, kein Satz, und die Abnahme greppt nach ihnen.
               Erkannt daran, dass die Datei ein Fenster aufmacht (sie
               bindet `wlib`/`wlibc` ein) oder im Kernel liegt UND die
               Kette nirgends anders hingeht als in `say`/`kv`/`sagn`.

  MARKE        Was mit einer EINGABE verglichen wird: Unterbefehl
               ("opk zurueck"), Schalter ("--quelle"), Pfad, Dateiname,
               Schluessel. Dieselbe Ausnahme wie in docs/I18N.md
               ("Befehlsname: nein") und dieselbe wie `keys=` in den
               Buendeln -- man muss das tippen koennen, auch ohne
               Umlauttaste. Erkannt an einem Vergleich (`streq`,
               `text.equal`) oder daran, dass der Inhalt wie ein Name
               aussieht und nicht wie ein Satz.

Eine MARKE darf ASCII bleiben, aber sie darf nicht die EINZIGE Form
sein, die das Programm annimmt: wer `zurück` tippt, meint dasselbe.
Genau das prueft `translit.py --marken`.

  quellen.py            nur die Funde der Klasse SICHTBAR
  quellen.py --alle     alle drei Klassen
  quellen.py --zahlen   nur die Bilanz
"""
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
                   # RUNDE MERGE-2: `h_claim` gibt den Namen einer
                   # Zusage auf die serielle Leitung aus.
                   r'(?:say|sayn|sayu|say_line|kv|sag|sagn|sagt|kvs|kvt'
                   r'|h_claim)'
                   r'|serial\.[a-z_0-9]+'
                   r')\s*\(')


def inhalt_von(roh):
    """Der Textinhalt einer Firn-Zeichenkette, ohne die Fuellnullen."""
    s = roh.replace('\\0', '')
    s = s.replace('\\n', '\n').replace('\\t', '\t')
    s = s.replace('\\"', '"').replace('\\\\', '\\')
    return s


# RUNDE MERGE-2: EIN PFAD IST KEIN SATZ.
#
# `opk` meldet "opk: /system/schluessel.pub ist nicht 32 Oktett lang".
# Darin steckt `schluessel` -- aber als DATEINAME auf der Platte, und
# der heisst so, wie er heisst. Wer ihn umschreibt, findet die Datei
# nicht mehr. Vor der Suche nach Umschrift werden absolute Pfade
# deshalb ausgeblendet; alles andere im selben Satz wird weiter
# geprueft (`kein vertrauter Schluessel:` faellt also NACH wie vor auf,
# und ist auch gefallen).
PFAD = re.compile(r'(?<![A-Za-z0-9_])/[A-Za-z0-9_./+-]+')


def ohne_pfade(t):
    return PFAD.sub(lambda m: ' ' * len(m.group(0)), t)


def sieht_aus_wie_name(t):
    k = t.strip()
    if not k:
        return True
    if k.startswith(('/', '-', '.')):
        return True
    if ' ' not in k and (k.endswith('=') or '.' in k or '/' in k):
        return t == k          # mit Rand ist es ein Feld, kein Name
    
    if ' ' not in k and k.isupper() and len(k) > 1:
        return True
    return False


def quelldateien(wurzel):
    for dp, dns, fns in os.walk(os.path.join(wurzel, 'kernel')):
        dns[:] = [d for d in dns if not d.startswith('.')]
        for fn in sorted(fns):
            if fn.endswith(('.fi', '.s')):
                yield os.path.join(dp, fn)


def funde(wurzel):
    """-> Liste dicts fuer JEDE Zeichenkette mit deutscher Umschrift."""
    aus = []
    for pfad in sorted(quelldateien(wurzel)):
        rel = os.path.relpath(pfad, wurzel).replace(os.sep, '/')
        txt = open(pfad, encoding='utf-8').read()
        zeilen = txt.split('\n')
        fenster = ('import wlib' in txt) or ('import wlibc' in txt)
        kern = not rel.startswith('kernel/user/')
        for nr, z in enumerate(zeilen, 1):
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
            for name, breite, roh, fest in paare:
                inhalt = inhalt_von(roh)
                if not translit.finde(ohne_pfade(inhalt)):
                    continue
                kl = klasse(name, inhalt, zeilen, nr, code, fenster, kern,
                            fest)
                # `// DRAHT: <wer liest es>` am Ende der Zeile: die Kette
                # ist ein Wort eines Formats oder Protokolls (Feldname,
                # Gruss, signierter Text), das ein ANDERES Programm Oktett
                # fuer Oktett erwartet. Runde ROTABSCHNITTE 5 hat zehn
                # solche Ketten "entschriftet" und damit die Bruecke, die
                # OTA-Schluesselkette und die Papierkorb-Infodatei
                # gebrochen. Eine DRAHT-Kette ist keine Umschrift.
                draht = DRAHT.search(z) is not None
                if draht:
                    kl = 'MARKE'
                aus.append(dict(datei=rel, zeile=nr, klasse=kl, name=name,
                                draht=draht,
                                breite=breite, inhalt=inhalt, roh=roh,
                                stamm=[s for s, _ in
                                       translit.finde(inhalt)],
                                ersatz=[e for _, e in
                                        translit.finde(inhalt)]))
    return aus


DRAHT = re.compile(r'//\s*DRAHT\b')
FNKOPF = re.compile(r'^(?:pub\s+)?fn\s')


def block(zeilen, nr):
    """Der Funktionsrumpf, in dem Zeile `nr` steht -- (von, bis).

    WARUM NICHT DIE GANZE DATEI. Zwei Funktionen derselben Datei duerfen
    beide ein `var s_g` haben, und sie bedeuten dann VERSCHIEDENE Texte.
    Wer alle Zeilen der Datei durchsieht, findet die Verwendung der
    anderen und ordnet die Kette der falschen Klasse zu -- genau so ist
    "launcher: waehle datei" einmal als Bildschirmtext gezaehlt worden,
    obwohl sie nur in den Mitschnitt geht.
    """
    von = 0
    for i in range(nr - 1, -1, -1):
        if FNKOPF.match(zeilen[i]):
            von = i + 1
            break
    bis = len(zeilen)
    for i in range(nr, len(zeilen)):
        if FNKOPF.match(zeilen[i]):
            bis = i
            break
    return von, bis


def stellen(zeilen, name, ausser, fest):
    """Alle Codezeilen im selben Rumpf, in denen dieser Name steht.

    `fest` sagt, ob die Kette mit `static`/`const` am DATEIRAND steht --
    dann gilt die ganze Datei, sonst nur der Rumpf, in dem sie steht.
    """
    such = re.compile(r'(?<![A-Za-z_0-9])%s(?![A-Za-z_0-9])'
                      % re.escape(name))
    if not fest:
        von, bis = block(zeilen, ausser)
    else:
        von, bis = 0, len(zeilen)
    aus = []
    for i in range(von, bis):
        nr = i + 1
        if nr == ausser or zeilen[i].lstrip().startswith('//'):
            continue
        code = zeilen[i].split('//')[0]
        if such.search(code):
            aus.append(code)
    return aus


def klasse(name, inhalt, zeilen, nr, code, fenster, kern, fest):
    if sieht_aus_wie_name(inhalt):
        return 'MARKE'
    benutzt = stellen(zeilen, name, nr, fest) if name != '-' else [code]
    for z in benutzt:
        if VERGL.search(z):
            return 'MARKE'
    # Der NAME eines Messwerts: erstes Argument eines Paar-Ausgebers
    # (`sag(n_gross, geschrieben)` -> "grossdatei 2621440"). Das ist ein
    # Feldname im Mitschnitt und kein Satz auf dem Schirm.
    feld = False
    if name != '-':
        wieerst = re.compile(
            # RUNDE MERGE-2: `h_claim` dazu. Der Selbsttest in
            # kernel/uprog.fi (Runde HANDLE) gibt seinen ersten
            # Parameter als Namen der Zusage auf die serielle
            # Leitung aus ("  [ ok ] auftrag-laeuft") -- dasselbe
            # Muster wie `sag`/`kv`, nur mit anderem Namen.
            r'(?:sag|sagn|kv|kvs|kvt|say_line|h_claim)\s*\(\s*\(?\s*&%s\s*\['
            % re.escape(name))
        feld = any(wieerst.search(z) for z in benutzt)
    if fenster or kern or feld:
        if not benutzt:
            return 'MITSCHNITT' if (fenster or kern) else 'SICHTBAR'
        for z in benutzt:
            if not TRACE.search(z):
                return 'SICHTBAR'
        return 'MITSCHNITT'
    return 'SICHTBAR'


def marken(wurzel):
    """Nimmt jede getippte Marke AUCH die Umlautschreibung?

    Eine Marke darf ASCII bleiben -- man muss sie ohne Umlauttaste
    tippen koennen. Sie darf aber nicht die EINZIGE Form sein: die
    Hilfe zeigt seit dieser Runde `opk zurück`, und wer das abtippt,
    muss ankommen. Dieselbe Regel wie `keys=` in den Buendeln.

    Geprueft wird nur, was WIRKLICH mit einer Eingabe verglichen wird.
    Ein Pfad (`/tmp/gross`) und ein Feldname im Mitschnitt (`bloecke=`)
    werden nicht getippt und stehen deshalb nicht zur Debatte.

    -> (geprueft, [Klage, ...])
    """
    klagen = []
    n = 0
    for r in funde(wurzel):
        if r['klasse'] != 'MARKE' or r['name'] == '-' or r.get('draht'):
            continue                      # DRAHT: niemand tippt das
        pfad = os.path.join(wurzel, r['datei'])
        txt = open(pfad, encoding='utf-8').read()
        zeilen = txt.split('\n')
        fest = re.match(r'^\s*(?:static|const)\b',
                        zeilen[r['zeile'] - 1]) is not None
        benutzt = stellen(zeilen, r['name'], r['zeile'], fest)
        if not any(VERGL.search(z) for z in benutzt):
            continue                      # wird nicht getippt
        n += 1
        soll = r['inhalt']
        for stamm, ersatz in translit.finde(soll):
            soll = soll.replace(stamm, ersatz)
        # Steht die Umlautform als eigene Kette in derselben Datei?
        gefunden = None
        for nr, z in enumerate(zeilen, 1):
            if z.lstrip().startswith('//'):
                continue
            d = DEKL.search(z.split('//')[0])
            if d and inhalt_von(d.group(4)) == soll:
                gefunden = d.group(2)
                break
        if gefunden is None:
            klagen.append('%s:%d  %s = %r  -- es gibt keine Kette %r, '
                          'also nimmt das Programm die Umlautform nicht an'
                          % (r['datei'], r['zeile'], r['name'],
                             r['inhalt'], soll))
            continue
        zw = stellen(zeilen, gefunden, 0, True)
        if not any(VERGL.search(z) for z in zw):
            klagen.append('%s  %s = %r steht da, wird aber mit nichts '
                          'verglichen' % (r['datei'], gefunden, soll))
    return n, klagen


def main(argv):
    wurzel = os.environ.get('OSUM_ROOT', '.')
    alle = '--alle' in argv
    if '--streng' in argv:
        # DER MODUS FUER DIE ABNAHME: rot, sobald EINE sichtbare
        # deutsche Zeichenkette Umschrift traegt.
        f = funde(wurzel)
        s = [r for r in f if r['klasse'] == 'SICHTBAR']
        print('quellen: %d Umschriften, davon %d SICHTBAR'
              % (len(f), len(s)))
        for r in s:
            print('    UMSCHRIFT  %s:%d  %-12s %-11s %s'
                  % (r['datei'], r['zeile'], r['name'],
                     '/'.join(r['stamm']),
                     r['inhalt'].replace('\n', '\\n')[:60]))
        return 1 if s else 0
    if '--marken' in argv:
        n, klagen = marken(wurzel)
        print('marken: %d getippte Marken mit Umschrift, %d ohne '
              'Umlautform' % (n, len(klagen)))
        for k in klagen:
            print('    FEHLT  ' + k)
        return 1 if klagen else 0
    f = funde(wurzel)
    n = {'SICHTBAR': 0, 'MITSCHNITT': 0, 'MARKE': 0}
    for r in f:
        n[r['klasse']] += 1
    print('quellen: %d Umschriften in kernel/**  --  SICHTBAR=%d '
          'MITSCHNITT=%d MARKE=%d'
          % (len(f), n['SICHTBAR'], n['MITSCHNITT'], n['MARKE']))
    if '--zahlen' in argv:
        return 0
    for r in f:
        if not alle and r['klasse'] != 'SICHTBAR':
            continue
        print('  %-11s %-26s %5d  %-12s %-11s %s'
              % (r['klasse'], r['datei'], r['zeile'], r['name'],
                 '/'.join(r['stamm']),
                 r['inhalt'].replace('\n', '\\n').replace('\t', '\\t')[:60]))
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
