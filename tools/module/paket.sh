#!/usr/bin/env bash
set -uo pipefail
cd "$(dirname "$0")/../.."
ROOT=$(pwd)

OUT=${1:-/tmp/modulpaket}
. "$(git -C "$(dirname "${BASH_SOURCE[0]}")" rev-parse --show-toplevel)/tools/lib/sperre.sh" && osum_sperre "$OUT"   # A-024
shift || true
FASSUNG=1.0.0
while [[ $# -gt 0 ]]; do
    case "$1" in
        --fassung) FASSUNG=$2; shift 2 ;;
        *) shift ;;
    esac
done

OPK=${OPK:-$(python3 "$(dirname "${BASH_SOURCE[0]}")/../lib/opkpfad.py")}   # A-025: der alte Ordner war ein Arbeitsbaum
STORE=${STORE:-/root/orientstore/werkzeug/store}

mkdir -p "$OUT"
echo "== 1. das Modul bauen und signieren =="
bash tools/module/build.sh "$OUT/ps2maus.omod" --name ps2maus --abi 1 \
    | sed 's/^/   /' || exit 1

echo "== 2. daraus ein Paket =="
cat > "$OUT/ps2maus.rezept" <<REZEPT
name=ps2maus
fassung=$FASSUNG
titel=Zeigegeraet (PS/2, 8042)
info=Nachladbarer Kerntreiber fuer die Maus am zweiten Anschluss des 8042. Braucht einen Kern mit Modulschnittstelle 1.
keys=maus,zeiger,ps2,8042,treiber,modul
datei=lib/ps2maus.omod $OUT/ps2maus.omod
REZEPT
if [ ! -x "$OPK" ] && [ ! -f "$OPK" ]; then
    echo "   opk.py fehlt ($OPK) -- Schritt 2 und 3 werden uebersprungen"
    exit 0
fi
python3 "$OPK" bauen "$OUT/ps2maus.rezept" -o "$OUT/ps2maus-$FASSUNG.opk" \
    | sed 's/^/   /' || exit 1
python3 "$OPK" zeigen "$OUT/ps2maus-$FASSUNG.opk" | sed 's/^/   /'

echo "== 3. in den Speicher legen =="
if [ ! -f "$STORE" ]; then
    echo "   werkzeug/store fehlt ($STORE) -- Schritt 3 wird uebersprungen"
    exit 0
fi
REPO="$OUT/speicher"
rm -rf "$REPO"
python3 "$STORE" --repo "$REPO" init --name "Justins Speicher" \
    --adresse "https://store.fleitec.com/" 2>&1 | sed 's/^/   /'
python3 "$STORE" --repo "$REPO" add "$OUT/ps2maus-$FASSUNG.opk" 2>&1 | sed 's/^/   /'
echo "-- der Katalog --"
python3 "$STORE" --repo "$REPO" list 2>&1 | sed 's/^/   /'
echo "-- die Pruefung des ganzen Katalogs gegen sich selbst --"
python3 "$STORE" --repo "$REPO" verify --tief 2>&1 | sed 's/^/   /'
echo "-- der Eintrag, wie er im index.json steht --"
python3 - "$REPO/index.json" <<'PY' | sed 's/^/   /'
import json, sys
d = json.load(open(sys.argv[1]))
print(json.dumps({k: v for k, v in d.items() if k != "pakete"},
                 indent=2, ensure_ascii=False, sort_keys=True))
for k, v in d["pakete"].items():
    print('"%s": %s' % (k, json.dumps(v, indent=2, ensure_ascii=False,
                                      sort_keys=True)))
PY
echo
echo "So sieht es auf dem Geraet aus:"
echo "    osum\$ opk install /store/ps2maus-$FASSUNG.opk"
echo "    opk: installed ps2maus $FASSUNG"
echo "    osum\$ ls /lib"
echo "    ps2maus.omod"
echo "    (Neustart -- und der Kern findet den Treiber.)"
