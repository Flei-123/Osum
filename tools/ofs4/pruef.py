#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
"""tools/ofs4/pruef.py -- was nach einem Groessenwechsel auf der PLATTE steht.

Es gibt in diesem Baum eine Regel, und dies ist ihre Anwendung auf die
Runde OFS4: JEDE Aussage ueber das Format hat zwei Umsetzungen, eine im
Kern und eine auf dem Wirt. Fuer die Struktur ist die zweite schon da --
`tools/fsrobust/pruef.py::struktur` liest die ganze Geometrie aus dem
Superblock und prueft Bereiche, Zeiger, Doppelbelegung und Karte gegen
die Wirklichkeit. Diese Datei benutzt sie und legt das dazu, was fuer
diese Runde neu ist:

  * der Inhalt des Bestandes (`/d4/...`), vom Wirt aus dem Abbild
    gelesen und NICHT durch den Kern -- ein Umzug, der einen Block an
    die falsche Stelle legt, faellt damit auf, auch wenn der Kern
    denselben Fehler beim Lesen noch einmal machen wuerde;
  * die Inodenummern, die sich durch keinen Groessenwechsel aendern
    duerfen;
  * die Zusage des Verkleinerns: HINTER `SB_BLOCKS` liegt kein Block
    einer Datei, und JEDES Bit dahinter steht auf belegt.

    pruef.py struktur <abbild>     wie fsrobust, unveraendert
    pruef.py inhalt   <abbild>     der Bestand von OFS4
    pruef.py grenze   <abbild>     nichts Belegtes hinter SB_BLOCKS
"""

import os
import sys

HIER = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HIER, "..", "osum"))
sys.path.insert(0, os.path.join(HIER, "..", "fsrobust"))
import mkfs          # noqa: E402
import pruef as fsr  # noqa: E402  -- tools/fsrobust/pruef.py

BS = mkfs.BS
M64 = 0xFFFFFFFFFFFFFFFF
FNV_OFF = 0xCBF29CE484222325
FNV_PRIME = 0x100000001B3

# Dieselben drei Stellen wie in `kernel/user/ofs4.fi`. Zwei Umsetzungen
# derselben Zahl -- wenn eine der beiden sich irrt, faellt es auf.
# `kernel/user/ofs4.fi::NFUELL`, dieselbe Zahl -- die beiden
# Fingerabdruecke ueber die Fuellstuecke muessen GLEICH herauskommen,
# und das ist die eigentliche Gegenprobe: zwei Umsetzungen, eine im
# Gast und eine hier.
NFUELL = 16

T_P0 = 0
T_P1 = 1000000
T_P2 = 2200000


def muster(pos):
    """`kernel/user/ofs4.fi::muster`, dieselbe Rechnung."""
    return (((pos * 2654435761) & M64) + 1013904223) % 251


