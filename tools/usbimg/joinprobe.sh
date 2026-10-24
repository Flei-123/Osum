#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/usbimg/joinprobe.sh -- CLICK PROBE of "Join" in the friends bar on the real USB image.
#
#   /root/jarvis/bin/heavy bash tools/usbimg/joinprobe.sh [workdir]
#
# Seeds a local friend with a joinable activity, an accepted join answer, an open incoming invite
# and a games list (one `os l` row: echo) into the image (SOCIAL_SEED), adds a start menu bundle
# for /bin/freunde (USBIMG_EXTRA), boots with UITRACE, opens the friends bar from the start menu and
# clicks: friend row -> chat -> Join (path A), then the invites tab -> Accept (path B). Both paths
# must end in `partyrun: start /bin/echo target=<target>` on the serial line.
set -uo pipefail
cd "$(dirname "$0")/../.."
OUT=${1:-}
if [ -z "$OUT" ]; then OUT=$(mktemp -d /tmp/joinprobe-XXXX); trap 'rm -rf "$OUT"' EXIT; fi
mkdir -p "$OUT"
pass=0; fail=0
ok()  { pass=$((pass+1)); echo "  OK    $1"; }
bad() { fail=$((fail+1)); echo "  FAIL  $1"; }

command -v qemu-system-x86_64 >/dev/null 2>&1 || { echo "JOINPROBE: skipped, qemu missing"; exit 0; }
KVM=()
[ -w /dev/kvm ] && KVM=(-accel kvm -cpu host)

SEED="$OUT/seed"; PKG="$OUT/pkg"
mkdir -p "$SEED" "$PKG"
printf 'c\tpeter\tfriend\tonline\tPeter (LAN)\tpeter\tin the cellar\tEchoGame\t0\t\t1\n' > "$SEED/local.book"
{
    printf 'i\tlinv11\tpeter\tout\tjoin\taccepted\t0\tgame://lobby/88\tEchoGame\n'
    printf 'i\tlinv30\tpeter\tin\tinvite\topen\t0\tgame://lobby/echo\tEchoGame\n'
} > "$SEED/local.invites"
printf 'l\techo\tEchoGame\n' > "$SEED/games.tsv"
printf 'app:freunde contacts.read messages.send invites.send activity.write\n' > "$SEED/apps"
printf 'name=Friends\ninfo=Friends bar\nkeys=friends,freunde\nfassung=1\n' > "$PKG/INFO"
cp assets/apps/charmap.osp/symbol.osym "$PKG/symbol.osym"

SOCIAL_SEED="$SEED" UITRACE=1 \
USBIMG_EXTRA="/apps/freunde.osp/ /apps/freunde.osp/INFO=$PKG/INFO@0644 /apps/freunde.osp/start@/bin/freunde /apps/freunde.osp/symbol.osym=$PKG/symbol.osym@0644" \
    bash tools/usbimg/build.sh "$OUT/bau" > "$OUT/build.txt" 2>&1 \
    && ok "image builds (uitrace on, seeded friend)" || { bad "image does not build"; tail -5 "$OUT/build.txt"; echo "JOINPROBE: $pass passed, $fail failed"; exit 1; }

S="$OUT/serial.txt"; SOCK="$OUT/mon.sock"
: > "$S"
timeout 600 qemu-system-x86_64 "${KVM[@]}" -m 512 \
    -kernel "$OUT/bau/osum.mb" -initrd "$OUT/bau/root.img" \
    -append "modfs osum vfs gfx wm wig desk wmhold wighalt=300 nokbd nosched lang=en" \
    -serial "file:$S" -display none -no-reboot -vga std \
    -monitor "unix:$SOCK,server,nowait" > "$OUT/qemu.log" 2>&1 &
QPID=$!
i=0
while [ $i -lt 800 ]; do
    grep -qaE '^wm: hold' "$S" 2>/dev/null && break
    kill -0 "$QPID" 2>/dev/null || break
    sleep 0.3; i=$((i+1))
