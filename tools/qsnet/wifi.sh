#!/usr/bin/env bash
set -uo pipefail
cd "$(dirname "$0")/../.."
export FIRNLIB="$PWD/lib"
TMPD=$(mktemp -d)
trap 'rm -rf "$TMPD"' EXIT
export DESIGNBUILD="$TMPD/build"
pass=0; fail=0
ok()  { pass=$((pass+1)); printf '  OK    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }
FIRMWARE_PATH=/lib/firmware/intel/iwlwifi/iwlwifi-8265-36.ucode
SCALE=${1:-1}
RES=1280x800; [ "$SCALE" != 1 ] && RES=1920x1080

bash vendor/firn/fetch-firnc.sh >/dev/null 2>&1
mkdir -p "$TMPD/blobs"
python3 -I tools/iwlfh/ref.py gen "$TMPD/blobs" > "$TMPD/blobs.log" 2>&1 || { bad "firmware reference blobs"; echo "QSNETWIFI: $pass passed, $fail failed"; exit 1; }

{
    echo "warteauf 'taskbar: steht|taskbar: geom' || 120"
    echo "warte 5"
    echo "taste meta_l-a"
    echo "warteauf 'qs: open' || 30"
    echo "warte 2"
    echo "klickauf qskachel1"
    echo "warteauf 'qsnet: page open' || 30"
    echo "foto early"
    echo "warteauf 'qsnet: state=[0-9]+ kind=[0-9]+ rows=[1-9]' || 150"
    echo "warte 4"
    echo "foto list"
    for r in 0 1 2; do
        echo "klickauf qsnetkey$((50 + r))"; echo "warte 3"; echo "foto pick$r"
        echo "klickauf qsnetkey41"; echo "tippe abc"; echo "klickauf qsnetkey42"; echo "warte 2"; echo "foto short$r"
        echo "klickauf qsnetkey41"; echo "tippe defgh123"; echo "klickauf qsnetkey42"; echo "warte 3"
    done
    echo "warte 3"
} > "$TMPD/script.txt"

D="$TMPD/out"
mkdir -p "$D"
AUDIT_PROC=1 AUDIT_MKFS_EXTRA="/lib/firmware/ /lib/firmware/intel/ /lib/firmware/intel/iwlwifi/ $FIRMWARE_PATH=$TMPD/blobs/v7.bin" \
    bash tools/design/audit.sh "$D" accel=kvm uitrace=yes fs=an extra="iwlfhtest iwlfhbind" uiscale="$SCALE" res="$RES" halt=400 \
    drehbuch="$TMPD/script.txt" > "$TMPD/audit.log" 2>&1
S="$D/serial.txt"
if [ -n "${QSNET_OUT:-}" ]; then mkdir -p "$QSNET_OUT/w$SCALE"; cp "$D"/*.ppm "$S" "$QSNET_OUT/w$SCALE/" 2>/dev/null; fi
if [ ! -s "$S" ]; then bad "no serial output: $(tail -3 "$TMPD/audit.log" | tr "\n" " ")"; echo "QSNETWIFI: $pass passed, $fail failed"; exit 1; fi

ocr() { python3 -I -c "
import sys
from PIL import Image
im = Image.open(sys.argv[1]).convert('L')
im = im.resize((im.width * 2, im.height * 2))
im.save(sys.argv[2])" "$1" "$TMPD/ocr.png" && tesseract "$TMPD/ocr.png" - 2>/dev/null; }

if [ -s "$D/list.ppm" ] && ocr "$D/list.ppm" | grep -qi "OrientFake"; then ok "scale $SCALE: the scanned list shows OrientFake"
else bad "scale $SCALE: OrientFake not visible in the list picture"; fi
if [ -s "$D/early.ppm" ] && ocr "$D/early.ppm" | grep -qi "OrientFake"; then bad "scale $SCALE: counter-proof broken: the name is visible before the scan"
else ok "scale $SCALE: counter-proof -- no network name before the scan result"; fi
[ "$(grep -ac 'qsnet: pick=' "$S")" -ge 3 ] && ok "scale $SCALE: three rows were picked" || bad "scale $SCALE: fewer than three picks"
grep -aq 'qsnet: box k=41 ' "$S" && ok "scale $SCALE: a secured network opens the password row" || bad "scale $SCALE: no password row appeared"
grep -aq 'qsnet: password short' "$S" && ok "scale $SCALE: a 3 character password is rejected" || bad "scale $SCALE: short password not rejected"
grep -aq 'qsnet: connect rc=0' "$S" && ok "scale $SCALE: a valid password saves the network" || bad "scale $SCALE: no connect after a valid password"
if grep -aqE 'CRASH|EXCEPTION' "$S"; then bad "scale $SCALE: crash lines in serial"; else ok "scale $SCALE: no crash lines"; fi
echo "QSNETWIFI: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
