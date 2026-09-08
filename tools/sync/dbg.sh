#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/sync/dbg.sh -- NUR (a) und (g), zum Nachsehen. Kein Testlauf,
# kein Urteil: baut A, B und den Konfliktfall und laesst die Logs stehen.
set -uo pipefail
cd "$(dirname "$0")/../.."
. tools/lib/qemu.sh
ROOT=$(pwd)
export FIRNLIB="$ROOT/lib"
FIRNC=${FIRNC:-vendor/firn/bin/firnc}
BLOCKS=6144
PROGS="sh ls cat echo mkdir rm cp sync tresor backup key bsect"
PASS=eine-lange-passphrase
NP=256
RP=8
TMPD=${DBG_TMP:-/tmp/syncdbg}
rm -rf "$TMPD"; mkdir -p "$TMPD/bin"

bash tools/build-kernel.sh "$TMPD/k0.img" --stufe 0 > "$TMPD/b0.txt" 2>&1 || {
    tail -5 "$TMPD/b0.txt"; exit 1; }
bash tools/sync/build.sh "$TMPD/bin" 0 $PROGS || exit 1

spec_von() {
    local d=$1 pre=$2
    (cd "$d" && find . -mindepth 1 | sed 's|^\./||' | while read -r r; do
        if [ -d "$d/$r" ]; then echo "$pre/$r/"; else echo "$pre/$r=$d/$r"; fi
    done)
}
geraet() {
    local img=$1 skript=$2 kd=$3 sd=$4 dd=$5
    local spec=""
    [ "$kd" != "-" ] && spec="$spec $(spec_von "$kd" /konto)"
    [ "$sd" != "-" ] && spec="$spec $(spec_von "$sd" /store)"
    [ "$dd" != "-" ] && spec="$spec $(spec_von "$dd" /daten)"
    python3 tools/osum/mkfs.py build "$img" $BLOCKS \
        /bin/ /t/ /proc/ /dev/ /konto/ /store/ /daten/ /tresor/ /system/ \
        $(for p in $PROGS; do echo "/bin/$p=$TMPD/bin/$p.elf"; done) \
        /t/s.sh="$skript" $spec > "$TMPD/mkfs.txt" 2>&1 || cat "$TMPD/mkfs.txt"
}
lauf() { bash tools/sync/lauf.sh "$TMPD/k0.img" "$1" "$TMPD/$2.txt" /t/s.sh; }
klar() { tr -cd '\11\12\15\40-\176' < "$TMPD/$1.txt"; }
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

mkdir -p "$TMPD/daten/unter"
printf 'die erste zeile\nGEHEIMNIS-4711 steht hier\n' > "$TMPD/daten/a.txt"
head -c 9000 /dev/urandom > "$TMPD/daten/unter/b.bin"
printf 'hallo\n' > "$TMPD/daten/klein.txt"
printf '100 farbe blau\n100 sprache de\n' > "$TMPD/daten/EINST"

cat > "$TMPD/sA.sh" <<EOS
sync neu /konto $PASS eigen /store $NP $RP
sync abgleich /konto /daten $PASS
echo ==END==
EOS
geraet "$TMPD/A.img" "$TMPD/sA.sh" - - "$TMPD/daten"
lauf "$TMPD/A.img" A > /dev/null
echo "--- A ---"; klar A | tail -20
hol "$TMPD/A.img" /store "$TMPD/store1"
hol "$TMPD/A.img" /konto "$TMPD/kontoA"
echo "--- kontoA ---"; ls -la "$TMPD/kontoA"
echo "--- BASIS ---"; cat "$TMPD/kontoA/BASIS" 2>/dev/null | cut -c1-90

mkdir -p "$TMPD/kontoB" "$TMPD/leer"
cp "$TMPD/kontoA/KOPF" "$TMPD/kontoB/KOPF"
cat > "$TMPD/sG1.sh" <<EOS
sync abgleich /konto /daten $PASS
echo VON-B > /daten/a.txt
sync abgleich /konto /daten $PASS
echo ==END==
EOS
geraet "$TMPD/G1.img" "$TMPD/sG1.sh" "$TMPD/kontoB" "$TMPD/store1" "$TMPD/leer"
lauf "$TMPD/G1.img" G1 > /dev/null
echo "--- G1 (B) ---"; klar G1 | tail -30
hol "$TMPD/G1.img" /store "$TMPD/store2"
hol "$TMPD/G1.img" /daten "$TMPD/datenG1"
echo "--- B a.txt ---"; cat "$TMPD/datenG1/a.txt"

cat > "$TMPD/sG2.sh" <<EOS
echo VON-A > /daten/a.txt
cat /daten/a.txt
sync abgleich /konto /daten $PASS
echo ==KONF==
sync konflikte /konto
echo ==A==
cat /daten/a.txt
echo ==K==
cat /daten/a.txt.konflikt
echo ==END==
EOS
geraet "$TMPD/G2.img" "$TMPD/sG2.sh" "$TMPD/kontoA" "$TMPD/store2" "$TMPD/daten"
lauf "$TMPD/G2.img" G2 > /dev/null
echo "--- G2 (A) ---"; klar G2 | tail -40
hol "$TMPD/G2.img" /daten "$TMPD/datenG2"
echo "--- A Baum ---"; ls -la "$TMPD/datenG2"
