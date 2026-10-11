#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/svclog/double.sh -- THE DESKTOP STARTS `jarvisd` EXACTLY ONCE (personal image, real permission file, real server).
#
#   /root/jarvis/bin/heavy bash tools/svclog/double.sh [seconds=75]
#
# Regression of 10.10.2026: on the personal image the watch (kgui.jarvis_watch) mixed up task slot and process number
# (`elf.spawn` returns the SLOT; slot 16 was pid 27 there), looked at `settingsd`, called the running helper "ended" and
# started a second one: `desk: start /bin/jarvisd` twice, `jarvisd: already running -- not starting a second one`, then
# an endless restart loop with back-off. tools/svclog/respawn.sh could not see it: in its small machine slot == pid.
#
# This test builds the personal image with the REAL file assets/jarvis/rechte-justin.conf (as the Dell stick), boots it
# once with BIOS + KVM + user networking (needs access to the bridge server) and lets it run for the whole time:
#   - `desk: start /bin/jarvisd` exactly ONCE
#   - no `desk: jarvisd ended`, no `desk: jarvisd restart in`, no `already running`
#   - the helper reached the server (`jarvisd: signed in`, or `PAIRING CODE` for a key that was never paired)
# Counter-proof: run the same script on a tree without the fix (origin/main 6ef081e1 gives 3 starts, 3 ends, 3 "already running").
# Lines are matched as plain substrings per line (-a: the serial file may hold odd octets); the watch lines are written
# under the serial line lock now, and the start count uses three lines, because output of other cores can still cut into a line.
set -uo pipefail
cd "$(dirname "$0")/../.."
SECS=${1:-75}
TMPD=$(mktemp -d)
trap 'rm -rf "$TMPD"' EXIT
pass=0; fail=0
ok()  { pass=$((pass+1)); printf '  OK    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }
export DESIGNBUILD="$TMPD/build"
FS_BLOCKS="${FS_BLOCKS:-102400}" JARVIS_CONF="${JARVIS_CONF:-assets/jarvis/rechte-justin.conf}" \
    bash tools/usbimg/build.sh "$TMPD/img" > "$TMPD/build.txt" 2>&1 || { echo "image build failed"; tail -15 "$TMPD/build.txt"; exit 1; }
IMG=$(ls "$TMPD"/img/*usb*.img | head -1)
echo "image: $(basename "$IMG") $(stat -c%s "$IMG") octets"
KVM=(); [ -w /dev/kvm ] && KVM=(-accel kvm -cpu host)
cp "$IMG" "$TMPD/disk.img"
timeout $((SECS+60)) qemu-system-x86_64 "${KVM[@]}" -smp 4 -m 1024 -drive "file=$TMPD/disk.img,format=raw" \
    -netdev user,id=n0 -device e1000,netdev=n0 -serial "file:$TMPD/ser.txt" -display none -no-reboot \
    > "$TMPD/q.log" 2>&1 &
q=$!
sleep "$SECS"
kill "$q" 2>/dev/null; wait "$q" 2>/dev/null
S="$TMPD/ser.txt"
[ -n "${KEEP:-}" ] && cp "$S" "$KEEP"
grep -aE 'desk: start /bin/jarvisd|desk: jarvisd|jarvisd: (signed in|PAIRING|already|permissions)' "$S" | head -12 | cut -c1-140 | sed 's/^/        /'

# Serial lines of different cores can be cut into each other (even `desk: start` once came out as "desk: start /bin/jarvisd  pwimd:= 1f6o"),
# so a start is counted by three independent lines of the same start; the largest count counts, and it must be exactly 1.
n1=$(grep -ac 'desk: start /bin/jarvisd' "$S"); n2=$(grep -ac 'jarvisd: supervisor started' "$S"); n3=$(grep -ac 'jarvisd: permissions read' "$S")
n=$n1; [ "$n2" -gt "$n" ] && n=$n2; [ "$n3" -gt "$n" ] && n=$n3
echo "        starts seen: desk=$n1 supervisor=$n2 permissions=$n3"
[ "$n" = 1 ] && ok "jarvisd started exactly once" || bad "jarvisd started $n times (want 1)"
e=$(grep -ac 'desk: jarvisd ended' "$S")
[ "$e" = 0 ] && ok "the watch never called the running helper ended" || bad "the watch reported $e ends"
r=$(grep -ac 'desk: jarvisd restart in' "$S")
[ "$r" = 0 ] && ok "no restart back-off" || bad "$r restart back-offs"
a=$(grep -ac 'jarvisd: already running' "$S")
[ "$a" = 0 ] && ok "no second service was refused" || bad "$a x 'already running'"
g=$(grep -acE 'jarvisd: (signed in|PAIRING CODE)' "$S")
[ "$g" -ge 1 ] && ok "the helper reached the server (signed in / pairing code)" || bad "the helper never reached the server"
echo "== $pass ok, $fail fail =="
[ "$fail" = 0 ]
