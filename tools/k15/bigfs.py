#!/usr/bin/env python3
"""tools/k15/bigfs.py -- ein Dateisystem mit einer ernsthaften Zahl von
Dateien, und die Liste dessen, was drin steht.

Runde K15, zweiter Nachtrag. Der Namensindex soll sich gegen einen
Baumdurchlauf beweisen. An zwanzig Dateien beweist sich dabei nichts:
beide sind sofort fertig, und der Unterschied liegt unter der Koernung
jeder Uhr. Also mehrere Tausend.

WAS DIESES ABBILD ANDERS MACHT ALS DIE UEBRIGEN:

  * `--inodes=4096` statt der 128, die seit Runde 62 in beiden
    Umsetzungen als Konstante standen. Die Zahl stand immer schon im
    Superblock; seit dem zweiten Nachtrag liest `kernel/fs.fi` sie von
    dort (`mount`), und `tools/osum/mkfs.py` schreibt sie hin.
  * LEERE Dateien. Ein Name, ein Inode, kein Datenblock. Der Index haelt
    Namen und keine Inhalte -- genau wie sein Vorbild --, und 4000
    Dateien mit Inhalt passten nicht auf ein Abbild von zwei Megaoktett.
  * EIN BAUM UND NICHT EIN ORDNER. Der Baumdurchlauf soll absteigen
    muessen, sonst misst man ihn zu guenstig: er hat hier acht Ordner
    unter `/data`, jeder mit einem Unterordner.

WAS DABEI HERAUSKOMMT, IST NACHRECHENBAR: dieses Werkzeug schreibt
neben die Angaben fuer `mkfs.py` auch eine Liste der Namen und, fuer
jedes gesuchte Wort, wie viele davon es treffen MUESSTE. Der Testlaeufer
haelt die Zahlen aus der Maschine dagegen -- er glaubt weder dem Index
noch dem Durchlauf.

Verwendung:
    bigfs.py <arbeitsverzeichnis> [<zahl der dateien>]
"""

import os
import sys

# Die Woerter, nach denen gesucht wird, und warum gerade diese:
#   "kupfer"  kommt in genau einem Namen vor -- ein Treffer.
#   "07"      trifft eine Handvoll -- mehr als einen, weniger als alle.
#   "datei"   trifft fast alles -- die teuerste Suche.
#   "quaste"  kommt NIRGENDS vor. Eine Suche, die immer etwas findet,
#             ist keine Suche.
WOERTER = ["kupfer", "07", "datei", "quaste"]

ORDNER = ["messing", "kupfer", "zinn", "blei", "zink", "nickel",
          "chrom", "eisen"]


def namen(n):
    """Die Namen, in der Reihenfolge, in der sie angelegt werden."""
    aus = []
    for i in range(n):
        ordner = ORDNER[i % len(ORDNER)]
        unten = (i // len(ORDNER)) % 2 == 1
        pfad = "/data/%s%s" % (ordner, "/tief" if unten else "")
        aus.append((pfad, "datei%04d.txt" % i))
    return aus


def main(argv):
    if len(argv) < 2:
        print(__doc__)
        return 2
    arbeit = argv[1]
    n = int(argv[2]) if len(argv) > 2 else 4000
    os.makedirs(arbeit, exist_ok=True)
    liste = namen(n)

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
    for pfad, name in liste:
        zeilen.append("%s/%s=" % (pfad, name))
    with open(os.path.join(arbeit, "angaben"), "w") as f:
        f.write("\n".join(zeilen) + "\n")

    with open(os.path.join(arbeit, "namen"), "w") as f:
        for pfad, name in liste:
            f.write("%s/%s\n" % (pfad, name))

    # Was jedes Wort treffen MUSS -- gezaehlt ueber die NAMEN, nicht
    # ueber die Pfade: der Index haelt Namen, und `locate` vergleicht
    # Namen. Die Ordner zaehlen mit, sie haben auch Namen.
    alle = [name for _, name in liste]
    alle += [p.strip("/").split("/")[-1] for p in sorted(gesehen)]
    alle += ["data"]
    with open(os.path.join(arbeit, "erwartet"), "w") as f:
        for w in WOERTER:
            f.write("%s %d\n"
                    % (w, sum(1 for x in alle if w.lower() in x.lower())))
    print("gross: %d Dateien, %d Ordner, %d Namen"
          % (n, len(gesehen), len(alle)))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
