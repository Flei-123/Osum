#!/usr/bin/env bash
set -uo pipefail
cd "$(dirname "$0")/../.."
ROOT=$(pwd)
OUT=${1:-/tmp/laden}
. "$(git -C "$(dirname "${BASH_SOURCE[0]}")" rev-parse --show-toplevel)/tools/lib/lock.sh" && osum_sperre "$OUT"   # A-024
OPK=${OPK:-$(python3 "$(dirname "${BASH_SOURCE[0]}")/../lib/opkpfad.py")}   # A-025: der alte Ordner war ein Arbeitsbaum
TAB=tools/loader/apps.tab

[ -d "$OUT/bin" ] || { echo "== $OUT/bin fehlt -- erst tools/loader/build.sh"; exit 1; }
rm -rf "$OUT/stand" "$OUT/info" "$OUT/symbole" "$OUT/rezepte"
mkdir -p "$OUT/stand" "$OUT/info" "$OUT/symbole" "$OUT/rezepte"
rm -rf "$OUT/registry"
python3 tools/appreg/build.py "$ROOT" "$OUT/registry" || exit 1

n=0
while IFS='|' read -r paket programm fassung titel info keys art; do
    case "${paket:-}" in ""|\#*) continue ;; esac
    prog="$OUT/bin/$programm"
    if [ ! -x "$prog" ] && [ "$paket" = certus ]; then
        echo "   certus    uebersprungen (kein /bin/certus gebaut)"
        continue
    fi
    [ -x "$prog" ] || { echo "== $prog is missing -- tools/loader/build.sh builds it"; exit 1; }

    {
        echo "# /apps/$paket.osp/INFO -- built from tools/loader/apps.tab."
        echo "name=$titel"
        echo "info=$info"
        echo "keys=$keys"
        echo "revision=${fassung%%.*}"
    } > "$OUT/info/$paket"

    cp "$OUT/registry/usr/share/appreg/$paket/symbol" "$OUT/symbole/$paket" || {
        echo "== no registry symbol for $paket"; exit 1; }

    {
        echo "# Round LOADER, generated from tools/loader/apps.tab -- do not edit by hand."
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
