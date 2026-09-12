#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/module/paket.sh -- DEN TREIBER AUSLIEFERN, wie Justin es sich
# vorstellt: "Treiber herunterladen" -- nur aus seinem eigenen Speicher.
#
# DIE KETTE, ganz, von der Quelldatei bis zum Gerät:
#
#   module/ps2maus.fi
#        │  tools/module/build.sh          (firnc, strip, Kopf, Ed25519)
#        ▼
#   ps2maus.omod                        ← das, was der KERN prueft
#        │  pkg/opk.py bauen            (OrientOS-Paketformat)
#        ▼
#   ps2maus-1.0.0.opk                   ← das, was OPK installiert
#        │  werkzeug/store add          (Orient-Speicher)
#        ▼
#   speicher/index.json + index.json.sig
#        │  store publish → https://store.fleitec.com/
#        ▼
#   opk installieren /store/…/ps2maus-1.0.0.opk
#        │
#        ▼
#   /lib/ps2maus.omod  auf der Platte -- und der Kern laedt es
#
# DREI SIGNATUREN, DREI VERSCHIEDENE FRAGEN, und das ist kein Zufall:
#
#   1. Ed25519 ueber die `.omod`     -- "darf dieser Programmtext in
#      (kernel/module.fi, Schluessel     Ring 0?" Prueft DER KERN,
#      im Kernabbild)                  jedes Mal beim Laden.
#   2. Ed25519 ueber die `.opk`      -- "kommt dieses Paket von mir?"
#      (kernel/user/opk.fi,             Prueft OPK, einmal beim
#      Runde UPDATE)                    Installieren.
#   3. Ed25519 ueber `index.json`    -- "ist dieser Katalog echt?"
#      (orientstore, Schluessel in       Prueft der Speicher-Client,
#      die App einkompiliert)           bei jedem Abgleich.
#
# Eine davon wegzulassen waere jedes Mal eine andere Luecke. Windows hat
# an derselben Stelle ebenfalls zwei getrennte Huerden -- Code Integrity
# beim LADEN und die PnP-Signatur beim INSTALLIEREN
# (docs/MODUL-BEFUND.md, Abschnitt 1.5).
#
#   bash tools/module/paket.sh [ausgabeverzeichnis] [--fassung X.Y.Z]
set -uo pipefail
cd "$(dirname "$0")/../.."
ROOT=$(pwd)

OUT=${1:-/tmp/modulpaket}
shift || true
FASSUNG=1.0.0
while [[ $# -gt 0 ]]; do
    case "$1" in
        --fassung) FASSUNG=$2; shift 2 ;;
        *) shift ;;
    esac
done

OPK=${OPK:-/root/orientos-install/pkg/opk.py}
STORE=${STORE:-/root/orientstore/werkzeug/store}

mkdir -p "$OUT"
echo "== 1. das Modul bauen und signieren =="
bash tools/module/build.sh "$OUT/ps2maus.omod" --name ps2maus --abi 1 \
    | sed 's/^/   /' || exit 1

echo "== 2. daraus ein OrientOS-Paket =="
cat > "$OUT/ps2maus.rezept" <<REZEPT
# Der Treiber fuer das Zeigegeraet am 8042, als NACHLADBARES Kernmodul.
#
# Die Nutzlast ist genau eine Datei: das signierte \`.omod\`. Sie landet
# auf dem Geraet unter /lib/ps2maus.omod, und dort sucht sie
# \`kernel/module.fi\`.
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
echo "    osum\$ opk installieren /store/ps2maus-$FASSUNG.opk"
echo "    opk: installiert ps2maus $FASSUNG"
echo "    osum\$ ls /lib"
echo "    ps2maus.omod"
echo "    (Neustart -- und der Kern findet den Treiber.)"
