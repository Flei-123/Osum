#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
"""tools/wm/zeiger.py -- DER MAUSZEIGER, ALS BILD UND NICHT ALS ZAHLEN.

RUNDE BLECH-HID.  Justin hat den Zeiger auf seinem Blech abfotografiert
und stark vergroessert: ein weisses Dreieck, darunter eine Luecke, und
darunter zwei getrennte weisse Stummel.  Kein Pfeil.

Der Fehler stand nicht in der Hardware und nicht im Raster, sondern in
achtzehn von Hand geschriebenen Bitmasken in `kernel/wm.fi`
(`cursor_row_of`, Form 0).  Zeile 11 der Fuellung war `0x0400` -- EIN
gesetzter Bildpunkt --, und die Zeilen 12 bis 16 hatten je ZWEI
getrennte Bloecke (`0x0370`, `0x01b0`, `0x00d8`).  Das ist der
klassische X11-Pfeil, dessen Schwanz sich in zwei Beine gabelt; von Hand
in Hexadezimalzahlen geschrieben sieht das aus wie ein Zeiger und auf
dem Schirm wie ein Zerfallsprodukt.

UND GENAU DESHALB IST DIESE PRUEFUNG EIN BILD.  Achtzehn
Hexadezimalzahlen kann niemand ansehen und sagen "das ist ein Pfeil".
Ein ASCII-Bild kann jeder ansehen.  Die Maschine prueft daneben vier
Dinge, die ein Mensch uebersieht:

  (a) die Fuellung ist EINE zusammenhaengende Flaeche (4er-Nachbarschaft)
  (b) jeder Fuellpunkt hat oben, unten, links und rechts entweder
      Fuellung oder Rand -- nirgends direkt den Hintergrund, und auch
      nicht den Bildrand
  (c) keine Zeile hat zwei getrennte Bloecke, weder in der Fuellung noch
      in der Silhouette
  (d) kein Bildpunkt der Silhouette steht allein
  (e) Fuellung und Rand ueberschneiden sich nicht
  (f) die Spitze liegt oben links, auf dem Griffpunkt (0,0)

Aufruf:
    python3 tools/wm/zeiger.py [kernel/wm.fi]      pruefen und malen
    python3 tools/wm/zeiger.py --bauen             die Masken erzeugen

Rueckgabe 0, wenn alle Pruefungen halten.
"""
import re
import sys

W, H = 12, 18

# Die Silhouette dieser Runde: Spitze oben links auf (0,0), ein Dreieck
# bis Zeile 10, danach ein Schwanz, der nach rechts unten lehnt und
# schmaler wird.  Je Zeile GENAU EIN Bereich -- das ist Bedingung (c),
# und sie ist der Grund, warum der Schwanz des klassischen X11-Pfeils
# (zwei Beine mit einer Kerbe dazwischen) hier nicht nachgebaut wird.
SILHOUETTE = [
    (0, 0), (0, 1), (0, 2), (0, 3), (0, 4), (0, 5), (0, 6), (0, 7),
    (0, 8), (0, 9), (0, 9), (0, 7), (1, 7), (2, 7), (3, 7), (3, 7),
    (3, 7), (3, 7),
]


def leer():
    return [[0] * W for _ in range(H)]


def silhouette():
    s = leer()
    for y, (a, b) in enumerate(SILHOUETTE):
        for x in range(a, b + 1):
            s[y][x] = 1
    return s


def erodiert(sil):
    """Die Fuellung: was rundherum (vier Richtungen) noch in der
    Silhouette liegt.  Was uebrigbleibt, ist der Rand -- und er ist damit
    ueberall genau einen Bildpunkt breit."""
    b = leer()
    for y in range(H):
        for x in range(W):
            if not sil[y][x]:
                continue
            gut = True
            for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                nx, ny = x + dx, y + dy
                if nx < 0 or ny < 0 or nx >= W or ny >= H or not sil[ny][nx]:
                    gut = False
            b[y][x] = 1 if gut else 0
    return b


def masken(sil, body):
    """Zwei Zahlen je Zeile, Bit 11 ist links."""
    um, inn = [], []
    for y in range(H):
        u = f = 0
        for x in range(W):
            bit = 1 << (11 - x)
            if body[y][x]:
                f |= bit
            elif sil[y][x]:
                u |= bit
        um.append(u)
        inn.append(f)
    return um, inn


def firn(werte):
    aus = ""
    for v in werte:
        aus += "\\x%02x\\x%02x" % ((v >> 8) & 0xFF, v & 0xFF)
    return aus + "\\x00"


