#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/helperinput/run.sh -- jarvisd input jobs: size, type, tap, drag, scroll, scan; refusals with counter-proofs.
#
#   bash tools/helperinput/run.sh [<workdir>]
set -uo pipefail
cd "$(dirname "$0")/../.."
ROOT=$(pwd)
if [ -n "${1:-}" ]; then W=$1; mkdir -p "$W"; else W=$(mktemp -d); trap 'rm -rf "$W"' EXIT; fi
pass=0; fail=0
ok()  { pass=$((pass+1)); printf '  OK    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }
[ -w /dev/kvm ] && ACC=(-accel kvm -cpu host) || ACC=()

BUILD=${HELPERINPUT_BUILD:-}
if [ -z "$BUILD" ]; then
    BUILD=$W/b
    bash tools/bridge/build.sh "$BUILD" 0 > "$W/build.log" 2>&1 && ok "kernel + jarvisd build" || { bad "bridge build"; tail -8 "$W/build.log"; }
else
    ok "using the prebuilt bridge image $BUILD"
fi

cat > "$W/g.sh" <<'G'
echo ==A==
jarvisd -i size
echo ==B==
jarvisd -i type "Ab 1!"
echo ==C==
jarvisd -i "tap 100 100 1 2"
jarvisd -i "tap 120 80 2 1"
jarvisd -i "drag 10 10 50 50 1"
jarvisd -i "scroll 100 100 0 3"
jarvisd -i "scroll 100 100 3 2"
jarvisd -i "scan 29 30 158 157"
jarvisd -i "mouse 300 200"
echo ==D==
jarvisd -i "tap 100 100 9 1"
jarvisd -i "tap 100 100 1 7"
jarvisd -i bogus
jarvisd -i type
echo ==E==
jarvisctl input off
jarvisd -i type "x"
jarvisd -i size
echo ==F==
jarvisctl input on
jarvisd -i type "x"
jarvisd -c /t/no.conf -i type "x"
jarvisd -c /t/no.conf -i size
echo ==G==
exit
G
printf 'input = no\n' > "$W/no.conf"
cp assets/jarvis/rechte-justin.conf "$W/rechte.conf"
SPEC="$(cat "$BUILD/spec.txt") /etc/jarvis/permissions.conf=$W/rechte.conf /t/ /t/g.sh=$W/g.sh /t/no.conf=$W/no.conf"
bash tools/mkfsfi/mkfs.sh build "$W/v.img" 16384 $SPEC > "$W/mkfs.txt" 2>&1 || { bad "mkfs"; tail -3 "$W/mkfs.txt"; }
timeout 200 qemu-system-x86_64 "${ACC[@]}" -kernel "$BUILD/k.mb" -m 256 \
    -append "osum nokbd nosched noproc nofs noring3 gfx fbres=1280x800 script=sh /t/g.sh;exit" \
    -serial "file:$W/v.txt" -display none -no-reboot \
    -drive "file=$W/v.img,format=raw,if=ide,index=0" -vga std \
    -device isa-debug-exit,iobase=0xf4,iosize=0x04 > "$W/q.log" 2>&1
sec() { sed -n "/==$1==/,/==$2==/p" "$W/v.txt" | tr -d '\r'; }
a=$(sec A B); b=$(sec B C); c=$(sec C D); d=$(sec D E); e=$(sec E F); f=$(sec F G)
echo "$a" | grep -aqx '1280 800' && ok "size: framebuffer size 1280 800" || bad "A: size ($(echo "$a" | tail -2 | tr '\n' ' '))"
echo "$b" | grep -aq 'typed 5' && echo "$b" | grep -aq 'skipped 0' && ok "type: 5 characters typed, none skipped" || bad "B: type ($(echo "$b" | tail -3 | tr '\n' ' '))"
n=$(echo "$c" | grep -ac '^input: OK')
[ "$n" -eq 7 ] && ok "tap (double + right), drag, scroll down/left, scan, mouse: 7 of 7 accepted" || bad "C: $n of 7 accepted"
echo "$d" | grep -aq 'invalid' && ok "bad mask / bad click count are refused as invalid" || bad "D: invalid arguments not refused"
echo "$d" | grep -aq 'unknown input kind' && ok "unknown kind refused" || bad "D: unknown kind"
echo "$d" | grep -aq 'type needs the text' && ok "type without payload refused" || bad "D: empty type"
echo "$e" | grep -aq 'emergency stop engaged' && ok "COUNTER-PROOF: emergency stop refuses type" || bad "E: type not refused after the stop"
echo "$e" | grep -aqx '1280 800' && ok "size is read-only: still answers during the stop" || bad "E: size during the stop"
echo "$f" | grep -aq '^input: OK' && ok "input on releases the stop, type works again" || bad "F: release failed"
echo "$f" | grep -aq 'input = no' && ok "COUNTER-PROOF: input = no refuses type and size" || bad "F: input = no not refused"

echo; echo "HELPERINPUT: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
