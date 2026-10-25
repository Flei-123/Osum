#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/osktray/run.sh -- r1919: on-screen keyboard row in the tray flyout (traypop.fi) + Settings switch (settings.fi, /etc/osk.conf).
#   /root/jarvis/bin/heavy bash tools/osktray/run.sh
# A: /etc/osk.conf tray=1 -> flyout reports `traypop: rect name=osk`; click starts /bin/osk (`traypop: osk pid=`, `osk: ready`),
#    second click on the row toggles it away (`osk: toggled`).
# B COUNTER-PROOF: no /etc/osk.conf -> no osk row, the flyout is lower than in A.
# C: Settings -> Mouse switch on/off/on writes the file (`settings: osk tray=1/0/1 ok=1`); the flyout then has the row.
set -uo pipefail
cd "$(dirname "$0")/../.."
TMPD=$(mktemp -d)
trap 'rm -rf "$TMPD"' EXIT
pass=0; fail=0
ok()  { pass=$((pass+1)); printf '  OK    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }
PROGS="desktop taskbar settings launcher explorer netview taskmgr edit sh echo ls cat ps uname date df mkdir rm cp mv grep head tail wc find du chmod id whoami touch true false sleep kill sort uniq rmdir theme locate dhcp host ping netstat notify osk"
printf 'tray=1\n' > "$TMPD/osk.conf"
cat > "$TMPD/a.txt" <<'DEOF'
warteauf 'taskbar: steht|taskbar: geom' || 120
warte 8
foto a-0
klickauf chevron
warteauf 'traypop: rect name=osk' || 25
warte 3
foto a-open
klickauf trayrectosk
warteauf 'osk: ready' || 60
warte 5
foto a-osk
marke 'traypop: rect name=osk'
klickauf chevron
warteneu 'traypop: rect name=osk' || 25
warte 3
klickauf trayrectosk
warteauf 'osk: toggled' || 40
warte 5
foto a-gone
DEOF
cat > "$TMPD/b.txt" <<'DEOF'
warteauf 'taskbar: steht|taskbar: geom' || 120
warte 8
klickauf chevron
warteauf 'traypop: open' || 25
warte 4
foto b-open
DEOF
cat > "$TMPD/c.txt" <<'DEOF'
warte 12
klick 24,780
warte 3
klickauf start_Settings
warte 12
klickauf srecttabp
warte 3
klickauf srectmosk
warte 4
klickauf srectmosk
warte 4
klickauf srectmosk
warte 4
marke 'traypop: open'
klickauf chevron
warteneu 'traypop: open' || 25
warte 4
foto c-open
DEOF
run_one() {
    mkdir -p "$TMPD/$1"
    EH_ETC_EXTRA="$3" EH_MKFS_EXTRA="/proc/" DESIGNBUILD="$TMPD/$1/build" bash tools/design/eh6.sh "$TMPD/$1/o" res=1280x800 accel=kvm tafel=nein "extra=vfs lang=en" \
        progs="$PROGS" tbextra="tray_chevron=1" drehbuch="$2" > "$TMPD/$1/o.log" 2>&1 < /dev/null
    rm -rf "$TMPD/$1/build"
}
bash vendor/firn/fetch-firnc.sh >/dev/null 2>&1
run_one a "$TMPD/a.txt" "/etc/osk.conf=$TMPD/osk.conf@0644"
if [ -z "${OSKTRAY_ONLY_A:-}" ]; then
    run_one b "$TMPD/b.txt" ""
    run_one c "$TMPD/c.txt" ""
fi
SA="$TMPD/a/o/serial.txt"; SB="$TMPD/b/o/serial.txt"; SC="$TMPD/c/o/serial.txt"
if [ -n "${OSKTRAY_OUT:-}" ]; then
    mkdir -p "$OSKTRAY_OUT"
    for r in a b c; do cp "$TMPD/$r/o/serial.txt" "$OSKTRAY_OUT/serial-$r.txt" 2>/dev/null; cp "$TMPD/$r/o/"*.ppm "$OSKTRAY_OUT/" 2>/dev/null; cp "$TMPD/$r/o.log" "$OSKTRAY_OUT/log-$r.txt" 2>/dev/null; done
fi
for r in a b c; do grep -a '^panic' "$TMPD/$r/o/serial.txt" | head -2; done
num() { echo "$1" | sed -E "s/.* $2=([0-9]+).*/\1/"; }
ha=$(num "$(grep -a 'traypop: open n=' "$SA" | head -1)" h)
hb=$(num "$(grep -a 'traypop: open n=' "$SB" | head -1)" h)
hc=$(num "$(grep -a 'traypop: open n=' "$SC" | tail -1)" h)
grep -aq 'traypop: rect name=osk x=' "$SA" && ok "A: the flyout reports the keyboard row" || bad "A: no keyboard row rect"
grep -aq 'traypop: osk pid=' "$SA" && ok "A: the click on the row starts /bin/osk" || bad "A: no 'traypop: osk pid='"
grep -aq '^osk: ready' "$SA" && ok "A: the keyboard came up (osk: ready)" || bad "A: no 'osk: ready'"
grep -aq 'osk: toggled' "$SA" && ok "A: the second click toggled it away (osk: toggled)" || bad "A: no 'osk: toggled'"
grep -aq 'traypop: shut osk' "$SA" && ok "A: the flyout closed itself after the click" || bad "A: flyout did not close"
if grep -aq 'traypop: rect name=osk' "$SB"; then bad "B COUNTER-PROOF: keyboard row without /etc/osk.conf"; else ok "B COUNTER-PROOF: no /etc/osk.conf -> no keyboard row"; fi
[ -n "$ha" ] && [ -n "$hb" ] && [ "$ha" -gt "$hb" ] && ok "B COUNTER-PROOF: the flyout is lower without the row (A $ha px, B $hb px)" || bad "flyout heights A=$ha B=$hb"
python3 -I - "$SC" <<'PY' && ok "C: switch clicks stored tray 1, 0, 1 (ok=1)" || bad "C: switch clicks"
import re, sys
t = open(sys.argv[1], "rb").read().decode("latin1")
L = [(int(m.group(1)), int(m.group(2))) for m in re.finditer(r"settings: osk tray=(\d+) ok=(\d+)", t)]
print("states (tray, ok):", L)
if [s[0] for s in L[-3:]] != [1, 0, 1] or len(L) < 3 or any(s[1] != 1 for s in L):
    sys.exit(1)
PY
grep -aq 'traypop: rect name=osk x=' "$SC" && ok "C: after the switch the flyout shows the keyboard row" || bad "C: no row after the switch"
[ -n "$hc" ] && [ "$hc" = "$ha" ] && ok "C: same flyout height as A ($hc px)" || bad "C: flyout height $hc vs A $ha"
echo "OSKTRAY: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
