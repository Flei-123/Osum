#!/usr/bin/env python3
"""tools/k15/buendel.py -- aus `assets/apps/*.prog` die Angaben fuer mkfs.

Runde K15, zweiter Nachtrag. Ein Programm ist ein VERZEICHNIS:

    /apps/explorer.prog/
        INFO            Anzeigename, Beschreibung, Schluesselwoerter,
                        Fassung
        start           die ausfuehrbare Datei
        symbol          das Bild (OSYM)
        daten/          alles Weitere

Im Quellbaum liegt davon alles ausser `start` und `symbol`: `start` ist
das Ergebnis des Uebersetzers, `symbol` das der Zeichnung
(`symbol.txt` -> `tools/k15/symbol.py`). Dieses Werkzeug baut beides in
ein Arbeitsverzeichnis und schreibt die Zeilen, die `mkfs.py` als
Angaben nimmt -- eine je Zeile, damit keine Befehlszeile daran
zerbricht.

`start` wird NICHT kopiert, sondern als ZWEITER NAME auf die Datei unter
`/bin` gelegt (`<neu>@<vorhanden>`). Ein Buendel kostet dadurch die
Oktette seiner INFO und seines Symbols und keinen einzigen Block fuer
das Programm -- `/bin/explorer` ist 205 KiB, und ein Abbild hat zwei
Megaoktett.

Verwendung:
    buendel.py <assets/apps> <arbeitsverzeichnis> [<zusatz.prog>=...]
"""

import os
import subprocess
import sys

HIER = os.path.dirname(os.path.abspath(__file__))


def start_von(pfad):
    """Welche Datei unter /bin `start` sein soll -- steht in start.txt."""
    for zeile in open(os.path.join(pfad, "start.txt"), encoding="ascii"):
        zeile = zeile.strip()
        if zeile and not zeile.startswith("#"):
            return zeile
    raise SystemExit("buendel: %s/start.txt nennt kein Programm" % pfad)


def main(argv):
    if len(argv) < 3:
        print(__doc__)
        return 2
    quelle, arbeit = argv[1], argv[2]
    os.makedirs(arbeit, exist_ok=True)
    zeilen = ["/apps/"]
    for name in sorted(os.listdir(quelle)):
        if not name.endswith(".prog"):
            continue
        pfad = os.path.join(quelle, name)
        ziel = "/apps/%s" % name
        zeilen.append(ziel + "/")
        zeilen.append("%s/INFO=%s" % (ziel, os.path.join(pfad, "INFO")))
        sym = os.path.join(arbeit, name + ".symbol")
        r = subprocess.run([sys.executable, os.path.join(HIER, "symbol.py"),
                            os.path.join(pfad, "symbol.txt"), sym],
                           capture_output=True, text=True)
        if r.returncode != 0:
            print(r.stdout + r.stderr, file=sys.stderr)
            return 1
        zeilen.append("%s/symbol=%s" % (ziel, sym))
        zeilen.append("%s/daten/" % ziel)
        zeilen.append("%s/daten/LIESMICH=%s"
                      % (ziel, os.path.join(pfad, "daten", "LIESMICH")))
        # DER VERWEIS ZULETZT: `mkfs.py` loest den vorhandenen Pfad auf,
        # und der muss dafuer schon im Abbild stehen. Die Reihenfolge
        # dieser Zeilen ist die Reihenfolge, in der gebaut wird.
        zeilen.append("%s/start@%s" % (ziel, start_von(pfad)))
    for z in zeilen:
        print(z)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
