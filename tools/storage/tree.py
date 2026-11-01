#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
"""tools/storage/tree.py -- ein Dateisystem mit vielen Dateien UND mit
Inhalt, und daneben die Wahrheit darueber, in Zahlen.

Runde SPEICHER. `tools/k15/bigfs.py` baut viertausend LEERE Dateien --
fuer einen Namensindex genau richtig, denn der haelt Namen. Fuer eine
Speicherplatzanalyse ist es wertlos: alle Summen waeren null, jede
Prozentangabe null, jede Kachel gleich gross, und ein Fehler in der
Aufsummierung fiele nicht auf, weil 0 + 0 immer 0 ergibt.

WAS DIESES WERKZEUG ANDERS MACHT:

  * ES GIBT DEN DATEIEN INHALT, und zwar SCHIEF verteilt. Ein paar
    grosse, viele kleine -- so sieht eine Platte wirklich aus, und nur
    so hat eine Treemap etwas zu zeigen. Waeren alle gleich gross, sagte
    ein Bild mit gleich grossen Kacheln nichts darueber aus, ob die
    Flaechen wirklich gerechnet wurden.
  * ES SCHREIBT AUF, WAS HERAUSKOMMEN MUSS. Fuer jedes Verzeichnis die
    Summe in Oktetten und in aufgerundeten Kilooktett-Bloecken, auf dem
    WIRT gerechnet, aus der Liste, aus der das Abbild gebaut wird. Damit
    hat der Testlaeufer eine DRITTE Zahl: Index, Durchlauf -- und die
    Arithmetik des Wirts. Zwei Wege, die sich einig sind, koennen
    denselben Fehler haben; drei ist unwahrscheinlicher.

DIE GRENZE DES ABBILDS, und sie ist der Grund fuer die Groessenwahl: die
Blockkarte von OFS ist EIN Block, also 4096 Bloecke, also zwei
Megaoktett. Davon gehen 1026 Bloecke fuer Superblock, Karte und die
Inode-Tabelle mit 4096 Eintraegen ab, und die Programme wollen auch
Platz. Was uebrig bleibt, ist ungefaehr ein Megaoktett -- deshalb
bekommen nur einige hundert Dateien Inhalt und nicht alle viertausend.

Verwendung:
    baum.py <arbeitsverzeichnis> [<zahl der dateien>] [<oktette gesamt>]
"""

import os
import sys

ORDNER = ["messing", "kupfer", "zinn", "blei", "zink", "nickel",
          "chrom", "eisen"]


def namen(n):
    """Die Namen, in der Reihenfolge, in der sie angelegt werden --
    dieselbe Aufteilung wie in tools/k15/bigfs.py, damit die beiden
    Abbilder vergleichbar bleiben."""
    aus = []
    for i in range(n):
        ordner = ORDNER[i % len(ORDNER)]
        unten = (i // len(ORDNER)) % 2 == 1
        pfad = "/data/%s%s" % (ordner, "/tief" if unten else "")
        aus.append((pfad, "datei%04d.txt" % i))
    return aus


def groessen(n, budget):
    """Eine schiefe Verteilung ohne Zufall: jede sechzehnte Datei
    bekommt Inhalt, und ihre Groesse faellt geometrisch. Kein
    Zufallsgenerator, weil ein Abbild, das bei jedem Lauf anders
    aussieht, keine Zusage traegt -- zweimal bauen muss zweimal
    dasselbe ergeben."""
    aus = [0] * n
    kand = list(range(0, n, 13))
    roh = []
    wert = 65536
    for k in range(len(kand)):
        roh.append(wert)
        if wert > 64:
            wert = wert * 88 // 100
    summe = sum(roh)
    for k, i in enumerate(kand):
        aus[i] = max(1, roh[k] * budget // summe)
    return aus


def main(argv):
    if len(argv) < 2:
        print(__doc__)
        return 2
    arbeit = argv[1]
    n = int(argv[2]) if len(argv) > 2 else 4000
    budget = int(argv[3]) if len(argv) > 3 else 600000
    inhalt = os.path.join(arbeit, "inhalt")
    os.makedirs(inhalt, exist_ok=True)

    liste = namen(n)
    sz = groessen(n, budget)

    zeilen = ["--inodes=4096", "/data/"]
    gesehen = set()
    for pfad, _ in liste:
        teile = pfad.strip("/").split("/")
        for k in range(1, len(teile) + 1):
            p = "/" + "/".join(teile[:k]) + "/"
            if p not in gesehen:
                gesehen.add(p)
                if p != "/data/":
                    zeilen.append(p)

    for i, (pfad, name) in enumerate(liste):
        if sz[i] > 0:
            wirt = os.path.join(inhalt, "f%05d" % i)
            with open(wirt, "wb") as f:
                f.write(bytes([65 + (i % 26)]) * sz[i])
            zeilen.append("%s/%s=%s" % (pfad, name, wirt))
        else:
            zeilen.append("%s/%s=" % (pfad, name))

    with open(os.path.join(arbeit, "angaben"), "w") as f:
        f.write("\n".join(zeilen) + "\n")

    okt = {}
    kb = {}
    dat = {}

    def dazu(p, o):
        teile = p.strip("/").split("/")
        for k in range(0, len(teile) + 1):
            d = "/" + "/".join(teile[:k])
            if d == "":
                d = "/"
            if len(d) > 1 and d.endswith("/"):
                d = d[:-1]
            okt[d] = okt.get(d, 0) + o
            kb[d] = kb.get(d, 0) + (o + 1023) // 1024
            dat[d] = dat.get(d, 0) + 1

    for i, (pfad, _name) in enumerate(liste):
        dazu(pfad, sz[i])
    for d in sorted(gesehen):
        dd = d if len(d) == 1 else d.rstrip("/")
        okt.setdefault(dd, 0)
        kb.setdefault(dd, 0)
        dat.setdefault(dd, 0)
    okt.setdefault("/", 0)
    kb.setdefault("/", 0)
    dat.setdefault("/", 0)

    with open(os.path.join(arbeit, "soll"), "w") as f:
        for d in sorted(okt):
            f.write("%s %d %d %d\n" % (d, okt[d], kb[d], dat[d]))

    mit = sum(1 for x in sz if x > 0)
    print("tree: %d files (%d with content), %d folders, %d octets, "
          "%d KiB-Bloecke"
          % (n, mit, len(gesehen), okt["/data"], kb["/data"]))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
