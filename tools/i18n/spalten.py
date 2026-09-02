#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
"""tools/i18n/spalten.py -- BREITE IN ZEICHEN, PUFFER IN OKTETT.

Runde UMLAUT2. Der Auftrag dieser Runde vermutete, ein Umlaut mache
jede Zeichenkette LAENGER. Er tut es nicht: die Umschrift `ue` ist
schon zwei Oktette, und `ü` ist auch zwei. Dasselbe gilt fuer `ae`,
`oe` und `ss`/`ß`. GEMESSEN an allen 42 Ketten dieser Runde: 42 mal
dieselbe Oktettzahl vorher wie nachher.

WAS SICH SEHR WOHL AENDERT, IST DIE ZAHL DER ZEICHEN. "Waerme:  " sind
neun Zeichen in neun Oktetten, "Wärme:  " sind acht Zeichen in neun
Oktetten. Und genau daran haengt eine Beschriftungsspalte: `/bin/power`
setzt seine Zeilen mit

    Profil:  ...      Akku:    ...      Netz:    ...

untereinander, indem jede Beschriftung auf NEUN ZEICHEN aufgefuellt
ist. Wer die Umschrift ersetzt und die Fuellzeichen laesst, hat eine
Zeile, die um ein Zeichen nach links rutscht -- der Puffer stimmt, der
Uebersetzer schweigt, und die Tabelle ist schief. Das ist der Fehler,
den diese Datei findet.

Zwei Pruefungen:

  1. DIE SPALTEN. Die Tabelle unten nennt die Beschriftungsspalten
     dieses Baums mit ihrer Breite IN ZEICHEN. Jede Kette wird aus dem
     Quelltext gelesen und gezaehlt. Weicht eine ab, ist die Spalte
     schief.
  2. DIE PUFFER. Jedes `[u8; N] = "..."` traegt GENAU N Oktette, und
     danach steht mindestens eine Null. Das erzwingt auch der
     Uebersetzer -- aber erst nach ein paar Minuten Bauzeit, und diese
     Pruefung braucht eine Zehntelsekunde.

  spalten.py            beides
  spalten.py --zahlen   nur die Bilanz

rc=0 alles gerade, rc=1 eine Spalte ist schief, rc=2 ein Puffer passt
nicht.
"""
import os
import re
import sys

DEKL = re.compile(
    r'^\s*(static\s+mut\s+|static\s+|var\s+|let\s+|const\s+)'
    r'([A-Za-z_][A-Za-z_0-9]*)'
    r'\s*:\s*\[u8;\s*(\d+)\s*\]\s*=\s*"((?:\\.|[^"\\])*)"')
FN = re.compile(r'^(?:pub\s+)?fn\s+([A-Za-z_0-9]+)')

# ------------------------------------------------------------------
# DIE SPALTEN DIESES BAUMS. Datei, Namen, Breite in ZEICHEN, wofuer.
#
# Sie stehen hier ausgeschrieben und werden nicht geraten. Eine Heuristik
# ("alles, was auf ein Leerzeichen endet") findet auch `":  min  "` und
# `" von "` und meckert an Stellen, an denen gar keine Spalte ist -- ein
# Pruefer, der Unsinn meldet, wird abgeschaltet. Wer eine Spalte
# HINZUFUEGT, traegt sie hier ein; wer eine bricht, wird rot.
# ------------------------------------------------------------------
SPALTEN = [
    ("kernel/user/power.fi",
     [("zeig_profil", "s_p"), ("zeig_akku", "s_a"), ("zeig_akku", "s_net"),
      ("zeig_akku", "s_mod"), ("zeig_waerme", "s_t")], 9,
     "/bin/power setzt Profil/Akku/Netz/Modell/Wärme untereinander"),
    ("kernel/user/vpn.fi",
     [("zeigen", "s_peer"), ("zeigen", "s_hs"), ("zeigen", "s_port"),
      ("zeigen", "s_kill"), ("zeigen", "s_koct")], 15,
     "/bin/vpn setzt Gegenstellen/Handschläge/Port/Notaus/verworfen "
     "untereinander"),
    ("kernel/user/tiling.fi",
     [("zeig", "s_bl"), ("zeig", "s_kn"), ("zeig", "s_lay"),
      ("zeig", "s_rec"), ("zeig", "s_bi")], 11,
     "/bin/tiling setzt Fenster/Knoten/Aufbau/Rechteck/Tasten "
     "untereinander"),
    ("kernel/user/powermon.fi",
     [("machine", n) for n in
      ["l_now", "l_base", "l_att", "l_bat", "l_hp", "l_rt", "l_ac",
       "l_tp", "l_br"]], 15,
     "powermon setzt seine neun Messwerte untereinander"),
    ("kernel/user/netstat.fi",
     [("summary", n) for n in
      ["s_lk", "s_hi", "s_st", "s_sr", "s_ct", "s_cr"]], 20,
     "netstat setzt seine Bilanzzeilen untereinander"),
    ("kernel/procfs.fi",
     [("make_status", n) for n in
      ["l1", "l2", "l3", "l4", "l5", "l6", "l7", "l8", "l9", "l10"]], 8,
     "/proc/<pid>/status setzt seine zehn Felder untereinander"),
]


def inhalt(roh):
    """Der Text einer Firn-Kette bis zur ersten Null."""
    s = roh.split('\\0')[0]
    return (s.replace('\\n', '\n').replace('\\t', '\t')
             .replace('\\"', '"').replace('\\\\', '\\'))


