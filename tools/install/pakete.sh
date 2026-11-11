#!/usr/bin/env bash
set -uo pipefail
cd "$(dirname "$0")/../.."
ROOT=$(pwd)
export FIRNLIB="$ROOT/lib"
. tools/lib/firnenv.sh
CC=$FIRNC
OUT=${1:-/tmp/ins}
. "$(git -C "$(dirname "${BASH_SOURCE[0]}")" rev-parse --show-toplevel)/tools/lib/lock.sh" && osum_sperre "$OUT"   # A-024
OPK=${OPK:-$(python3 "$(dirname "${BASH_SOURCE[0]}")/../lib/opkpfad.py")}   # A-025: der alte Ordner war ein Arbeitsbaum

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

rm -rf "$OUT/quelle1" "$OUT/quelle2"
mkdir -p "$OUT/quelle1" "$OUT/quelle2"
cp "$OUT/pak/hallo-1.opk" "$OUT/quelle1/"
cp "$OUT/pak/hallo-2.opk" "$OUT/quelle2/"
if [ ! -s "$OUT/geheim.key" ]; then
    python3 "$OPK" schluessel "$OUT" > "$OUT/schluessel.log" 2>&1 || {
        cat "$OUT/schluessel.log"; exit 1; }
else
    echo "   key is already there ($OUT/geheim.key), will NOT be re-rolled"
fi
for q in quelle1 quelle2; do
    python3 "$OPK" quelle "$OUT/$q" --schluessel "$OUT/geheim.key" \
        > "$OUT/$q.log" 2>&1 || { cat "$OUT/$q.log"; exit 1; }
done

for q in quelle1 quelle2; do
    python3 tools/update/signpak.py "$OUT/geheim.key" "$OUT/$q"/*.opk \
        || exit 1
done
cp "$OUT/oeffentlich.key" "$OUT/schluessel.pub"
echo "   schluessel $OUT/schluessel.pub ($(stat -c%s "$OUT/schluessel.pub") Oktette)"
echo "   pakete    $(ls "$OUT"/pak/*.opk | wc -l), zwei signierte Quellen"
exit 0
