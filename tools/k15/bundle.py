#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
"""tools/k15/bundle.py -- aus `assets/apps/*.osp` die Angaben fuer mkfs.

Runde K15, zweiter Nachtrag. Ein Programm ist ein VERZEICHNIS:

    /apps/explorer.osp/
        INFO            Anzeigename, Beschreibung, Schluesselwoerter,
                        Fassung
        start           die ausfuehrbare Datei
        symbol          das Bild (OSYM)
        data/          alles Weitere

Im Quellbaum liegt davon alles ausser `start` und `symbol`: `start` ist
das Ergebnis des Uebersetzers, `symbol` das der Zeichnung
(`symbol.txt` -> `tools/k15/icon.py`). Dieses Werkzeug baut beides in
ein Arbeitsverzeichnis und schreibt die Zeilen, die `mkfs.py` als
Angaben nimmt -- eine je Zeile, damit keine Befehlszeile daran
zerbricht.

`start` wird NICHT kopiert, sondern als ZWEITER NAME auf die Datei unter
`/bin` gelegt (`<neu>@<vorhanden>`). Ein Buendel kostet dadurch die
Oktette seiner INFO und seines Symbols und keinen einzigen Block fuer
das Programm -- `/bin/explorer` ist 205 KiB, und ein Abbild hat zwei
Megaoktett.

Verwendung:
    bundle.py <assets/apps> <arbeitsverzeichnis> [nur=<programmliste>]

RUNDE WERKZEUGE: `nur=` -- WELCHE PROGRAMME AUF DIESER PLATTE LIEGEN.

Ein Buendel ist ein VERWEIS auf eine Datei unter /bin. Liegt die dort
nicht, bricht `mkfs.py` mit "gibt es nicht" ab -- und zwar in JEDEM
Laeufer, der eine kleine Programmliste hat. Bis zu dieser Runde stand
deshalb in `tools/themestore/build.sh` eine Zeile mit zwei Namen
(`editor.osp`, `widgets.osp`), die vorher geloescht wurden. Die naechste
Runde mit einem neuen Buendel laeuft in dieselbe Wand -- diese hier ist
es gewesen.

Also sagt der Aufrufer, was er hat, und was er nicht hat, wird
uebersprungen. Ohne `nur=` bleibt alles wie vorher: jedes Buendel kommt
mit.
"""

import os
import subprocess
import sys

HIER = os.path.dirname(os.path.abspath(__file__))


# ===================================================== RUNDE TUERSCHLOSS
#
# WIE WEIT VORNE DIE ANGABEN STEHEN MUESSEN, und warum das hier
# nachgerechnet und nicht gehofft wird.
#
# `appdir.eine_datei` (kernel/user/appdir.fi) liest von einer INFO
# GENAU 1023 Oktette. Steht `name=` dahinter, findet der Starter keinen
# Namen, zaehlt das Buendel nicht mit -- und es fehlt im Menue, obwohl
# es vollstaendig im Abbild liegt. Nichts beschwert sich dabei.
#
# GEMESSEN, 08.09.2026: die erste Fassung von settings.osp/INFO hatte
# den Kommentar vor den Angaben, `name=` stand bei Oktett 1109, und der
# Starter meldete `apps=5` statt 6. Beim Nachrechnen stellte sich
# heraus, dass explorer.osp/INFO mit 1019 Oktetten nur VIER Oktette vom
# selben Fehler entfernt war -- ein Satz mehr im Kommentar, und der
# Dateimanager waere aus dem Menue verschwunden.
#
# Deshalb bricht der Bau jetzt ab, statt ein stummes Buendel zu bauen.
INFO_GRENZE = 1023


def angaben_stehen_vorn(pfad):
    """Ende der letzten `schluessel=wert`-Zeile in der INFO.

    Gibt (ende, grenze). `ende < grenze` ist die Bedingung."""
    roh = open(pfad, "rb").read()
    letzte = -1
    for zeile in (b"name=", b"info=", b"keys=", b"fassung=", b"net=",
                  b"exec=", b"icon="):
        p = roh.find(zeile)
        if p > letzte:
            letzte = p
    if letzte < 0:
        return (0, INFO_GRENZE)
    ende = roh.find(b"\n", letzte)
    return (len(roh) if ende < 0 else ende, INFO_GRENZE)


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
    nur = None
    for a in argv[3:]:
        if a.startswith("nur="):
            nur = set("/bin/" + w for w in a[4:].split())
    os.makedirs(arbeit, exist_ok=True)
    zeilen = ["/apps/"]
    for name in sorted(os.listdir(quelle)):
        if not name.endswith(".osp"):
            continue
        pfad = os.path.join(quelle, name)
        if nur is not None and start_von(pfad) not in nur:
            continue
        # RUNDE TUERSCHLOSS: stehen die Angaben weit genug vorn?
        # Ein Buendel, dessen `name=` hinter Oktett 1023 steht, wird vom
        # Starter stumm uebergangen (siehe oben). Lieber hier abbrechen.
        ende, grenze = angaben_stehen_vorn(os.path.join(pfad, "INFO"))
        if ende >= grenze:
            print("buendel: %s/INFO -- die Angaben enden erst bei Oktett %d,"
                  " appdir.eine_datei liest nur %d. Der Starter wuerde dieses"
                  " Buendel stumm uebergehen. Kommentar hinter die Angaben."
                  % (pfad, ende, grenze), file=sys.stderr)
            return 1
        ziel = "/apps/%s" % name
        zeilen.append(ziel + "/")
        zeilen.append("%s/INFO=%s" % (ziel, os.path.join(pfad, "INFO")))
        sym = os.path.join(arbeit, name + ".symbol")
        r = subprocess.run([sys.executable, os.path.join(HIER, "icon.py"),
                            os.path.join(pfad, "symbol.txt"), sym],
                           capture_output=True, text=True)
        if r.returncode != 0:
            print(r.stdout + r.stderr, file=sys.stderr)
            return 1
        zeilen.append("%s/symbol=%s" % (ziel, sym))
        zeilen.append("%s/data/" % ziel)
        zeilen.append("%s/data/README=%s"
                      % (ziel, os.path.join(pfad, "data", "README")))
        # DER VERWEIS ZULETZT: `mkfs.py` loest den vorhandenen Pfad auf,
        # und der muss dafuer schon im Abbild stehen. Die Reihenfolge
        # dieser Zeilen ist die Reihenfolge, in der gebaut wird.
        zeilen.append("%s/start@%s" % (ziel, start_von(pfad)))
    for z in zeilen:
        print(z)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