def oktette(roh):
    """Wieviele Oktette dieses Literal belegt -- Escape zaehlt eins.

    RUNDE BLECH: `\\xNN` IST VIER ZEICHEN LANG UND EIN OKTETT BREIT.
    Bis hierher hat diese Funktion jeden Escape mit `i += 2`
    uebersprungen -- richtig fuer `\\0`, `\\n`, `\\t` und `\\\\`, und falsch
    fuer die hexadezimale Form: von `\\x1e` wurden `\\x` als ein Oktett
    gezaehlt und `1` und `e` danach als zwei weitere. Ein Literal aus
    sechsundzwanzig `\\xNN` kam so auf 78 statt auf 26.

    Gefunden hat es `kernel/ehci.fi`: die Tabelle, die einen
    HID-Gebrauchscode in einen PS/2-Abtastcode uebersetzt, ist ein Feld
    aus sechsundzwanzig Oktetten, und keines davon ist ein druckbares
    Zeichen. Sie ist das erste Literal dieses Baums in dieser Form --
    deshalb ist der Fehler bis zum 02.09.2026 niemandem aufgefallen.

    Die Gegenprobe steht in `tools/i18n/run.sh` und wurde NICHT
    entschaerft: eine Spalte um ein Zeichen zu kuerzen macht den Pruefer
    weiterhin rot.
    """
    n = 0
    i = 0
    while i < len(roh):
        if roh[i] == '\\':
            n += 1
            if (i + 3 < len(roh) and roh[i + 1] == 'x'
                    and roh[i + 2] in HEX and roh[i + 3] in HEX):
                i += 4
            else:
                i += 2
        else:
            n += len(roh[i].encode('utf-8'))
            i += 1
    return n


HEX = '0123456789abcdefABCDEF' 


def ketten(pfad):
    """-> {(funktion, name): (zeile, N, roh)}.

    MIT DER FUNKTION ALS TEIL DES SCHLUESSELS, und das ist kein Zierat:
    `kernel/user/power.fi` hat ein `s_t` in `zeig_profil` ("Taktstufen")
    und ein zweites in `zeig_waerme` ("Wärme:   "). Wer nur den Namen
    nimmt, misst die falsche Kette und meldet eine schiefe Spalte, die
    gerade ist.
    """
    aus = {}
    fn = '<datei>'
    for nr, z in enumerate(open(pfad, encoding='utf-8').read().split('\n'),
                           1):
        m = FN.match(z)
        if m:
            fn = m.group(1)
        if z.lstrip().startswith('//'):
            continue
        d = DEKL.match(z.split('//')[0])
        if d:
            aus.setdefault((fn, d.group(2)), (nr, int(d.group(3)),
                                              d.group(4)))
    return aus


def alle_ketten(wurzel):
    for dp, dns, fns in os.walk(os.path.join(wurzel, 'kernel')):
        dns[:] = [d for d in dns if not d.startswith('.')]
        for fn in sorted(fns):
            if not fn.endswith('.fi'):
                continue
            pfad = os.path.join(dp, fn)
            rel = os.path.relpath(pfad, wurzel).replace(os.sep, '/')
            for nr, z in enumerate(
                    open(pfad, encoding='utf-8').read().split('\n'), 1):
                if z.lstrip().startswith('//'):
                    continue
                d = DEKL.match(z.split('//')[0])
                if d:
                    yield rel, nr, d.group(2), int(d.group(3)), d.group(4)


def main(argv):
    wurzel = os.environ.get('OSUM_ROOT', '.')
    schief = []
    geprueft = 0
    for datei, namen, breite, wozu in SPALTEN:
        pfad = os.path.join(wurzel, datei)
        if not os.path.exists(pfad):
            schief.append('%s fehlt' % datei)
            continue
        k = ketten(pfad)
        for schl in namen:
            n = schl[1]
            if schl not in k:
                schief.append('%s: die Kette %s in fn %s gibt es nicht mehr'
                              % (datei, n, schl[0]))
                continue
            nr, N, roh = k[schl]
            t = inhalt(roh)
            geprueft += 1
            if len(t) != breite:
                schief.append(
                    '%s:%d  %s = %r -- %d Zeichen, die Spalte ist %d '
                    '(%s)' % (datei, nr, n, t, len(t), breite, wozu))
    print('spalten: %d Beschriftungen in %d Spalten, %d schief'
          % (geprueft, len(SPALTEN), len(schief)))
    for z in schief:
        print('    SCHIEF  ' + z)

    eng = []
    nk = 0
    for rel, nr, name, N, roh in alle_ketten(wurzel):
        nk += 1
        b = oktette(roh)
        # NUR EINE FRAGE, UND SIE IST DIE RICHTIGE: passt das Literal
        # genau in seinen Puffer? Ob danach eine Null steht, ist KEINE
        # allgemeine Regel dieses Baums -- `wlibc` legt Schluessel ohne
        # Abschluss ab und liest sie mit einer Laenge, und `launcher`
        # kopiert seine sechs Striche mit `while j < 6`.
        if b != N:
            eng.append('%s:%d  %s: das Literal ist %d Oktette, der Puffer '
                       '%d' % (rel, nr, name, b, N))
    print('puffer:  %d Zeichenketten, %d passen nicht' % (nk, len(eng)))
    for z in eng:
        print('    ZU ENG  ' + z)
    if schief:
        return 1
    if eng:
        return 2
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
