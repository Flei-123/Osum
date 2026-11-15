#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
set -uo pipefail
cd "$(dirname "$0")/../.."
TMPD=$(mktemp -d)
trap 'rm -rf "$TMPD"' EXIT
PASS=0
FAIL=0
ok() { PASS=$((PASS + 1)); printf '  OK    %s\n' "$1"; }
bad() { FAIL=$((FAIL + 1)); printf '  FAIL  %s\n' "$1"; }
has() { if grep -qaE -- "$2" "$1"; then ok "$3"; else bad "$3 -- '$2' missing"; fi; }
hasnot() { if grep -qaE -- "$2" "$1"; then bad "$3 -- '$2' present"; else ok "$3"; fi; }

printf 'dummy\n' > "$TMPD/bad.key"
python3 -c 'import secrets; print(secrets.token_hex(32))' > "$TMPD/good.key"
chmod 600 "$TMPD/good.key"

build_image() {
    local name=$1 key=$2
    DESIGNBUILD="$TMPD/build-$name" HP_STICK=1 JARVIS_CONF=assets/jarvis/rechte-hp-dev.conf JARVIS_DEVICE_KEY="$key" \
        bash tools/usbimg/build.sh "$TMPD/img-$name" > "$TMPD/build-$name.txt" 2>&1
    ls "$TMPD/img-$name"/*usb*.img 2> /dev/null | head -1
}

run_image() {
    local name=$1 img=$2 limit=$3 stop=$4
    local kvm=()
    [ -w /dev/kvm ] && kvm=(-accel kvm -cpu host)
    cp "$img" "$TMPD/disk-$name.img"
    timeout "$limit" qemu-system-x86_64 "${kvm[@]}" -smp 2 -m 2048 -drive "file=$TMPD/disk-$name.img,format=raw" \
        -netdev user,id=n0 -device e1000,netdev=n0 -serial "file:$TMPD/ser-$name.txt" -display none -no-reboot \
        > "$TMPD/q-$name.log" 2>&1 &
    local q=$!
    local t=0
    while [ "$t" -lt $((limit * 5)) ]; do
        grep -qaE -- "$stop" "$TMPD/ser-$name.txt" 2> /dev/null && break
        kill -0 "$q" 2> /dev/null || break
        sleep 0.2
        t=$((t + 1))
    done
    sleep 1
    kill "$q" 2> /dev/null
    wait "$q" 2> /dev/null
    rm -f "$TMPD/disk-$name.img"
}

echo "== 1. unsignable device key: reason logged, strikes, reboot =="
BAD=$(build_image bad "$TMPD/bad.key")
[ -n "$BAD" ] || { echo "image build failed"; tail -15 "$TMPD/build-bad.txt"; exit 1; }
run_image bad "$BAD" 400 'heal: rebooting'
has "$TMPD/ser-bad.txt" 'jarvisd: heal: signing failed, reason [0-9]+ detail [0-9]+' "reason and detail logged"
has "$TMPD/ser-bad.txt" 'jarvisd: heal: strike 1' "first strike"
has "$TMPD/ser-bad.txt" 'jarvisd: heal: strike 2' "second strike"
has "$TMPD/ser-bad.txt" 'jarvisd: heal: rebooting' "reboot after two strikes"

echo "== 2. control: valid device key reaches the server, no heal action =="
GOOD=$(build_image good "$TMPD/good.key")
[ -n "$GOOD" ] || { echo "image build failed"; tail -15 "$TMPD/build-good.txt"; exit 1; }
run_image good "$GOOD" 200 'jarvisd: (signed in|PAIRING CODE)'
sleep 1
has "$TMPD/ser-good.txt" 'jarvisd: (signed in|PAIRING CODE)' "helper reached the server"
hasnot "$TMPD/ser-good.txt" 'jarvisd: heal:' "no heal output"

echo "== $PASS ok, $FAIL fail =="
[ "$FAIL" = 0 ]
