#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
"""tools/k15/bigfs.py -- ein Dateisystem mit einer ernsthaften Zahl von
Dateien, und die Liste dessen, was drin steht.

Runde K15, zweiter Nachtrag. Der Namensindex soll sich gegen einen
Baumdurchlauf beweisen. An zwanzig Dateien beweist sich dabei nichts:
beide sind sofort fertig, und der Unterschied liegt unter der Koernung
jeder Uhr. Also mehrere Tausend.

WAS DIESES ABBILD ANDERS MACHT ALS DIE UEBRIGEN:

  * `--inodes=4096` statt der 128, die seit Runde 62 in beiden
    Umsetzungen als Konstante standen. Die Zahl stand immer schon im
    Superblock; seit dem zweiten Nachtrag liest `kernel/fs/fs.fi` sie von
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

WOERTER = ["kupfer", "07", "datei", "quaste"]

FOLDER = ["messing", "kupfer", "zinn", "blei", "zink", "nickel",
          "chrom", "eisen"]


def names(n):
    """Die Namen, in der Reihenfolge, in der sie angelegt werden."""
    aus = []
    for i in range(n):
        folder = FOLDER[i % len(FOLDER)]
        bottom = (i // len(FOLDER)) % 2 == 1
        path_2 = "/data/%s%s" % (folder, "/tief" if bottom else "")
        aus.append((path_2, "datei%04d.txt" % i))
    return aus


def main(argv):
    if len(argv) < 2:
        print(__doc__)
        return 2
    arbeit = argv[1]
    n = int(argv[2]) if len(argv) > 2 else 4000
    os.makedirs(arbeit, exist_ok=True)
    list_2 = names(n)

    zeilen = ["--inodes=4096", "/data/"]
    seen = set()
    for path_2, _ in list_2:
        parts = path_2.strip("/").split("/")
        for k in range(1, len(parts) + 1):
            p = "/" + "/".join(parts[:k]) + "/"
            if p not in seen:
                seen.add(p)
                if p != "/data/":
                    zeilen.append(p)
    for path_2, name in list_2:
        zeilen.append("%s/%s=" % (path_2, name))
    with open(os.path.join(arbeit, "angaben"), "w") as f:
        f.write("\n".join(zeilen) + "\n")

    with open(os.path.join(arbeit, "namen"), "w") as f:
        for path_2, name in list_2:
            f.write("%s/%s\n" % (path_2, name))

    alle = [name for _, name in list_2]
    alle += [p.strip("/").split("/")[-1] for p in sorted(seen)]
    alle += ["data"]
    with open(os.path.join(arbeit, "erwartet"), "w") as f:
        for w in WOERTER:
            f.write("%s %d\n"
                    % (w, sum(1 for x in alle if w.lower() in x.lower())))
    print("big: %d files, %d folders, %d names"
          % (n, len(seen), len(alle)))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
