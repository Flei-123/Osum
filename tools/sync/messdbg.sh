#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/sync/messdbg.sh -- NUR die Messstrecke, und der Arbeitsordner
# bleibt stehen. Kein Urteil, keine Zusagen: drei Abgleiche ueber 20
# Dateien, danach liegt alles zum Nachsehen unter $TMPD.
#
#   bash tools/sync/messdbg.sh [anzahl] [groesse] [blocks]
set -uo pipefail
cd "$(dirname "$0")/../.."
. tools/lib/qemu.sh
ROOT=$(pwd)
export FIRNLIB="$ROOT/lib"
FIRNC=${FIRNC:-vendor/firn/bin/firnc}
N=${1:-20}
GR=${2:-51200}
BLOCKS=${3:-16384}
PROGS="sh ls cat echo mkdir rm cp sync"
PASS=eine-lange-passphrase
NP=256
RP=8
TMPD=${MESS_TMP:-/tmp/syncmess}
rm -rf "$TMPD"; mkdir -p "$TMPD/bin"

bash tools/build-kernel.sh "$TMPD/k0.img" --stufe 0 > "$TMPD/b0.txt" 2>&1 || {
    tail -5 "$TMPD/b0.txt"; exit 1; }
bash tools/sync/build.sh "$TMPD/bin" 0 $PROGS || exit 1

mkdir -p "$TMPD/mess"
i=0
while [ $i -lt "$N" ]; do
    head -c "$GR" /dev/urandom > "$TMPD/mess/m$i.bin"
    i=$((i+1))
done

spec_von() {
    local d=$1 pre=$2
    (cd "$d" && find . -mindepth 1 | sed 's|^\./||' | while read -r r; do
        if [ -d "$d/$r" ]; then echo "$pre/$r/"; else echo "$pre/$r=$d/$r"; fi
    done)
}
geraet() {
    local img=$1 skript=$2 dd=$3
    local spec=""
    [ "$dd" != "-" ] && spec="$spec $(spec_von "$dd" /daten)"
    python3 tools/osum/mkfs.py build "$img" $BLOCKS \
        /bin/ /t/ /proc/ /dev/ /konto/ /store/ /daten/ /system/ \
        $(for p in $PROGS; do echo "/bin/$p=$TMPD/bin/$p.elf"; done) \
        /t/s.sh="$skript" $spec > "$TMPD/mkfs.txt" 2>&1 || cat "$TMPD/mkfs.txt"
}
hol() {
    local img=$1 pre=$2 ziel=$3
    rm -rf "$ziel"; mkdir -p "$ziel"
    python3 tools/osum/mkfs.py list "$img" 2>/dev/null | awk '{print $1}' \
    | grep "^$pre/" | while read -r p; do
        local rel=${p#"$pre/"}
        if [ "${p%/}" != "$p" ]; then mkdir -p "$ziel/${rel%/}"
        else mkdir -p "$ziel/$(dirname "$rel")"
             python3 tools/osum/mkfs.py cat "$img" "$p" > "$ziel/$rel" 2>/dev/null
        fi
    done
}

cat > "$TMPD/sM.sh" <<EOS
sync neu /konto $PASS eigen /store $NP $RP
echo ==VOLL==
sync abgleich /konto /daten $PASS
echo ==NOCHMAL==
sync abgleich /konto /daten $PASS
echo ==KLEIN==
echo eine-kleine-aenderung > /daten/m0.bin
sync abgleich /konto /daten $PASS
echo ==LS==
ls /store
echo ==END==
EOS
geraet "$TMPD/M.img" "$TMPD/sM.sh" "$TMPD/mess"
SYNC_TIMEOUT=1800 bash tools/sync/lauf.sh "$TMPD/k0.img" "$TMPD/M.img" \
    "$TMPD/M.txt" /t/s.sh > /dev/null
tr -cd '\11\12\15\40-\176' < "$TMPD/M.txt" > "$TMPD/M.log"

echo "===== was das Programm gesagt hat ====="
sed -n '/^==VOLL==/,/^==END==/p' "$TMPD/M.log"
echo "===== der Speicher auf dem Wirt ====="
hol "$TMPD/M.img" /store "$TMPD/storeM"
ls -la "$TMPD/storeM"
echo "PACK $(stat -c%s "$TMPD/storeM/PACK" 2>/dev/null)"
echo "INDEX $(stat -c%s "$TMPD/storeM/INDEX" 2>/dev/null) Zeilen $(wc -l < "$TMPD/storeM/INDEX" 2>/dev/null)"
echo "Klartext $(du -sb "$TMPD/mess" | cut -f1) ($N x $GR)"
echo "erwartet je Datei $(( (GR + 4095) / 4096 )) Bloecke, zusammen $(( N * ((GR + 4095) / 4096) ))"
echo "Arbeitsordner bleibt: $TMPD"
