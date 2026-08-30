#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/ota/pakete.sh -- DIE QUELLEN, DIE UEBER DAS NETZ AUSGELIEFERT
# WERDEN. Sechs Stueck, und vier davon sind kaputt.
#
# `tools/install/pakete.sh` baut zwei ordentliche, signierte Quellen
# (Fassung 1 und 2). `tools/update/pakete.sh` baut Fassung 3, die sich
# sauber installiert und NICHT hochkommt, dazu die beschaedigten Pakete
# der Runde UPDATE. Diese Datei setzt darauf auf und macht daraus
# VERZEICHNISSE -- den signierten Katalog, den ein Geraet ueber HTTPS
# holt.
#
# WAS ENTSTEHT (unter $OUT):
#
#   netz1/       Fassung 1, VERZEICHNIS mit `fassung 1`.
#                Der RUECKSCHRITT: wird angeboten, nachdem 2 schon
#                installiert ist. Alles daran ist richtig signiert --
#                genau das ist der Punkt. Muss abgelehnt werden.
#   netz2/       Fassung 2, VERZEICHNIS mit `fassung 2`. Das gute
#                Update.
#   netz3/       Fassung 3, VERZEICHNIS mit `fassung 3`. Sauber
#                signiert, installiert sich einwandfrei, und das
#                Programm darin KOMMT NICHT HOCH. Dafuer gibt es den
#                Erprobungszaehler.
#   netzfremd/   wie netz2, aber das VERZEICHNIS ist mit einem FREMDEN
#                Ed25519-Schluessel signiert. Muss abgelehnt werden,
#                bevor eine einzige Zeile daraus geglaubt wird.
#   netzman/     wie netz2, aber im VERZEICHNIS ist der Streuwert des
#                Pakets um ein Bit veraendert -- und die Signatur ueber
#                das Verzeichnis ist trotzdem GUELTIG, weil sie nach der
#                Aenderung gerechnet wurde. Das ist der Fall, den eine
#                Kette faengt und eine einzelne Unterschrift nicht.
#   netzbadsig/  wie netz2, das VERZEICHNIS stimmt (Streuwert und Laenge
#                des Pakets sind richtig), aber `hallo-2.opk.sig` ist die
#                Signatur eines ANDEREN Pakets. `ota` laesst das durch --
#                es hat nichts zu beanstanden --, und `opk` faengt es.
#                DIE ZWEITE VERTEIDIGUNGSLINIE, und ohne diesen Fall
#                waere sie unbewiesen.
#
#   bash tools/ota/pakete.sh [ausgabeverzeichnis]
set -uo pipefail
cd "$(dirname "$0")/../.."
ROOT=$(pwd)
OUT=${1:-/tmp/ota}
OPK=${OPK:-/root/orientos-install/pkg/opk.py}
export OPK

[ -f "$OUT/geheim.key" ] || {
    echo "== $OUT/geheim.key fehlt -- erst tools/install/pakete.sh"; exit 1; }
for q in quelle1 quelle2 quelle3; do
    [ -d "$OUT/$q" ] || {
        echo "== $OUT/$q fehlt -- erst tools/install/pakete.sh und tools/update/pakete.sh"
        exit 1; }
done

# Ein FREMDER Signierschluessel, fuer netzfremd/. Er entsteht nur einmal:
# ein zweiter Wurf haette Verzeichnisse signiert, die ein schon gebautes
# Abbild anders beurteilt -- und die Fehlermeldung dafuer saehe aus wie
# ein Angriff und waere ein Werkzeugfehler.
if [ ! -s "$OUT/fremdsig.key" ]; then
    mkdir -p "$OUT/fremdsig"
    python3 "$OPK" schluessel "$OUT/fremdsig" > "$OUT/fremdsig.log" 2>&1 || {
        cat "$OUT/fremdsig.log"; exit 1; }
    cp "$OUT/fremdsig/geheim.key" "$OUT/fremdsig.key"
fi

mach() { # <zielname> <quelle> <fassung>
    rm -rf "$OUT/$1"
    mkdir -p "$OUT/$1"
    cp "$OUT/$2"/* "$OUT/$1/" 2>/dev/null
    rm -f "$OUT/$1/VERZEICHNIS" "$OUT/$1/VERZEICHNIS.sig"
    python3 tools/ota/verzeichnis.py "$OUT/$1" --fassung "$3" \
        --schluessel "$OUT/geheim.key" || exit 1
}

mach netz1 quelle1 1
mach netz2 quelle2 2
mach netz3 quelle3 3

# --- das VERZEICHNIS mit dem FREMDEN Schluessel
rm -rf "$OUT/netzfremd"
mkdir -p "$OUT/netzfremd"
cp "$OUT/quelle2"/* "$OUT/netzfremd/" 2>/dev/null
rm -f "$OUT/netzfremd/VERZEICHNIS" "$OUT/netzfremd/VERZEICHNIS.sig"
python3 tools/ota/verzeichnis.py "$OUT/netzfremd" --fassung 2 \
    --schluessel "$OUT/fremdsig.key" || exit 1

# --- der veraenderte Streuwert IM richtig signierten VERZEICHNIS
rm -rf "$OUT/netzman"
mkdir -p "$OUT/netzman"
cp "$OUT/quelle2"/* "$OUT/netzman/" 2>/dev/null
rm -f "$OUT/netzman/VERZEICHNIS" "$OUT/netzman/VERZEICHNIS.sig"
python3 tools/ota/verzeichnis.py "$OUT/netzman" --fassung 2 \
    --schluessel "$OUT/geheim.key" --kaputt hallo-2.opk || exit 1

# --- richtiges VERZEICHNIS, falsche Paketsignatur
rm -rf "$OUT/netzbadsig"
mkdir -p "$OUT/netzbadsig"
cp "$OUT/quelle2"/* "$OUT/netzbadsig/" 2>/dev/null
rm -f "$OUT/netzbadsig/VERZEICHNIS" "$OUT/netzbadsig/VERZEICHNIS.sig"
# die Signatur der FASSUNG 1 neben das Paket der Fassung 2 legen
cp "$OUT/quelle1/hallo-1.opk.sig" "$OUT/netzbadsig/hallo-2.opk.sig"
python3 tools/ota/verzeichnis.py "$OUT/netzbadsig" --fassung 2 \
    --schluessel "$OUT/geheim.key" || exit 1

for d in netz1 netz2 netz3 netzfremd netzman netzbadsig; do
    echo "   $d  $(ls "$OUT/$d" | wc -l) Dateien, $(du -sb "$OUT/$d" | cut -f1) Oktette"
done
exit 0