def lies(pfad):
    """Die beiden Masken der Form 0 aus dem Quelltext."""
    q = open(pfad, encoding="utf-8", errors="replace").read()
    raus = {}
    for name in ("umriss", "innen"):
        m = re.search(r'var %s: \[u8; \d+\] = b"((?:\\x[0-9a-fA-F]{2})+)"'
                      % name, q)
        if not m:
            print("  FALL  %s steht nicht in %s" % (name, pfad))
            return None
        okt = [int(t, 16) for t in re.findall(r'\\x([0-9a-fA-F]{2})',
                                              m.group(1))]
        if len(okt) < H * 2:
            print("  FALL  %s hat nur %d Oktette, gebraucht werden %d"
                  % (name, len(okt), H * 2))
            return None
        raus[name] = [(okt[i * 2] << 8) | okt[i * 2 + 1] for i in range(H)]
    return raus


def gitter(um, inn):
    sil, body = leer(), leer()
    for y in range(H):
        for x in range(W):
            bit = 1 << (11 - x)
            if inn[y] & bit:
                body[y][x] = 1
                sil[y][x] = 1
            elif um[y] & bit:
                sil[y][x] = 1
    return sil, body


def bild(sil, body):
    zeilen = []
    for y in range(H):
        r = ""
        for x in range(W):
            r += "#" if body[y][x] else ("." if sil[y][x] else " ")
        zeilen.append("  %2d |%s|" % (y, r))
    return zeilen


def bloecke(reihe):
    n, drin = 0, False
    for v in reihe:
        if v and not drin:
            n += 1
        drin = bool(v)
    return n


def pruefe(sil, body):
    fehler = []
    # (e) Fuellung und Rand ueberschneiden sich nicht -- per Bauart der
    #     Masken schon so, aber ein von Hand geschriebener Quelltext darf
    #     das verletzen.
    for y in range(H):
        for x in range(W):
            if body[y][x] and not sil[y][x]:
                fehler.append("(e) Fuellpunkt %d,%d liegt nicht in der Silhouette" % (x, y))
    # (a) EINE zusammenhaengende Flaeche
    start = None
    n = 0
    for y in range(H):
        for x in range(W):
            if body[y][x]:
                n += 1
                if start is None:
                    start = (x, y)
    if n == 0:
        fehler.append("(a) die Fuellung ist leer")
    else:
        gesehen = {start}
        stapel = [start]
        while stapel:
            x, y = stapel.pop()
            for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                nx, ny = x + dx, y + dy
                if 0 <= nx < W and 0 <= ny < H and body[ny][nx] \
                        and (nx, ny) not in gesehen:
                    gesehen.add((nx, ny))
                    stapel.append((nx, ny))
        if len(gesehen) != n:
            fehler.append("(a) die Fuellung zerfaellt: %d von %d Punkten "
                          "haengen zusammen" % (len(gesehen), n))
    # (b) jeder Fuellpunkt ist rundherum gedeckt
    for y in range(H):
        for x in range(W):
            if not body[y][x]:
                continue
            for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                nx, ny = x + dx, y + dy
                if nx < 0 or ny < 0 or nx >= W or ny >= H:
                    fehler.append("(b) Fuellpunkt %d,%d liegt am Bildrand"
                                  % (x, y))
                elif not sil[ny][nx]:
                    fehler.append("(b) Fuellpunkt %d,%d hat bei %d,%d den "
                                  "Hintergrund" % (x, y, nx, ny))
    # (c) keine Zeile mit zwei Bloecken
    for y in range(H):
        for was, g in (("Fuellung", body), ("Silhouette", sil)):
            b = bloecke(g[y])
            if b > 1:
                fehler.append("(c) Zeile %d: die %s hat %d getrennte Bloecke"
                              % (y, was, b))
    # (d) kein allein stehender Bildpunkt
    for y in range(H):
        for x in range(W):
            if not sil[y][x]:
                continue
            nachbarn = 0
            for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                nx, ny = x + dx, y + dy
                if 0 <= nx < W and 0 <= ny < H and sil[ny][nx]:
                    nachbarn += 1
            if nachbarn == 0:
                fehler.append("(d) %d,%d steht allein" % (x, y))
    # (f) die Spitze sitzt auf dem Griffpunkt
    if not sil[0][0]:
        fehler.append("(f) auf 0,0 -- dem Griffpunkt -- ist nichts")
    return fehler


def main():
    if "--bauen" in sys.argv:
        sil = silhouette()
        body = erodiert(sil)
        um, inn = masken(sil, body)
        for z in bild(sil, body):
            print(z)
        print('umriss = b"%s"' % firn(um))
        print('innen  = b"%s"' % firn(inn))
        return 0
    pfad = sys.argv[1] if len(sys.argv) > 1 else "kernel/wm.fi"
    m = lies(pfad)
    if m is None:
        return 1
    sil, body = gitter(m["umriss"], m["innen"])
    print("  DER ZEIGER, WIE ER GEMALT WIRD (# Fuellung, . Rand):")
    for z in bild(sil, body):
        print(z)
    fehler = pruefe(sil, body)
    for f in fehler:
        print("  FALL  " + f)
    if fehler:
        print("  ZEIGER: %d Beanstandungen" % len(fehler))
        return 1
    print("  ZEIGER: 6 Pruefungen, 0 Beanstandungen")
    return 0


sys.exit(main())
