#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/svclog/bootserie.sh -- BOOT SERIES OF THE PERSONAL STICK IMAGE, DEFAULT ENTRY (Limine menu timeout, nobody presses a key).
#
#   /root/jarvis/bin/heavy bash tools/svclog/bootserie.sh [runs=10]
#
# Builds the personal image (tools/usbimg/build.sh), boots a fresh copy N times with BIOS + KVM + user networking and
# counts the boots in which the desktop started `/bin/jarvisd` AND the helper signed in at the real server
# (`jarvisd: signed in`). Needs network access to the bridge server.
set -uo pipefail
cd "$(dirname "$0")/../.."
N=${1:-10}
TMPD=$(mktemp -d)
trap 'rm -rf "$TMPD"' EXIT
export DESIGNBUILD="${DESIGNBUILD:-$TMPD/build}"
JARVIS_CONF="${JARVIS_CONF:-assets/jarvis/rechte-justin.conf}" bash tools/usbimg/build.sh "$TMPD/img" > "$TMPD/build.txt" 2>&1 || { echo "image build failed"; tail -15 "$TMPD/build.txt"; exit 1; }
IMG=$(ls "$TMPD"/img/*usb*.img | head -1)
echo "image: $(basename "$IMG") $(stat -c%s "$IMG") octets"
KVM=(); [ -w /dev/kvm ] && KVM=(-accel kvm -cpu host)
started=0; signed=0; i=1
while [ "$i" -le "$N" ]; do
    cp "$IMG" "$TMPD/disk.img"
    rm -f "$TMPD/ser.txt"
    timeout 150 qemu-system-x86_64 "${KVM[@]}" -smp 4 -m 1024 -drive "file=$TMPD/disk.img,format=raw" \
        -netdev user,id=n0 -device e1000,netdev=n0 -serial "file:$TMPD/ser.txt" -display none -no-reboot \
        > "$TMPD/q.log" 2>&1 &
    q=$!
    t=0
    while [ "$t" -lt 450 ]; do
        grep -qa 'jarvisd: signed in' "$TMPD/ser.txt" 2>/dev/null && break
        kill -0 "$q" 2>/dev/null || break
        sleep 0.2; t=$((t+1))
    done
    sleep 1; kill "$q" 2>/dev/null; wait "$q" 2>/dev/null
    s=0; g=0
    grep -qaE 'desk: start /bin/jarvisd|jarvisd watch ar' "$TMPD/ser.txt" && s=1
    grep -qa 'jarvisd: signed in' "$TMPD/ser.txt" && g=1
    started=$((started+s)); signed=$((signed+g))
    printf 'boot %2d: started=%d signed_in=%d (%ds)\n' "$i" "$s" "$g" $((t/5))
    [ "$g" = 0 ] && { cp "$TMPD/ser.txt" "/tmp/svclog-bootserie-fail-$i.txt" 2>/dev/null; grep -aE 'jarvisd|dhcp' "$TMPD/ser.txt" | head -6 | sed 's/^/        /'; }
    i=$((i+1))
done
echo "== started $started/$N, signed in $signed/$N =="
[ "$started" = "$N" ] && [ "$signed" = "$N" ]
