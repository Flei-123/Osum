#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
set -uo pipefail
cd "$(dirname "$0")/../.."
ROOT=$(pwd)
export FIRNLIB="${FIRNLIB:-$ROOT/lib}"
TMPD=$(mktemp -d)
SWPIDS=()
cleanup() { for p in "${SWPIDS[@]:-}"; do [ -n "$p" ] && kill "$p" 2>/dev/null; done; [ -n "${VAULTUI_KEEP:-}" ] && cp -r "$TMPD" "$VAULTUI_KEEP" 2>/dev/null; rm -rf "$TMPD"; }
trap cleanup EXIT
pass=0; fail=0
ok()  { pass=$((pass+1)); printf '  OK    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }
has() { grep -qaF -- "$2" "$1" && ok "$3" || bad "$3 -- '$2' missing"; }
hasnot() { grep -qaF -- "$2" "$1" && bad "$3 -- '$2' is there and should not be" || ok "$3"; }
count() { grep -acF -- "$2" "$1"; }

PIN1="482915"; PINBAD="590813"; PW1="correct-horse-battery"
: "${OSUM_QEMU_ACCEL:=tcg}"
[ -e /dev/kvm ] && [ "$OSUM_QEMU_ACCEL" = tcg ] && OSUM_QEMU_ACCEL=kvm
command -v swtpm >/dev/null 2>&1 || { echo "VAULTUI-LIVE: swtpm missing"; exit 1; }
command -v qemu-system-x86_64 >/dev/null 2>&1 || { echo "VAULTUI-LIVE: qemu missing"; exit 1; }

printf 'kib=64\npasses=1\nlanes=1\n' > "$TMPD/kdf"
cat > "$TMPD/vuihost.script" <<EOS
/bin/vaultd /secrets 30000 &
sleep 3000
/bin/vaultctl status
/bin/pinctl set root $PIN1
/bin/vaultctl create pw=$PW1
/bin/vaultctl tpmenroll pin=$PIN1
/bin/vaultctl lock
/bin/vaultui
EOS

live() {
    local nm=$1; shift
    local sock="$TMPD/tpm-$nm.sock"
    mkdir -p "$TMPD/st-$nm"
    swtpm socket --tpmstate "dir=$TMPD/st-$nm" --ctrl "type=unixio,path=$sock" --tpm2 --log "file=$TMPD/sw-$nm.log" &
    SWPIDS+=($!)
    local _i line
    for _i in $(seq 50); do [ -S "$sock" ] && break; sleep 0.1; done
    local -a MON=()
    for line in "$@"; do MON+=("mon=$line"); done
    bash tools/alltag/build.sh "$TMPD/$nm" kbd=yes uitrace=yes lang=en \
        "accel=${OSUM_QEMU_ACCEL}" "waitfor=vaultui: ready" \
        "extra=osum vfs bus wighalt=120 wigapp=/bin/vuihost" \
        "progs=vaultui vaultd vaultctl pinctl vuihost theme" \
        xdir=/proc xdir=/dev xdir=/secrets xdir=/etc/vault \
        "xfile=/etc/vuihost.script=$TMPD/vuihost.script" "xfile=/etc/vault/kdf=$TMPD/kdf" \
        "xfile=/etc/wallpaper=assets/wallpaper-sea.osym" \
        "qemu=-chardev socket,id=chrtpm,path=$sock -tpmdev emulator,id=tpm0,chardev=chrtpm -device tpm-tis,tpmdev=tpm0" \
        warten=4 "${MON[@]}" > "$TMPD/$nm.log" 2>&1
}

pin_lines() {
    local pin=$1 focus=${2:-1} i
    [ "$focus" = 1 ] && { echo "sendkey tab"; echo "warte 1"; }
    for ((i = 0; i < ${#pin}; i++)); do echo "sendkey ${pin:i:1}"; echo "warte 1"; done
    echo "sendkey ret"
    echo "warte 4"
}

echo "== 1. ready state in the live guest =="
live r1 "warte 6"
S=$TMPD/r1/serial.txt
has "$S" "vaultui: ready" "the window opens next to a live vaultd with a PIN slot"
has "$S" "vaultui: state 0" "state 0 (ready): PIN unlock is offered"
hasnot "$S" "vaultui: state 7" "COUNTER-PROOF: not the 'service not running' state"
if [ -s "$TMPD/r1/desktop.png" ]; then
    sc=$(python3 -I tools/mockup/ssim.py /root/jarvis/data/projects_kb/orientos/reports/mockups/vaultui.png "$TMPD/r1/desktop.png" auto "$TMPD/crop.png" 2>&1 | tail -1)
    v=$(echo "$sc" | sed -n 's/.*"ssim": *\([0-9.]*\).*/\1/p')
    python3 -I -c "import sys; sys.exit(0 if float('${v:-0}') >= 0.95 else 1)" && ok "ready mockup match: $sc" || bad "ready mockup match: $sc"
    sc2=$(python3 -I tools/mockup/ssim.py /root/jarvis/data/projects_kb/orientos/reports/mockups/vaultui-nosvc.png "$TMPD/r1/desktop.png" auto "$TMPD/crop2.png" 2>&1 | tail -1)
    v2=$(echo "$sc2" | sed -n 's/.*"ssim": *\([0-9.]*\).*/\1/p')
    python3 -I -c "import sys; sys.exit(0 if float('${v:-0}') > float('${v2:-0}') else 1)" && ok "COUNTER-PROOF: the ready shot matches ready better than no-service ($v vs $v2)" || bad "ready shot is not closer to ready than to no-service ($v vs $v2)"
else
    bad "no screenshot (r1)"
fi

[ "${VAULTUI_STOP:-9}" -le 1 ] && { echo "VAULTUI-LIVE: stopped after 1"; exit 0; }
echo "== 2. right PIN + Enter =="
mapfile -t L < <(pin_lines $PIN1)
live r2 "warte 2" "${L[@]}"
S=$TMPD/r2/serial.txt
has "$S" "vaultui: unlock ok" "right PIN, Enter key: unlock ok"
has "$S" "vuihost: run /bin/vaultui rc=0" "... and the window exits 0"
hasnot "$S" "vaultui: unlock bad" "no bad answer"

echo "== 3. wrong PIN =="
mapfile -t L < <(pin_lines $PINBAD)
live r3 "warte 2" "${L[@]}"
S=$TMPD/r3/serial.txt
has "$S" "vaultui: unlock bad" "wrong PIN: bad"
hasnot "$S" "vaultui: unlock ok" "COUNTER-PROOF: a wrong PIN never unlocks"
has "$S" "vaultui: state 1" "the window goes to the 'wrong PIN' state"
if [ -s "$TMPD/r3/desktop.png" ]; then
    python3 -I -c "
from PIL import Image, ImageChops
import sys
a=Image.open('$TMPD/r1/desktop.png').convert('RGB'); b=Image.open('$TMPD/r3/desktop.png').convert('RGB')
d=ImageChops.difference(a,b).convert('L').point(lambda v: 255 if v else 0).histogram()[255]
sys.exit(0 if d>200 else 1)" && ok "the message changes pixels on screen" || bad "the screen did not change after the wrong PIN"
fi

echo "== 4. countdown after the 5th wrong PIN =="
mapfile -t L < <(for n in 1 2 3 4 5 6; do pin_lines $PINBAD $([ "$n" = 1 ] && echo 1 || echo 0); done)
live r4 "warte 2" "${L[@]}"
S=$TMPD/r4/serial.txt
[ "$(count "$S" "vaultui: unlock bad")" -ge 5 ] && ok "five wrong PINs: five bad answers" || bad "bad answers: $(count "$S" "vaultui: unlock bad")"
has "$S" "vaultui: unlock wait" "the sixth try: the countdown starts"
has "$S" "vaultui: state 3" "state 3 (wait)"
hasnot "$S" "vaultui: unlock ok" "COUNTER-PROOF: no unlock during the delay"

echo "== 5. live guests did not crash =="
for d in r1 r2 r3 r4; do
    c=$(grep -acE 'CRASH|EXCEPTION' "$TMPD/$d/serial.txt" 2>/dev/null; true)
    [ "$c" = 0 ] || bad "crash lines in $d: $c"
done
echo "VAULTUI-LIVE: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
