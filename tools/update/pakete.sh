#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/update/pakete.sh -- die Pakete, die RUNDE UPDATE zusaetzlich
# braucht, und sie sind fast alle kaputt.
#
# `tools/install/pakete.sh` baut zwei ordentliche, signierte Quellen.
# Diese Runde misst die andere Haelfte: was passiert, wenn eine Signatur
# FEHLT, FALSCH ist, oder ueber einen anderen INDEX gerechnet wurde -- und
# was passiert, wenn ein Update sauber signiert ist und trotzdem nicht
# hochkommt. Ein Signaturweg, von dem nur der positive Fall gemessen ist,
# ist nicht gemessen.
#
# Was entsteht (unter $OUT):
#
#   quelle3/       Fassung 3 des Probepakets, richtig signiert. Das
#                  PROGRAMM darin beendet sich mit Code 1 -- ein Update,
#                  das sich einwandfrei installiert und danach NICHT
#                  laeuft. Dafuer gibt es den Erprobungszaehler.
#   boese/hallo-1.opk        ohne .sig      -> muss abgelehnt werden
#   boese/verdreht.opk       mit der Signatur des UNVERAENDERTEN Pakets,
#                            aber einem gekippten Oktett IM ARCHIV
#                            -> muss abgelehnt werden
#   boese/INDEX, INDEX.sig   der INDEX von quelle1, um eine Zeile
#                            veraendert, mit der ALTEN Signatur
#                            -> die Quelle muss abgelehnt werden
#   fremd.pub                ein ANDERER oeffentlicher Schluessel, fuer
#                            die Gegenprobe "richtige Signatur, falscher
#                            Schluessel"
#
#   bash tools/update/pakete.sh [ausgabeverzeichnis]
set -uo pipefail
cd "$(dirname "$0")/../.."
ROOT=$(pwd)
export FIRNLIB="$ROOT/lib"
CC=${FIRNC:-vendor/firn/bin/firnc}
OUT=${1:-/tmp/upd}
. "$(git -C "$(dirname "${BASH_SOURCE[0]}")" rev-parse --show-toplevel)/tools/lib/sperre.sh" && osum_sperre "$OUT"   # A-024
OPK=${OPK:-/root/orientos-install/pkg/opk.py}

[ -f "$OUT/geheim.key" ] || { echo "== $OUT/geheim.key fehlt -- erst tools/install/pakete.sh"; exit 1; }

mkdir -p "$OUT/quelle3" "$OUT/boese"
as --64 -o "$OUT/crt.o" kernel/user/crt.s || exit 1

# ---------------------------------------------------------- Fassung 3
"$CC" kernel/user/hallo3.fi -o "$OUT/h3.o" > "$OUT/h3.err" 2>&1 || {
    echo "== h3: der Uebersetzer sagt nein"; head -10 "$OUT/h3.err"; exit 1; }
ld -T kernel/user/user.ld --defsym=USER_ENTRY=_F0.u_start \
   -o "$OUT/h3.elf" "$OUT/crt.o" "$OUT/h3.o" || exit 1
strip --strip-all "$OUT/h3.elf"
sed "s#H3ELF#$OUT/h3.elf#" tools/update/hallo3.rezept > "$OUT/hallo3.rezept"
rm -f "$OUT/quelle3"/*
python3 "$OPK" bauen "$OUT/hallo3.rezept" -o "$OUT/quelle3/hallo-3.opk" || exit 1
python3 "$OPK" quelle "$OUT/quelle3" --schluessel "$OUT/geheim.key" \
    > "$OUT/quelle3.log" 2>&1 || { cat "$OUT/quelle3.log"; exit 1; }
python3 tools/update/signpak.py "$OUT/geheim.key" "$OUT/quelle3"/*.opk || exit 1

# ---------------------------------------------------------- die boesen
rm -f "$OUT/boese"/*
# 1. ohne Signatur
cp "$OUT/quelle1/hallo-1.opk" "$OUT/boese/ohnesig.opk"
# 2. ein gekipptes Oktett IM ARCHIV, mit der Signatur des Originals.
#    Das Oktett liegt weit hinten, mitten in den Daten -- und zwar so,
#    dass die SHA-256 im Kopf danach ebenfalls nicht mehr passt. Beides
#    ist Absicht: geprueft wird, dass die SIGNATUR zuerst zuschlaegt.
cp "$OUT/quelle1/hallo-1.opk" "$OUT/boese/verdreht.opk"
cp "$OUT/quelle1/hallo-1.opk.sig" "$OUT/boese/verdreht.opk.sig"
python3 - "$OUT/boese/verdreht.opk" <<'EOF'
import sys
f = open(sys.argv[1], "r+b")
f.seek(20000)
b = f.read(1)
f.seek(20000)
f.write(bytes([b[0] ^ 0x40]))
f.close()
EOF
# 3. ein veraenderter INDEX mit der alten Signatur
cp "$OUT/quelle1/hallo-1.opk" "$OUT/boese/hallo-1.opk"
cp "$OUT/quelle1/hallo-1.opk.sig" "$OUT/boese/hallo-1.opk.sig"
cp "$OUT/quelle1/INDEX.sig" "$OUT/boese/INDEX.sig"
python3 - "$OUT/quelle1/INDEX" "$OUT/boese/INDEX" <<'EOF'
import sys
z = open(sys.argv[1]).read()
# denselben Namen, einen anderen Streuwert: genau das, was ein
# Angreifer eintraege, der ein eigenes Paket unterschieben will.
f = z.split("\t")
f[2] = "0" * 64
open(sys.argv[2], "w").write("\t".join(f))
EOF

# ---------------------------------------------------------- fremder Schluessel
mkdir -p "$OUT/fremd"
python3 "$OPK" schluessel "$OUT/fremd" > "$OUT/fremd.log" 2>&1 || {
    cat "$OUT/fremd.log"; exit 1; }
cp "$OUT/fremd/oeffentlich.key" "$OUT/fremd.pub"

echo "   quelle3   $(ls "$OUT/quelle3" | wc -l) Dateien (Fassung 3, signiert, scheitert beim Start)"
echo "   boese     $(ls "$OUT/boese" | wc -l) Dateien"
echo "   fremd.pub $(stat -c%s "$OUT/fremd.pub") Oktette"
exit 0
