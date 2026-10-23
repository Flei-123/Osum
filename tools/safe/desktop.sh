#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/safe/desktop.sh -- W-SAFE2 desktop gate: good-boot mark, hang watchdog, no false positive at idle.
#
#   /root/jarvis/bin/heavy bash tools/safe/desktop.sh
#
# A  idle desktop with `safeauto safewd`: must report "boot marked good" and NO watchdog line (measures that the desktop round
#    counter keeps moving at idle).
# B  `safeauto safewd stallspin=100000` + a key press: the desktop loop hangs, watchdog must fire (~40 s) and enter the panic path.
# C  counter-proof: same hang without `safewd`: no watchdog line.
set -uo pipefail
cd "$(dirname "$0")/../.."
TMPD=$(mktemp -d)
trap 'rm -rf "$TMPD"' EXIT
pass=0; fail=0
ok()  { pass=$((pass+1)); printf '  OK    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }
PROGS="desktop taskbar settings launcher explorer netview taskmgr edit sh echo ls cat ps uname date df mkdir rm cp mv grep head tail wc find du chmod id whoami touch true false sleep kill sort uniq"
cat > "$TMPD/idle.txt" <<EOT
warteauf 'taskbar: health' || 240
warte 110
foto 00-end
EOT
cat > "$TMPD/hang.txt" <<EOT
warteauf 'taskbar: health' || 240
warte 5
taste esc
warte 3
taste esc
warte 75
foto 00-end
EOT
run_one() { # <name> <extra words> <script>
    mkdir -p "$TMPD/$1"
    ( DESIGNBUILD="$TMPD/$1/build" bash tools/design/eh6.sh "$TMPD/$1/o" res=1280x800 accel=kvm tafel=nein progs="$PROGS" \
        extra="$2" drehbuch="$TMPD/$3" > "$TMPD/$1/o.log" 2>&1 )
}
bash vendor/firn/fetch-firnc.sh >/dev/null 2>&1
run_one a "safeauto safewd" idle.txt &
run_one b "safeauto safewd stallspin=100000" hang.txt &
run_one c "safeauto stallspin=100000" hang.txt &
wait
SA="$TMPD/a/o/serial.txt"; SB="$TMPD/b/o/serial.txt"; SC="$TMPD/c/o/serial.txt"
if [ -n "${SAFE_OUT:-}" ]; then
    mkdir -p "$SAFE_OUT"; for r in a b c; do cp "$TMPD/$r/o/serial.txt" "$SAFE_OUT/serial-$r.txt" 2>/dev/null; done
fi
for r in a b c; do
    [ -s "$TMPD/$r/o/serial.txt" ] || bad "run $r: no serial output: $(tail -n 3 "$TMPD/$r/o.log" | tr '\n' ' ')"
done
if [ "$fail" -gt 0 ]; then echo "SAFEDESK: $pass passed, $fail failed"; exit 1; fi
grep -aq '^taskbar: health ' "$SA" && ok "A: desktop came up" || bad "A: no taskbar health"
grep -aq 'boot marked good' "$SA" && ok "A idle: boot marked good: $(grep -a -m1 'boot marked good' "$SA")" || bad "A idle: no 'boot marked good'"
nw=$(grep -ac 'watchdog: desktop loop' "$SA")
[ "$nw" = 0 ] && ok "A idle: 0 watchdog fires (no false positive)" || bad "A idle: $nw watchdog fires"
grep -aiqE 'panic|kernel fault' "$SA" && bad "A idle: panic on serial" || ok "A idle: 0 panics"
nb=$(grep -ac 'watchdog: desktop loop' "$SB")
[ "$nb" = 1 ] && ok "B hang: watchdog fired once: $(grep -a -m1 'watchdog: desktop loop' "$SB")" || bad "B hang: expected 1 watchdog fire, found $nb"
grep -aiqE 'panic|kernel fault|trap' "$SB" && ok "B hang: panic path entered" || bad "B hang: no panic path after watchdog"
nc=$(grep -ac 'watchdog: desktop loop' "$SC")
[ "$nc" = 0 ] && ok "C counter-proof (no safewd): 0 watchdog lines" || bad "C counter-proof: $nc watchdog lines"
echo; echo "SAFEDESK: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
