#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/operation/vorbereiten.sh -- alles, was VOR den Messungen entsteht:
# Pakete, Zertifikate, der Schluesselbund, vier Auslieferungen, das
# Abbild und eine Platte, auf der Fassung 1 laeuft.
#
#   bash tools/operation/vorbereiten.sh [ausgabeverzeichnis]
#
# Das dauert (Bau plus Installation in QEMU) und wird deshalb einmal
# gemacht; `tools/operation/run.sh` benutzt danach `$OUT/basis.img`.
set -uo pipefail
cd "$(dirname "$0")/../.."
ROOT=$(pwd)
export FIRNLIB="$ROOT/lib"
OUT=${1:-/tmp/betrieb-run}
mkdir -p "$OUT"
export OUT
export OSUM_CPU=${OSUM_CPU:-Haswell}
export OSUM_SIGN_PASS=${OSUM_SIGN_PASS:-passwort-haupt-4711}
export OSUM_ERSATZ_PASS=${OSUM_ERSATZ_PASS:-passwort-ersatz-0815}
PORT=${BETRIEB_PORT:-18443}
NAME=${BETRIEB_NAME:-pkg.betrieb.test}

echo "== 0. der Uebersetzer"
bash vendor/firn/fetch-firnc.sh > "$OUT/firnc.log" 2>&1 || {
    tail -5 "$OUT/firnc.log"; exit 1; }

echo "== 1. Pakete (Fassung 1, 2, 3) und Zertifikate auf $NAME"
bash tools/install/pakete.sh "$OUT" > "$OUT/pak1.log" 2>&1 || {
    tail -5 "$OUT/pak1.log"; exit 1; }
bash tools/update/pakete.sh "$OUT" > "$OUT/pak2.log" 2>&1 || {
    tail -5 "$OUT/pak2.log"; exit 1; }
python3 tools/ota/mkcerts.py "$OUT/certs" "$NAME" 10.0.2.2 \
    > "$OUT/certs.log" 2>&1 || { cat "$OUT/certs.log"; exit 1; }

echo "== 2. der Schluesselbund"
# Der Hauptschluessel ist DERSELBE, mit dem `tools/install/pakete.sh`
# die Pakete signiert hat -- sonst muesste entweder das Abbild einen
# zweiten Vertrauensanker tragen oder die Pakete neu signiert werden,
# und beides waere eine Aenderung an dem, was gemessen wird.
rm -f "$OUT/bund.json" "$OUT/fremd.json"
python3 tools/ota/schluesselbund.py "$OUT/bund.json" anlegen \
    --aus "$OUT/geheim.key" || exit 1
OSUM_SIGN_PASS=fremd1 OSUM_ERSATZ_PASS=fremd2 \
    python3 tools/ota/schluesselbund.py "$OUT/fremd.json" anlegen || exit 1
python3 tools/ota/schluesselbund.py "$OUT/bund.json" oeffentlich ersatz \
    -o "$OUT/ersatz.pub" || exit 1

echo "== 3. vier Auslieferungen (1..4) aus dem Register"
rm -rf "$OUT/aus" "$OUT/stand"
mkdir -p "$OUT/stand"
for f in 1 2 3 2; do
    rm -f "$OUT/stand"/*.opk
    cp "$OUT/quelle$f/hallo-$f.opk" "$OUT/stand/"
    python3 tools/ota/veroeffentlichen.py "$OUT/aus" --stand "$OUT/stand" \
        --bund "$OUT/bund.json" --notiz "hallo-$f" 2>&1 | grep -v signiert
done

echo "== 4. das Abbild (mit Ersatzschluessel)"
cat > "$OUT/ota.conf" <<EOF
quelle=https://$NAME:$PORT
abstand=3600
auto=nein
frist=15
EOF
# DIE EINTRAGUNG VON HAND. Genau das verlangt der Auftrag neben DHCP:
# ein Nameserver, den ein Mensch hingeschrieben hat. 10.0.2.2 ist in
# QEMUs Benutzernetz der Wirt, und dort laeuft `tools/operation/dnsdienst.py`.
cat > "$OUT/resolv.conf" <<EOF
# von Hand eingetragen
nameserver 10.0.2.2
options timeout:3 attempts:2
EOF
printf 'opk richten\nif /apps/hallo.osp/start\nthen\nota bestaetigen\nfi\nopk erprobung\n' \
    > "$OUT/start.sh"
EX="/start.sh=$OUT/start.sh /etc/resolv.conf=$OUT/resolv.conf"
OTA_ROOTS="$OUT/certs/ca.pem" OTA_CONF="$OUT/ota.conf" EXTRA="$EX" \
    OTA_ERSATZ="$OUT/ersatz.pub" ZIEL_MIB=96 \
    bash tools/install/build.sh "$OUT" > "$OUT/build.log" 2>&1 \
    || { tail -25 "$OUT/build.log"; exit 1; }
grep -a 'ersatz\|apps \|programme' "$OUT/build.log"

echo "== 5. die leere Platte und die Installation"
rm -f "$OUT/ziel.img"
head -c $((96 * 1024 * 1024)) /dev/zero > "$OUT/ziel.img"
OUT="$OUT" bash tools/install/oneshot.sh inst iso "install /dev/hda --ja;exit" 900 \
    > /dev/null 2>&1
echo "   installer rc=$(cat "$OUT/inst.rc" 2>/dev/null) $(grep -ac 'install: fertig' "$OUT/inst.txt")"

echo "== 6. ein Startlauf -- kommt die Maschine hoch, steht das Netz"
OTA_NETZ="nic nip=10.0.2.15/24 ngw=10.0.2.2 nsvc=0 nwait=0" OUT="$OUT" \
    bash tools/install/oneshot.sh basis0 platte \
    "ota zeigen;cat /etc/resolv.conf;exit" 600 \
    > /dev/null 2>&1
sed -i -e 's/\x1b\[[0-9;=]*[a-zA-Z]//g' "$OUT/basis0.txt" 2>/dev/null
grep -a 'ota: fassung hier\|ota: schluesselgen\|ersatzschluessel\|nameserver' \
    "$OUT/basis0.txt" | head -6
cp -f "$OUT/ziel.img" "$OUT/basis.img"

# DER SCHNAPPSCHUSS. `run.sh` veroeffentlicht Fassungen und wechselt
# Schluessel; damit ein zweiter Lauf dieselben Zahlen ergibt wie der
# erste, stellt er von hier wieder her.
rm -rf "$OUT/rein"
mkdir -p "$OUT/rein"
cp -a "$OUT/aus" "$OUT/rein/aus"
cp -a "$OUT/bund.json" "$OUT/rein/bund.json"
echo "== fertig: $OUT/basis.img (Schnappschuss unter $OUT/rein)"
