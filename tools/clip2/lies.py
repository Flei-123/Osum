#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
"""tools/clip2/lies.py -- RUNDE CLIP-2: was nach dem Ablegen WIRKLICH
auf der Platte steht.

    lies.py <abbild>

DAS IST DER SCHIEDSRICHTER DIESER RUNDE. Alles andere im Laeufer ist,
was das PROGRAMM ueber sich sagt ("expl: drop ... rc=0"); hier steht,
was der WIRT im Abbild findet. Ein Ablegen, das rc=0 meldet und nichts
bewegt hat, faellt genau hier auf -- und sonst nirgends.

Gelesen wird mit dem Leser aus `tools/fsrobust/check.py`: er kennt OFS
in allen drei Fassungen, und ein zweiter Leser waere ein zweiter Ort,
an dem dasselbe falsch sein kann.

Ausgegeben wird eine Zeile je Befund, damit `run.sh` mit `grep` prueft
und nicht mit Augenmass:

    da  <pfad> ino=<n> size=<n>     das Stueck liegt dort
    weg <pfad>                      es liegt dort NICHT
    inode gleich <n>                Quelle und Ziel haben dieselbe Inode
    inode anders <alt> <neu>        sie haben es nicht
    inhalt ok <text>                der Inhalt ist der erwartete
    inhalt falsch <text>            er ist es nicht
"""
import os
import sys

HIER = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HIER, "..", "fsrobust"))
sys.path.insert(0, os.path.join(HIER, "..", "osum"))

import check  # noqa: E402
import mkfs   # noqa: E402


def main(argv):
    if len(argv) < 2:
        print("Aufruf: lies.py <abbild>", file=sys.stderr)
        return 2
    b = check.Bild(argv[1])
    if not b.magic:
        print("kein OFS-Abbild", file=sys.stderr)
        return 1

    def zeig(pfad):
        ino = b.finde(pfad)
        if ino:
            print("da %s ino=%d size=%d"
                  % (pfad, ino, b.ig(ino, mkfs.I_SIZE)))
        else:
            print("weg %s" % pfad)
        return ino

    # DIE VIER STELLEN, um die es geht.
    alt = zeig("/data/alpha.txt")
    neu = zeig("/data/bilder/alpha.txt")
    zeig("/data/notizen")
    zeig("/data/beta.txt")

    # DIE INODE. Sie ist der ganze Unterschied zwischen "umgehaengt"
    # und "kopiert und geloescht": beim Umhaengen bleibt die Nummer.
    # Verglichen wird gegen die Nummer, die `mkfs` vergeben hat -- die
    # steht nicht mehr zur Verfuegung, sobald die Datei weg ist, also
    # nimmt der Laeufer den zweiten Weg: die Nummer der Datei am ZIEL
    # gegen die Nummer, die eine NICHT bewegte Nachbardatei hat. Ist
    # alpha kopiert worden, bekam die Kopie eine FRISCHE Inode --
    # also eine, die groesser ist als alle, die mkfs vergeben hat.
    #
    # Genauer und ohne Raten geht es mit der Nummer aus dem Abbild VOR
    # dem Lauf; die reicht `run.sh` als zweites Argument herein.
    if len(argv) > 2:
        try:
            vorher = int(argv[2])
        except ValueError:
            vorher = 0
        if neu and vorher and neu == vorher:
            print("inode gleich %d" % neu)
        elif neu and vorher:
            print("inode anders %d %d" % (vorher, neu))

    if neu:
        roh = b.lies(neu, 0, b.ig(neu, mkfs.I_SIZE))
        txt = roh.decode("latin-1").strip()
        if txt == "eins":
            print("inhalt ok %s" % txt)
        else:
            print("inhalt falsch %r" % txt)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