done
grep -qaE '^wm: hold' "$S" && ok "desktop is up (wm: hold)" || { bad "desktop never came up"; kill "$QPID" 2>/dev/null; echo "JOINPROBE: $pass passed, $fail failed"; exit 1; }

drive() { python3 -u tools/design/drive.py "$SOCK" "$S" "$OUT" "$1" >> "$OUT/drive.log" 2>&1; }
since() { tail -n +"$(( $1 + 1 ))" "$S"; }

cat > "$OUT/d1" <<'E'
warte 6
klickauf start
warteauf launcher: tile || 30
warte 2
foto 00-start
klickauf start_Friends
warteauf freunde: rect || 60
warte 4
foto 02-bar
E
drive "$OUT/d1"
grep -aq '^freunde: rect ' "$S" && ok "friends bar is open and reports rectangles" || bad "friends bar did not come up"
grep -aq '^freunde: eintraege=1 ' "$S" && ok "the bar lists the seeded friend" || bad "the bar lists no friend"
wait_line() {
    local pat="$1" i
    for i in $(seq 1 60); do grep -aq "$pat" "$S" && return 0; sleep 1; done
    return 1
}
party_n() { grep -ac '^partyrun: start /bin/echo target=' "$S"; }
dlg_n() { grep -ac 'wm: trusted dialog up no=' "$S"; }
ans_n() { grep -ac 'wm: trusted dialog answer=1 ' "$S"; }
answer_dialog() {
    local i a0
    for i in $(seq 1 40); do [ "$(dlg_n)" -gt "$1" ] && break; sleep 1; done
    [ "$(dlg_n)" -gt "$1" ] || return 1
    a0=$(ans_n)
    sleep 2
    printf 'taste j\nwarte 3\n' > "$OUT/dj"
    drive "$OUT/dj"
    [ "$(ans_n)" -gt "$a0" ]
}

# path A: friend -> Message (chat) -> Join (critical: the trusted dialog asks, the probe answers it)
n0=$(party_n)
d0=$(dlg_n)
cat > "$OUT/d2" <<EOT
klickauf fdnth2x0
warte 5
foto 03-chat
klickauf fdnth2x-1
warte 3
foto 04-join
EOT
drive "$OUT/d2"
grep -aq '^freunde: key 55' "$S" && ok "path A: the Join button reaches the bar" || bad "path A: no Join key at the bar"
answer_dialog "$d0" && ok "path A: the trusted dialog took the yes" || bad "path A: no trusted dialog answered"
for i in $(seq 1 60); do [ "$(party_n)" -gt "$n0" ] && break; sleep 1; done
[ "$(party_n)" -gt "$n0" ] && ok "path A: Join starts the game through partyrun" || bad "path A: no partyrun start after Join"
grep -aq '^partyrun: start /bin/echo target=game://lobby/88' "$S" && ok "path A: the target of the accepted answer is handed over" || bad "path A: wrong or missing target"

# path B: back -> Pending tab -> Accept the open invitation
n1=$(party_n)
cat > "$OUT/d3" <<EOT
klickauf fdnth2x0
warte 4
klickauf fdnth7x2
warte 4
foto 05-pending
EOT
drive "$OUT/d3"
echo "--- rects of the pending page ---"; grep -a '^freunde: rect ' "$S" | tail -n 8 | cut -c1-120
if [ "$fail" != 0 ]; then
    echo "--- diagnosis: launcher/freunde lines ---"; grep -aE '^(launcher|freunde|social): ' "$S" | head -30 | cut -c1-160
    echo "--- diagnosis: drive.log ---"; tail -n 25 "$OUT/drive.log" 2>/dev/null | cut -c1-160
fi
kill "$QPID" 2>/dev/null; wait "$QPID" 2>/dev/null
echo "JOINPROBE: $pass passed, $fail failed"
[ "$fail" = 0 ]