def fnv_bytes(daten):
    """`kernel/user/ofs4.fi::fingerabdruck`, dieselbe Rechnung: JE
    LESEBLOCK von 4096 Oktetten erst ueber volle 64-Bit-Woerter, dann
    der Rest oktettweise. Das Programm im Gast liest in Stuecken von
    4096 -- wer hier ueber die ganze Datei am Stueck rechnet, bekommt
    eine andere Zahl, sobald die Laenge kein Vielfaches von acht ist."""
    h = FNV_OFF
    for a in range(0, len(daten), 4096):
        stueck = daten[a:a + 4096]
        n = len(stueck)
        voll = (n // 8) * 8
        for i in range(0, voll, 8):
            h = ((h ^ int.from_bytes(stueck[i:i + 8], "little"))
                 * FNV_PRIME) & M64
        for i in range(voll, n):
            h = ((h ^ stueck[i]) * FNV_PRIME) & M64
    return h


def probe(bild, ino, pos):
    """512 Oktette ab `pos`, und wie viele davon stimmen."""
    d = bild.lies(ino, pos, 512)
    if not d:
        return 0
    return sum(1 for i, c in enumerate(d) if c == muster(pos + i))


def inhalt(bild):
    """Der Bestand, vom Wirt gelesen. Rueckgabe: (befunde, zeilen)."""
    befunde = []
    zeilen = []
    if not bild.magic:
        return ["keine OSUM-OFS-Kennung"], zeilen

    def sag(name, wert):
        zeilen.append("wirt: %s = %s" % (name, wert))

    tief = bild.finde("/d4/tief")
    mittel = bild.finde("/d4/mittel")
    hart = bild.finde("/d4/hart")
    if not tief or not mittel:
        return ["/d4/tief oder /d4/mittel fehlt"], zeilen
    for name, pos in (("tief_0", T_P0), ("tief_1", T_P1), ("tief_2", T_P2)):
        g = probe(bild, tief, pos)
        sag(name, g)
        if g != 512:
            befunde.append("%s: nur %d von 512 Oktetten stimmen" % (name, g))
    gr = bild.ig(mittel, mkfs.I_SIZE)
    d = bild.lies(mittel, 0, gr)
    sag("mittel", fnv_bytes(d if d else b""))
    sag("len_mittel", gr)
    sag("ino_tief", tief)
    sag("ino_mittel", mittel)
    sag("ino_hart", hart)
    if hart != mittel:
        befunde.append("der harte Verweis zeigt auf %s statt auf %s"
                       % (hart, mittel))
    # Die Fuellstuecke: eine Zahl fuer alle, wie im Gast.
    h = FNV_OFF
    da = 0
    for i in range(NFUELL):
        ino = bild.finde("/d4/g%03d" % i)
        if ino:
            da += 1
            gr = bild.ig(ino, mkfs.I_SIZE)
            f = fnv_bytes(bild.lies(ino, 0, gr) or b"")
        else:
            f = 0
        h = ((h ^ f) * FNV_PRIME) & M64
    sag("fuell", h)
    sag("ndate", da)
    return befunde, zeilen


def grenze(bild):
    """DIE ZUSAGE DES VERKLEINERNS, auf der Platte nachgesehen.

    1. Kein Blockzeiger einer Datei liegt bei oder hinter `SB_BLOCKS`.
    2. Jedes Bit von `SB_BLOCKS` bis zum Ende der KARTE steht auf
       belegt -- sonst gaebe ein Kern, der diese Platte spaeter
       einhaengt, Bloecke her, die es nicht mehr gibt.
    """
    befunde = []
    if not bild.magic:
        return ["keine OSUM-OFS-Kennung"]
    sb = bild.blk(0)
    behauptet = int.from_bytes(sb[mkfs.SB["BLOCKS"]:mkfs.SB["BLOCKS"] + 8],
                               "little")
    ueber = 0
    for ino in range(1, bild.inodes + 1):
        if bild.ig(ino, mkfs.I_TYPE) == 0:
            continue
        for p in bild.bloecke(ino):
            if p >= behauptet:
                ueber += 1
    if ueber:
        befunde.append("%d Blockzeiger liegen hinter SB_BLOCKS=%d"
                       % (ueber, behauptet))
    frei = 0
    ende = bild.bmblocks * 4096
    for b in range(behauptet, ende):
        kb = bild.bmstart + b // 4096
        if (kb + 1) * BS > bild.laenge:
            break
        blk = bild.blk(kb)
        if not ((blk[(b % 4096) // 8] >> (b % 8)) & 1):
            frei += 1
    if frei:
        befunde.append("%d Bits hinter SB_BLOCKS=%d stehen auf FREI"
                       % (frei, behauptet))
    return befunde


def main(argv):
    if len(argv) < 3:
        print(__doc__)
        return 2
    was, pfad = argv[1], argv[2]
    bild = fsr.Bild(pfad)
    if was == "struktur":
        befunde, z = fsr.struktur(bild)
        for k in sorted(z):
            print("wirt: %s = %d" % (k, z[k]))
    elif was == "inhalt":
        befunde, zeilen = inhalt(bild)
        for zl in zeilen:
            print(zl)
    elif was == "grenze":
        befunde = grenze(bild)
    else:
        print(__doc__)
        return 2
    for b in befunde:
        print("BEFUND: %s" % b)
    return 1 if befunde else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
