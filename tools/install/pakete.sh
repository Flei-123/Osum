#!/usr/bin/env bash
# tools/install/pakete.sh -- ZWEI FASSUNGEN EINES PAKETS UND ZWEI
# SIGNIERTE QUELLEN, gebaut mit dem Werkzeug des Wirts.
#
# WARUM DER WIRT SIE BAUT UND NICHT OSUM. `opk bauen` ist die Seite, die
# ein Entwickler benutzt; `opk installieren` die, die auf dem Geraet
# laeuft. Diese Runde baut die zweite. Dass die erste weiter auf dem Wirt
# steht, ist keine Luecke, sondern die Arbeitsteilung, die jede
# Distribution hat -- und sie ist ausserdem der bessere Nachweis: was
# hier entsteht, hat Osum NIE gesehen, und trotzdem muss es dort
# hineinpassen, Oktett fuer Oktett.
#
#   bash tools/install/pakete.sh [ausgabeverzeichnis]
set -uo pipefail
cd "$(dirname "$0")/../.."
ROOT=$(pwd)
export FIRNLIB="$ROOT/lib"
CC=${FIRNC:-vendor/firn/bin/firnc}
OUT=${1:-/tmp/ins}
OPK=${OPK:-/root/orientos-install/pkg/opk.py}

mkdir -p "$OUT/pak" "$OUT/quelle1" "$OUT/quelle2"
as --64 -o "$OUT/crt.o" kernel/user/crt.s || exit 1
for v in 1 2; do
    "$CC" "kernel/user/hallo$v.fi" -o "$OUT/h$v.o" > "$OUT/h$v.err" 2>&1 || {
        echo "== h$v: der Uebersetzer sagt nein"; head -10 "$OUT/h$v.err"; exit 1; }
    ld -T kernel/user/user.ld --defsym=USER_ENTRY=_F0.u_start \
       -o "$OUT/h$v.elf" "$OUT/crt.o" "$OUT/h$v.o" || exit 1
    strip --strip-all "$OUT/h$v.elf"
    sed "s#H${v}ELF#$OUT/h$v.elf#" "tools/install/hallo$v.rezept" \
        > "$OUT/hallo$v.rezept"
    python3 "$OPK" bauen "$OUT/hallo$v.rezept" -o "$OUT/pak/hallo-$v.opk" \
        || exit 1
done

# ZWEI QUELLEN, damit „aktualisieren" wirklich etwas zu holen hat: die
# erste traegt Fassung 1, die zweite Fassung 2. Jede bekommt ihren
# eigenen INDEX und ihre eigene Signatur.
rm -rf "$OUT/quelle1" "$OUT/quelle2"
mkdir -p "$OUT/quelle1" "$OUT/quelle2"
cp "$OUT/pak/hallo-1.opk" "$OUT/quelle1/"
cp "$OUT/pak/hallo-2.opk" "$OUT/quelle2/"
python3 "$OPK" schluessel "$OUT" > "$OUT/schluessel.log" 2>&1 || {
    cat "$OUT/schluessel.log"; exit 1; }
for q in quelle1 quelle2; do
    python3 "$OPK" quelle "$OUT/$q" --schluessel "$OUT/geheim.key" \
        > "$OUT/$q.log" 2>&1 || { cat "$OUT/$q.log"; exit 1; }
done
echo "   pakete    $(ls "$OUT"/pak/*.opkg | wc -l), zwei signierte Quellen"
exit 0
