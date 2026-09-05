#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/laden/pakete.sh -- AUS DEN PROGRAMMEN DIESES BAUMS ECHTE PAKETE.
#
#   bash tools/laden/pakete.sh [arbeitsverzeichnis]
#
# Braucht vorher `bash tools/laden/build.sh <dasselbe verzeichnis>` --
# dort liegen die uebersetzten Programme unter bin/.
#
# WAS ENTSTEHT (unter $OUT):
#
#   info/<paket>            die INFO des Buendels (appdir.fi-Format)
#   symbole/<paket>         das Symbol als OSYM (tools/k15/icon.py)
#   rezepte/<paket>.rezept  das Rezept fuer pkg/opk.py
#   stand/<paket>-<n>.opk   DAS PAKET
#
# `stand/` ist genau das, was `tools/ota/veroeffentlichen.py --stand`
# erwartet: ein Verzeichnis, in dem NUR .opk-Dateien liegen. INDEX,
# Signaturen und VERZEICHNIS macht dieses Skript ABSICHTLICH NICHT --
# dafuer gibt es das Veroeffentlichungswerkzeug, und zwei Stellen, die
# einen INDEX schreiben, sind eine Stelle zu viel.
#
# WARUM DER DATEINAME NUR DIE ERSTE ZIFFER DER FASSUNG TRAEGT
# (`explorer-1.opk` und nicht `explorer-1.0.0.opk`): ein
# Verzeichniseintrag in OFS ist 32 Oktette, davon 24 fuer den Namen
# samt Null (`kernel/fs.fi`, NAME_LEN = 24). `ota` legt neben das
# Paket dessen Signatur -- `<datei>.opk.sig` --, und
# `widgetdemo-1.0.0.opk.sig` sind 24 Zeichen und passen damit NICHT
# mehr in einen Eintrag. Mit der kurzen Form sind es 20.
set -uo pipefail
cd "$(dirname "$0")/../.."
ROOT=$(pwd)
OUT=${1:-/tmp/laden}
OPK=${OPK:-/root/orientos-install/pkg/opk.py}
TAB=tools/laden/apps.tab

[ -d "$OUT/bin" ] || { echo "== $OUT/bin fehlt -- erst tools/laden/build.sh"; exit 1; }
rm -rf "$OUT/stand" "$OUT/info" "$OUT/symbole" "$OUT/rezepte"
mkdir -p "$OUT/stand" "$OUT/info" "$OUT/symbole" "$OUT/rezepte"

n=0
while IFS='|' read -r paket programm fassung titel info keys art; do
    case "${paket:-}" in ""|\#*) continue ;; esac
    prog="$OUT/bin/$programm"
    [ -x "$prog" ] || { echo "== $prog fehlt -- tools/laden/build.sh baut es"; exit 1; }
    zeich="tools/laden/symbole/$paket.txt"
    [ -f "$zeich" ] || { echo "== $zeich fehlt"; exit 1; }

    # 1. DIE INFO DES BUENDELS. Das ist das Format aus
    #    kernel/user/appdir.fi und NICHT das der Paketmetadaten: der
    #    Starter liest sie, nicht die Paketverwaltung.
    {
        echo "# /apps/$paket.osp/INFO -- aus tools/laden/apps.tab gebaut."
        echo "name=$titel"
        echo "info=$info"
        echo "keys=$keys"
        echo "fassung=${fassung%%.*}"
    } > "$OUT/info/$paket"

    # 2. DAS SYMBOL. Aus der Zeichnung, mit demselben Werkzeug, das die
    #    mitgelieferten Buendel benutzen -- kein zweites Format.
    python3 tools/k15/icon.py "$zeich" "$OUT/symbole/$paket" \
        > "$OUT/symbole/$paket.log" 2>&1 || {
        echo "== Symbol $paket:"; cat "$OUT/symbole/$paket.log"; exit 1; }

    # 3. DAS REZEPT. Drei Dateien gehen ins Archiv, und genau die drei
    #    macht `opk` auf dem Geraet zum Buendel: `start`, `INFO`,
    #    `symbol`.
    {
        echo "# Runde LADEN, aus tools/laden/apps.tab erzeugt -- nicht von Hand aendern."
        echo "name=$paket"
        echo "fassung=$fassung"
        echo "titel=$titel"
        echo "info=$info"
        echo "keys=$keys"
        echo "handle=$art"
        echo "datei=start $ROOT/$OUT/bin/$programm" | sed "s#$ROOT//#/#"
        echo "datei=INFO $OUT/info/$paket"
        echo "datei=symbol $OUT/symbole/$paket"
    } > "$OUT/rezepte/$paket.rezept"
    sed -i "s#^datei=start .*#datei=start $prog#" "$OUT/rezepte/$paket.rezept"

    python3 "$OPK" bauen "$OUT/rezepte/$paket.rezept" \
        -o "$OUT/stand/$paket-${fassung%%.*}.opk" || exit 1
    n=$((n + 1))
done < "$TAB"

echo "   $n Pakete, zusammen $(du -sb "$OUT/stand" | cut -f1) Oktette"
exit 0
