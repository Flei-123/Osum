#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/actionbus/image.sh -- AB-016: THE ACTION BUS IN THE REAL IMAGE.
#
#   bash tools/actionbus/image.sh [workdir]
#
# tools/actionbus/run.sh measures the bus in small test guests. This one
# builds the SHIPPED stick image (tools/usbimg/build.sh, the one that goes
# onto the Dell) and boots it the way the Dell does -- UEFI, from USB,
# the default menu entry, desktop with sign-in -- and checks that:
#
#   1. the image carries the broker, the client, the settings provider,
#      the rules, the schema and the settings manifest; the image's own
#      bundles carry the SYSTEM marker (AB-003);
#   2. the session starts the broker BEFORE the sign-in, and the settings
#      provider binds to it;
#   3. the desktop still comes up (the bus costs the session nothing it
#      needs) and nothing panics.
set -uo pipefail
cd "$(dirname "$0")/../.."
ROOT=$(pwd)

pass=0; fail=0
ok()  { pass=$((pass+1)); printf '  OK    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }
has() { grep -qaF -- "$2" "$1" && ok "$3" || bad "$3 -- '$2' missing"; }

TMPD=${1:-$(mktemp -d)}
mkdir -p "$TMPD"
IMGDIR="$TMPD/bau"
IMG="$IMGDIR/osum-usb.img"

echo "== 1. build the stick image =="
if bash tools/usbimg/build.sh "$IMGDIR" > "$TMPD/build.txt" 2>&1; then
    ok "tools/usbimg/build.sh builds the image ($(stat -L -c%s "$IMG") octets)"
else
    bad "the image does not build"; tail -15 "$TMPD/build.txt" | sed 's/^/        /'
    echo "ACTBUS-IMAGE: $pass passed, $fail failed"; exit 1
fi
python3 tools/osum/mkfs.py list "$IMGDIR/root.img" > "$TMPD/list.txt" 2>&1
for f in /bin/orientbus /bin/act /bin/settingsd /etc/orientbus/policy \
         /etc/settings.schema /etc/actions.d/settings.actions \
         /apps/terminal.osp/SYSTEM /apps/settings.osp/SYSTEM; do
    grep -qE "(^|[[:space:]])${f}([[:space:]]|\$)" "$TMPD/list.txt" \
        && ok "in the image: $f" || bad "missing in the image: $f"
done

OVMF_CODE=""; OVMF_VARS=""
for c in /usr/share/OVMF/OVMF_CODE_4M.fd /usr/share/OVMF/OVMF_CODE.fd; do
    [ -f "$c" ] && { OVMF_CODE=$c; break; }; done
for v in /usr/share/OVMF/OVMF_VARS_4M.fd /usr/share/OVMF/OVMF_VARS.fd; do
    [ -f "$v" ] && { OVMF_VARS=$v; break; }; done
if [ -z "$OVMF_CODE" ] || ! command -v qemu-system-x86_64 >/dev/null; then
    bad "no OVMF/qemu -- the boot cannot run"
    echo "ACTBUS-IMAGE: $pass passed, $fail failed"; exit 1
fi
KVM=()
[ -w /dev/kvm ] && KVM=(-accel kvm -cpu host)

echo "== 2. boot it like the Dell: UEFI, USB, default entry =="
D="$TMPD/boot"; rm -rf "$D"; mkdir -p "$D"
cp -f "$IMG" "$D/stick.img"
cp -f "$OVMF_VARS" "$D/vars.fd"
truncate -s 256M "$D/disk.img"
timeout 300 qemu-system-x86_64 "${KVM[@]}" -m 2048 -smp 2 \
    -drive "if=pflash,format=raw,unit=0,readonly=on,file=$OVMF_CODE" \
    -drive "if=pflash,format=raw,unit=1,file=$D/vars.fd" \
    -device qemu-xhci,id=xhci \
    -drive "file=$D/stick.img,format=raw,if=none,id=stick" \
    -device usb-storage,bus=xhci.0,drive=stick \
    -drive "file=$D/disk.img,format=raw,if=ide,index=0" \
    -vga std -display none -no-reboot -net none \
    -serial "file:$D/ser.txt" \
    -monitor "unix:$D/mon.sock,server,nowait" > "$D/qemu.txt" 2>&1 &
QPID=$!
i=0
while [ $i -lt 900 ]; do
    grep -qa 'orientbus: provider settings bound' "$D/ser.txt" 2>/dev/null && break
    kill -0 "$QPID" 2>/dev/null || break
    sleep 0.2; i=$((i + 1))
done
# let the session settle: the desktop, the sign-in, 20 s of idle broker
sleep 20
printf 'screendump %s\n' "$D/shot.ppm" | socat - "UNIX-CONNECT:$D/mon.sock" >/dev/null 2>&1
sleep 2
printf 'quit\n' | socat - "UNIX-CONNECT:$D/mon.sock" >/dev/null 2>&1
wait "$QPID" 2>/dev/null
tr -cd '\11\12\15\40-\176' < "$D/ser.txt" > "$D/ser.klar"
S="$D/ser.klar"
grep -qaE 'desk: orientbus pid=[0-9]' "$S" && ok "the session starts /bin/orientbus ($(grep -aoE 'desk: orientbus pid=[0-9]+' "$S" | head -1))" \
    || bad "the session did not start the broker"
# The serial line is shared with the kernel, and with two cores its lines
# can tear a program's line apart (A-046). So the ready lines are looked
# for with the kernel's characters taken OUT: every character of the
# expected line, in order, within a window of three times its length.
torn() { # file text -> 0 if the text is there, possibly interleaved
    python3 - "$1" "$2" <<'PY2'
import sys
d = open(sys.argv[1], encoding="latin-1").read()
t = sys.argv[2]
start = 0
while True:
    i = d.find(t[0], start)
    if i < 0:
        sys.exit(1)
    j, k = i, 0
    while j < len(d) and k < len(t) and j - i < 3 * len(t):
        if d[j] == t[k]:
            k += 1
        j += 1
    if k == len(t):
        sys.exit(0)
    start = i + 1
PY2
}
torn "$S" "orientbus: ready apps=1 actions=6 rejected_manifests=0" \
    && ok "the broker reads the settings manifest (1 app, 5 actions + 1 event, none refused)" \
    || bad "no 'orientbus: ready apps=1 actions=6 rejected_manifests=0'"
torn "$S" "settingsd: ready keys=14" \
    && ok "settingsd reads the shipped schema (14 settings)" \
    || bad "no 'settingsd: ready keys=14'"
has "$S" "orientbus: provider settings bound" "settingsd is bound as the provider of settings.*"
# the broker comes before the sign-in screen
lb=$(grep -anE 'desk: orientbus pid=' "$S" | head -1 | cut -d: -f1)
la=$(grep -anE 'desk: start /bin/glogin|desk: start /bin/desktop' "$S" | head -1 | cut -d: -f1)
[ -n "$lb" ] && [ -n "$la" ] && [ "$lb" -lt "$la" ] \
    && ok "the broker starts before the sign-in (serial line $lb < $la)" \
    || bad "order broker/sign-in: ${lb:-?} / ${la:-?}"
grep -qaE 'glogin: bereit|glogin: desktop pid=|wm: fen i=' "$S" \
    && ok "the session still comes up (sign-in / desktop window reported)" \
    || bad "no sign-in screen and no desktop window on the serial line"
grep -qaE 'panic|EXCEPTION|#GP|#PF' "$S" && bad "a panic or exception while booting" || ok "no panic, no exception"
grep -qa 'bus: reserved name' "$S" && bad "a reserved bus name was refused while booting: $(grep -a 'bus: reserved name' "$S" | head -1)" \
    || ok "no program of the image tripped over a reserved bus name"
if [ -s "$D/shot.ppm" ]; then
    python3 -c "from PIL import Image; Image.open('$D/shot.ppm').save('$D/shot.png')" 2>/dev/null
    ok "photo of the session: $D/shot.png"
fi
echo "ACTBUS-IMAGE: $pass passed, $fail failed"
[ "$fail" = 0 ]
