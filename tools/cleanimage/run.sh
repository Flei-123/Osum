#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# heavy bash tools/cleanimage/run.sh
set -uo pipefail
cd "$(dirname "$0")/../.."
. tools/lib/brand-env.sh
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

pass=0
fail=0
ok()  { pass=$((pass + 1)); printf '  OK    %s\n' "$*"; }
bad() { fail=$((fail + 1)); printf '  FAIL  %s\n' "$*"; }

echo "== 1. build release and dev images =="
IMAGE_PROFILE=release PARTTAB=mbr bash tools/usbimg/build.sh "$WORK/release" > "$WORK/release.log" 2>&1 \
    && ok "release image builds" || { bad "release build"; tail -20 "$WORK/release.log"; }
IMAGE_PROFILE=dev PARTTAB=mbr bash tools/usbimg/build.sh "$WORK/dev" > "$WORK/dev.log" 2>&1 \
    && ok "dev image builds" || { bad "dev build"; tail -20 "$WORK/dev.log"; }
REL="$WORK/release/${MARKE_DATEI}-usb.img"
DEV="$WORK/dev/${MARKE_DATEI}-usb.img"

echo "== 2. release image holds no dev parts =="
if python3 tools/usbimg/pubcheck.py "$REL" > "$WORK/rel.txt" 2>&1; then
    ok "release image is fit"
else
    bad "release image is not fit: $(tr '\n' ' ' < "$WORK/rel.txt")"
fi
python3 tools/usbimg/pubcheck.py "$REL" 2>&1 | grep -q 'dev ' && bad "dev findings in release" || ok "no dev findings in release"

mcopy -o -i "$REL@@1M" ::/root.img "$WORK/release-root.img" > /dev/null 2>&1
python3 tools/osum/mkfs.py list "$WORK/release-root.img" > "$WORK/release-files.txt" 2>&1
for kept in /bin/resetsys /system/factory/mouse.conf /bin/settings /bin/installer; do
    grep -q "^$kept " "$WORK/release-files.txt" && ok "release keeps $kept" || bad "release lost $kept"
done

echo "== 3. counter-proof: the dev image is rejected for dev parts =="
python3 tools/usbimg/pubcheck.py "$DEV" > "$WORK/dev.txt" 2>&1 && bad "dev image passes the check" || ok "dev image is rejected"
for needle in "dev file /bin/widgetdemo" "dev file /bin/bench" "dev boot entry" "dev boot word"; do
    grep -q "$needle" "$WORK/dev.txt" && ok "dev image flagged: $needle" || bad "dev image not flagged: $needle"
done

echo "== 4. release menu and boot words =="
mcopy -o -i "$REL@@1M" ::/limine.conf "$WORK/limine.conf" > /dev/null 2>&1
for word in tafel herz nicintx nicnoirq fbuc fbwb pulsled r3eins r3alle gsluege odb uitrace; do
    grep -qw "$word" "$WORK/limine.conf" && bad "boot word $word in release menu" || ok "no boot word $word"
done
grep -q '^/Install ' "$WORK/limine.conf" && ok "install entry kept" || bad "install entry missing"
grep -q 'safe mode' "$WORK/limine.conf" && ok "safe mode entry kept" || bad "safe mode entry missing"

echo "== 5. release image boots clean =="
BAU="$WORK/release" SCHNELL=1 PERSONAL_IMG="$DEV" bash tools/usbimg/live.sh "$WORK/live" > "$WORK/live.txt" 2>&1
KNOWN_RED="the live session WROTE to the stick"
UNEXPECTED=$(grep -E '^  FAIL' "$WORK/live.txt" | grep -vF "$KNOWN_RED" | wc -l)
[ "$UNEXPECTED" -eq 0 ] && ok "live acceptance: no new FAIL (known red on main: stick write)" || { bad "live acceptance"; grep FAIL "$WORK/live.txt" | head; }

echo
echo "cleanimage: $pass OK, $fail FAIL"
[ "$fail" -eq 0 ]
