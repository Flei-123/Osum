#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/srhotkey/run.sh -- r1990 gate: Ctrl+Alt+N switches the screen reader through hotkeyd and the bus action screenreader.toggle.
#
#   /root/jarvis/bin/heavy bash tools/srhotkey/run.sh
#
# Machine: the stick's (tools/design/eh6.sh) with the bus, hotkeyd, wmplug and `screenreader serve` started by the desktop autostart.
# Boot A (right `hotkey` granted): hotkeyd binds the key, Ctrl+Alt+N announces "Screen reader off", the second press "Screen reader on".
# Boot B (COUNTER-PROOF, no grant): hotkeyd refuses the binding (reason=no-right) and the key changes nothing.
set -uo pipefail
cd "$(dirname "$0")/../.."
ROOT=$(pwd)
export FIRNLIB="$ROOT/lib"
D=$(mktemp -d)
trap '[ -n "${SRH_KEEP:-}" ] && { mkdir -p "$SRH_KEEP"; cp "$D"/*/serial.txt "$D"/*.log "$SRH_KEEP"/ 2>/dev/null; for b in A B; do [ -s "$D/$b/serial.txt" ] && cp "$D/$b/serial.txt" "$SRH_KEEP/$b.serial"; done; }; rm -rf "$D"' EXIT
BUILD="$D/build"
mkdir -p "$BUILD"
pass=0; fail=0
ok()  { pass=$((pass+1)); printf '  OK    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }
has() { grep -qaE -- "$2" "$1" 2>/dev/null && ok "$3" || bad "$3 -- '$2' missing"; }
hasnt() { grep -qaE -- "$2" "$1" 2>/dev/null && bad "$3 -- '$2' present" || ok "$3"; }

printf 'ctrl+alt+n screenreader.toggle\n' > "$D/hotkeys.conf"
{ cat etc/wmplug.conf; printf 'screenreader rechte=0x001 prog=/bin/screenreader\n'; } > "$D/wmplug.conf"
printf 'hotkey\nscreenreader serve\n' > "$D/autostart"
printf 'screenreader hotkey\n' > "$D/rights.yes"
printf '# no grants\n' > "$D/rights.no"
printf 'autostart=1\nenabled=1\n' > "$D/screenreader.conf"
MORE="orientbus act wmplug hotkeyd apprights screenreader"
EXTRA="/var/ /var/log/ /etc/hotkeys.conf=$D/hotkeys.conf@0644 /etc/wmplug.conf=$D/wmplug.conf@0644 /etc/wmplug.autostart=$D/autostart@0644 /etc/screenreader.conf=$D/screenreader.conf@0644 /etc/actions.d/screenreader.actions=etc/actions.d/screenreader.actions@0644"

run_boot() { # name rights-file
    EH_APPEND=rtcutc EH_MKFS_EXTRA="$EXTRA /etc/apprights.conf=$2@0644" DESIGNBUILD="$BUILD" \
        bash tools/design/eh6.sh "$D/$1" res=1280x800 accel=kvm tafel=nein "moreprogs=$MORE" extra=wmplug "drehbuch=$D/$1.book" > "$D/$1.log" 2>&1
}

cat > "$D/A.book" <<EOT
warteauf 'hotkeyd: bound ctrl\+alt\+n screenreader.toggle' || 150
warteauf 'sr: serving rights=' || 120
warte 10
marke 'sr: say: Screen reader'
taste ctrl-alt-n
warteneu 'sr: say: Screen reader' || 30
warte 3
marke 'sr: say: Screen reader'
taste ctrl-alt-n
warteneu 'sr: say: Screen reader' || 30
warte 3
EOT
cat > "$D/B.book" <<EOT
warteauf 'sr: serving rights=' || 150
warte 20
taste ctrl-alt-n
warte 10
EOT

echo "== boot A (right granted) =="
run_boot A "$D/rights.yes"
SA="$D/A/serial.txt"
[ -s "$SA" ] || { bad "boot A: no serial output"; tail -15 "$D/A.log"; }
has "$SA" "hotkeyd: bound ctrl\+alt\+n screenreader.toggle" "hotkeyd bound Ctrl+Alt+N to screenreader.toggle"
has "$SA" "sr: serving rights=" "the reader was started by the desktop autostart"
tr -cd '\11\12\15\40-\176' < "$SA" > "$D/A.klar"
off=$(grep -an 'sr: say: Screen reader off' "$D/A.klar" | head -1 | cut -d: -f1)
on=$(grep -an 'sr: say: Screen reader on' "$D/A.klar" | tail -1 | cut -d: -f1)
[ -n "$off" ] && ok "first Ctrl+Alt+N: 'Screen reader off' announced" || bad "no 'Screen reader off' after the first key"
[ -n "$off" ] && [ -n "$on" ] && [ "$on" -gt "$off" ] && ok "second Ctrl+Alt+N: 'Screen reader on' announced after the off" || bad "no 'Screen reader on' after the second key"
has "$SA" "hotkeyd: fired .*screenreader.toggle" "hotkeyd fired the action"
hasnt "$SA" "panic|EXCEPTION" "no panic"

[ "${SRH_ONLY:-}" = A ] && { echo "SRHOTKEY: $pass passed, $fail failed"; [ "$fail" = 0 ]; exit; }
echo "== boot B (COUNTER-PROOF: no grant) =="
run_boot B "$D/rights.no"
SB="$D/B/serial.txt"
[ -s "$SB" ] || { bad "boot B: no serial output"; tail -15 "$D/B.log"; }
tr -cd '\11\12\15\40-\176' < "$SB" > "$D/B.klar"
has "$D/B.klar" "hotkeyd: refused ctrl\+alt\+n screenreader.toggle reason=no-right" "without the right hotkeyd refuses the binding"
hasnt "$D/B.klar" "sr: say: Screen reader off" "without the right the key does not switch the reader"

echo "SRHOTKEY: $pass passed, $fail failed"
[ "$fail" = 0 ]
