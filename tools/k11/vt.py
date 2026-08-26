#!/usr/bin/env python3
"""tools/k11/vt.py -- den SERIELLEN Mitschnitt zu einem Bildschirm rechnen.

Der Editor dieser Runde schreibt Fluchtfolgen. Auf der seriellen Leitung
kommen sie als Oktette an; was ein Mensch dort saehe, weiss nur ein
Terminal. Also steht hier eines: dieselben Folgen, die `kernel/ansi.fi`
auf dem Bildschirm ausfuehrt, auf einem Feld aus Zeichen.

Damit lassen sich zwei Dinge messen, die sonst niemand messen kann:

  1. WAS AUF DER SERIELLEN LEITUNG ZU SEHEN WAERE -- gegen eine von Hand
     geschriebene Erwartung.
  2. DASS BEIDE AUSGABEWEGE DASSELBE ZEIGEN: dieses Bild gegen das, was
     `tools/gfx/schau.py lesen` aus einem echten Bildschirmfoto liest.
     Stimmen sie ueberein, dann tut `kernel/ansi.fi` auf dem Schirm genau
     das, was ein Terminal an der Leitung taete -- und das ist die
     Zusage "der Editor laeuft auf beiden".

    vt.py <mitschnitt> [zeilen] [spalten] [--ab MUSTER]

`--ab` wirft alles weg, was vor dem letzten Vorkommen von MUSTER steht --
so bleiben die Bootmeldungen des Kernels aussen vor.
"""
import sys


class Schirm:
    def __init__(self, zeilen=24, spalten=80):
        self.h = zeilen
        self.w = spalten
        self.zellen = [[' '] * spalten for _ in range(zeilen)]
        self.x = 0
        self.y = 0
        self.zustand = 0      # 0 Text, 1 nach ESC, 2 in ESC[
        self.par = []
        self.zahl = None
        self.priv = False
        self.folgen = 0

    # -- Textzustand -------------------------------------------------
    def rollen(self):
        self.zellen.pop(0)
        self.zellen.append([' '] * self.w)

    def zeichen(self, c):
        if self.x >= self.w:
            self.x = 0
            self.y += 1
            if self.y >= self.h:
                self.y = self.h - 1
                self.rollen()
        self.zellen[self.y][self.x] = c
        self.x += 1

    def steuer(self, o):
        if o == 10:                      # Zeilenvorschub
            self.x = 0
            self.y += 1
            if self.y >= self.h:
                self.y = self.h - 1
                self.rollen()
        elif o == 13:                    # Wagenruecklauf
            self.x = 0
        elif o == 8:                     # Ruecktaste: loescht, wie fb.putc
            if self.x > 0:
                self.x -= 1
                self.zellen[self.y][self.x] = ' '
        elif o == 9:                     # Tabulator auf die naechste Achtel
            n = 8 - (self.x & 7)
            for _ in range(n):
                self.zeichen(' ')

    # -- Fluchtfolgen ------------------------------------------------
    def wische(self, y0, x0, y1, x1):
        y = y0
        x = x0
        while (y, x) < (y1, x1):
            if y < self.h and x < self.w:
                self.zellen[y][x] = ' '
            x += 1
            if x >= self.w:
                x = 0
                y += 1
            if y >= self.h:
                break

    def p(self, i, dflt=1):
        if i >= len(self.par) or self.par[i] in (0, None):
            return dflt
        return self.par[i]

    def fuehre(self, final):
        self.folgen += 1
        if final in ('H', 'f'):
            self.y = min(self.p(0, 1) - 1, self.h - 1)
            self.x = min(self.p(1, 1) - 1, self.w - 1)
        elif final == 'A':
            self.y = max(0, self.y - self.p(0, 1))
        elif final == 'B':
            self.y = min(self.h - 1, self.y + self.p(0, 1))
        elif final == 'C':
            self.x = min(self.w - 1, self.x + self.p(0, 1))
        elif final == 'D':
            self.x = max(0, self.x - self.p(0, 1))
        elif final == 'J':
            was = self.p(0, 0)
            if was == 2:
                self.wische(0, 0, self.h, 0)
            elif was == 1:
                self.wische(0, 0, self.y, self.x + 1)
            else:
                self.wische(self.y, self.x, self.h, 0)
        elif final == 'K':
            was = self.p(0, 0)
            if was == 1:
                self.wische(self.y, 0, self.y, self.x + 1)
            elif was == 2:
                self.wische(self.y, 0, self.y + 1, 0)
            else:
                self.wische(self.y, self.x, self.y + 1, 0)
        # 'm', 'h', 'l' aendern nur die Darstellung, nicht den Text.

    def fuettern(self, oktette):
        for o in oktette:
            if self.zustand == 0:
                if o == 27:
                    self.zustand = 1
                elif o in (8, 9, 10, 13):
                    self.steuer(o)
                elif 32 <= o <= 126:
                    self.zeichen(chr(o))
                # alles andere: `fb.putc` malt ein '?', aber der Editor
                # schickt es nicht -- also faellt es hier weg.
            elif self.zustand == 1:
                if o == 91:
                    self.zustand = 2
                    self.par = []
                    self.zahl = None
                    self.priv = False
                else:
                    self.zustand = 0
            else:
                c = chr(o) if 32 <= o <= 126 else ''
                if c == '?':
                    self.priv = True
                elif c.isdigit():
                    self.zahl = (self.zahl or 0) * 10 + int(c)
                elif c == ';':
                    self.par.append(self.zahl or 0)
                    self.zahl = None
                elif 64 <= o <= 126:
                    if self.zahl is not None:
                        self.par.append(self.zahl)
                    self.fuehre(c)
                    self.zustand = 0
                elif o < 32:
                    self.zustand = 0
                    self.steuer(o)

    def zeilen(self):
        return [''.join(z).rstrip() for z in self.zellen]


def main():
    if len(sys.argv) < 2:
        print(__doc__)
        return 2
    daten = open(sys.argv[1], 'rb').read()
    zeilen, spalten = 24, 80
    ab = None
    rest = sys.argv[2:]
    i = 0
    while i < len(rest):
        if rest[i] == '--ab':
            ab = rest[i + 1].encode()
            i += 2
        else:
            zeilen = int(rest[i])
            spalten = int(rest[i + 1])
            i += 2
    if ab is not None:
        k = daten.rfind(ab)
        if k >= 0:
            daten = daten[k + len(ab):]
    s = Schirm(zeilen, spalten)
    s.fuettern(daten)
    for z in s.zeilen():
        print(z)
    return 0


if __name__ == '__main__':
    sys.exit(main())
