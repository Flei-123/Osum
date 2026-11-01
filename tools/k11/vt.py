#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
"""Usage:
    vt.py <mitschnitt> [rows] [columns] [--ab MUSTER]
"""
import sys


class Screen:
    def __init__(self, lines=24, columns=80):
        self.h = lines
        self.w = columns
        self.zellen = [[' '] * columns for _ in range(lines)]
        self.x = 0
        self.y = 0
        self.state = 0
        self.par = []
        self.num = None
        self.priv = False
        self.folgen = 0

    def rollen(self):
        self.zellen.pop(0)
        self.zellen.append([' '] * self.w)

    def char(self, c):
        if self.x >= self.w:
            self.x = 0
            self.y += 1
            if self.y >= self.h:
                self.y = self.h - 1
                self.rollen()
        self.zellen[self.y][self.x] = c
        self.x += 1

    def steuer(self, o):
        if o == 10:
            self.x = 0
            self.y += 1
            if self.y >= self.h:
                self.y = self.h - 1
                self.rollen()
        elif o == 13:
            self.x = 0
        elif o == 8:
            if self.x > 0:
                self.x -= 1
                self.zellen[self.y][self.x] = ' '
        elif o == 9:
            n = 8 - (self.x & 7)
            for _ in range(n):
                self.char(' ')

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

    def fuettern(self, oktette):
        for o in oktette:
            if self.state == 0:
                if o == 27:
                    self.state = 1
                elif o in (8, 9, 10, 13):
                    self.steuer(o)
                elif 32 <= o <= 126:
                    self.char(chr(o))
            elif self.state == 1:
                if o == 91:
                    self.state = 2
                    self.par = []
                    self.num = None
                    self.priv = False
                else:
                    self.state = 0
            else:
                c = chr(o) if 32 <= o <= 126 else ''
                if c == '?':
                    self.priv = True
                elif c.isdigit():
                    self.num = (self.num or 0) * 10 + int(c)
                elif c == ';':
                    self.par.append(self.num or 0)
                    self.num = None
                elif 64 <= o <= 126:
                    if self.num is not None:
                        self.par.append(self.num)
                    self.fuehre(c)
                    self.state = 0
                elif o < 32:
                    self.state = 0
                    self.steuer(o)

    def lines(self):
        return [''.join(z).rstrip() for z in self.zellen]


def main():
    if len(sys.argv) < 2:
        print(__doc__)
        return 2
    data = open(sys.argv[1], 'rb').read()
    lines, columns = 24, 80
    ab = None
    rest = sys.argv[2:]
    i = 0
    while i < len(rest):
        if rest[i] == '--ab':
            ab = rest[i + 1].encode()
            i += 2
        else:
            lines = int(rest[i])
            columns = int(rest[i + 1])
            i += 2
    if ab is not None:
        k = data.rfind(ab)
        if k >= 0:
            data = data[k + len(ab):]
    s = Screen(lines, columns)
    s.fuettern(data)
    for z in s.lines():
        print(z)
    return 0


if __name__ == '__main__':
    sys.exit(main())
