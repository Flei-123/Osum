#!/usr/bin/env bash
#
#   bash tools/ota/pakete.sh [ausgabeverzeichnis]
set -uo pipefail
cd "$(dirname "$0")/../.."
ROOT=$(pwd)
OUT=${1:-/tmp/ota}
. "$(git -C "$(dirname "${BASH_SOURCE[0]}")" rev-parse --show-toplevel)/tools/lib/sperre.sh" && osum_sperre "$OUT"   # A-024
OPK=${OPK:-$(python3 "$(dirname "${BASH_SOURCE[0]}")/../lib/opkpfad.py")}   # A-025: der alte Ordner war ein Arbeitsbaum
export OPK

[ -f "$OUT/geheim.key" ] || {
    echo "== $OUT/geheim.key fehlt -- erst tools/install/pakete.sh"; exit 1; }
for q in quelle1 quelle2 quelle3; do
    [ -d "$OUT/$q" ] || {
        echo "== $OUT/$q fehlt -- erst tools/install/pakete.sh und tools/update/pakete.sh"
        exit 1; }
done

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
    python3 tools/ota/listing.py "$OUT/$1" --fassung "$3" \
        --schluessel "$OUT/geheim.key" || exit 1
}

mach netz1 quelle1 1
mach netz2 quelle2 2
mach netz3 quelle3 3

rm -rf "$OUT/netzfremd"
mkdir -p "$OUT/netzfremd"
cp "$OUT/quelle2"/* "$OUT/netzfremd/" 2>/dev/null
rm -f "$OUT/netzfremd/VERZEICHNIS" "$OUT/netzfremd/VERZEICHNIS.sig"
python3 tools/ota/listing.py "$OUT/netzfremd" --fassung 2 \
    --schluessel "$OUT/fremdsig.key" || exit 1

rm -rf "$OUT/netzman"
mkdir -p "$OUT/netzman"
cp "$OUT/quelle2"/* "$OUT/netzman/" 2>/dev/null
rm -f "$OUT/netzman/VERZEICHNIS" "$OUT/netzman/VERZEICHNIS.sig"
python3 tools/ota/listing.py "$OUT/netzman" --fassung 2 \
    --schluessel "$OUT/geheim.key" --kaputt hallo-2.opk || exit 1

# --- richtiges VERZEICHNIS, falsche Paketsignatur
rm -rf "$OUT/netzbadsig"
mkdir -p "$OUT/netzbadsig"
cp "$OUT/quelle2"/* "$OUT/netzbadsig/" 2>/dev/null
rm -f "$OUT/netzbadsig/VERZEICHNIS" "$OUT/netzbadsig/VERZEICHNIS.sig"
cp "$OUT/quelle1/hallo-1.opk.sig" "$OUT/netzbadsig/hallo-2.opk.sig"
python3 tools/ota/listing.py "$OUT/netzbadsig" --fassung 2 \
    --schluessel "$OUT/geheim.key" || exit 1

GROSS_MIB=${OTA_GROSS_MIB:-60}
if [ ! -s "$OUT/gross.bin" ]; then
    head -c $((GROSS_MIB * 1024 * 1024)) /dev/urandom > "$OUT/gross.bin"
fi
rm -rf "$OUT/netzvoll" "$OUT/grossbau"
mkdir -p "$OUT/netzvoll" "$OUT/grossbau"
cat > "$OUT/gross.rezept" <<EOF
# Ein Paket, das absichtlich zu gross fuer die Platte des Pruefstands ist.
name=gross
fassung=1.0.0
titel=Gross
info=Ein Paket, das nicht auf die Platte passt -- fuer den Fall "kein Platz"
keys=gross,test
handle=konsole
datei=nutzlast $OUT/gross.bin
EOF
python3 "$OPK" bauen "$OUT/gross.rezept" -o "$OUT/netzvoll/gross-1.opk" \
    > "$OUT/gross.log" 2>&1 || { cat "$OUT/gross.log"; exit 1; }
python3 "$OPK" quelle "$OUT/netzvoll" --schluessel "$OUT/geheim.key" \
    >> "$OUT/gross.log" 2>&1 || { cat "$OUT/gross.log"; exit 1; }
python3 tools/update/signpak.py "$OUT/geheim.key" "$OUT/netzvoll"/*.opk \
    >> "$OUT/gross.log" 2>&1 || { cat "$OUT/gross.log"; exit 1; }
python3 tools/ota/listing.py "$OUT/netzvoll" --fassung 2 \
    --schluessel "$OUT/geheim.key" || exit 1

for d in netz1 netz2 netz3 netzfremd netzman netzbadsig netzvoll; do
    echo "   $d  $(ls "$OUT/$d" | wc -l) Dateien, $(du -sb "$OUT/$d" | cut -f1) Oktette"
done
exit 0
