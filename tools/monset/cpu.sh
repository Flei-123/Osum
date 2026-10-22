#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/monset/cpu.sh -- r1590: CPU cost of the developer overlay on the idle desktop (taskbar process hosts it).
#
#   /root/jarvis/bin/heavy bash tools/monset/cpu.sh
#
# Same method as tools/idlebudget (eh6 machine, e1000 chatter, four `ps` 45 s apart, shares from tools/menualive/check.py table), two machines at once:
# "on" has mon=true in /etc/mouse.conf (overlay shown from boot), "off" has none. Prints the per-task shares; limit: overlay costs the bar < 4 points more.
set -uo pipefail
cd "$(dirname "$0")/../.."
ROOT=$(pwd)
TMPD=$(mktemp -d)
trap 'rm -rf "$TMPD"; kill $(jobs -p) 2>/dev/null' EXIT
pass=0; fail=0
ok()  { pass=$((pass+1)); printf '  OK    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }
FPS=${FPS:-40}
printf '# /etc/mouse.conf\nmon=true\n' > "$TMPD/mouse-on.conf"

run_one() { # <name> <etc extra>
    local qp=$((20000 + RANDOM % 20000)) hp=$((40000 + RANDOM % 20000))
    mkdir -p "$TMPD/$1"
    python3 "$ROOT/tools/idlebudget/flood.py" "$qp" "$FPS" 150 "$hp" > "$TMPD/$1.flood" 2>&1 &
    local fp=$!
    EH_NETDEV="-netdev socket,id=n0,udp=127.0.0.1:$hp,localaddr=127.0.0.1:$qp -device e1000,netdev=n0,mac=52:54:00:aa:bb:cc" \
    EH_ETC_EXTRA="$2" EH_MKFS_EXTRA="/proc/" DESIGNBUILD="$TMPD/$1/build" bash tools/design/eh6.sh "$TMPD/$1/o" res=1280x800 accel=kvm netz=ja \
        "extra=vfs lang=en" drehbuch="$ROOT/tools/idlebudget/dreh.txt" > "$TMPD/$1/o.log" 2>&1
    kill $fp 2>/dev/null
}
share() { awk -v k="$2" '{ if ($0 ~ ("kind=" k " ") || $0 ~ ("name=" k " ")) { sub(/.*share=/, ""); s += $0 } } END { printf "%.1f", s }' "$1"; }

bash vendor/firn/fetch-firnc.sh >/dev/null 2>&1
run_one on "/etc/mouse.conf=$TMPD/mouse-on.conf@0644" &
run_one off "" &
wait
for t in on off; do
    S="$TMPD/$t/o/serial.txt"
    python3 tools/menualive/check.py table "$S" > "$TMPD/$t.tab" 2>&1
    [ -n "${KEEP:-}" ] && { mkdir -p "$KEEP"; cp "$S" "$KEEP/$t.serial.txt"; cp "$TMPD/$t.tab" "$KEEP/$t.tab"; }
    echo "== $t =="; head -8 "$TMPD/$t.tab" | sed 's/^/        /'
done
grep -aq 'fpsov: shown' "$TMPD/on/o/serial.txt" && ok "overlay was shown on the 'on' machine" || bad "no 'fpsov: shown' on the 'on' machine"
grep -aq 'fpsov: ' "$TMPD/off/o/serial.txt" && bad "'off' machine has fpsov lines" || ok "'off' machine has no fpsov line"
for k in taskbar starter boot; do
    a=$(share "$TMPD/on.tab" $k); b=$(share "$TMPD/off.tab" $k)
    echo "  SHARE $k on=$a off=$b"
done
ta=$(share "$TMPD/on.tab" taskbar); tb=$(share "$TMPD/off.tab" taskbar)
awk -v a="$ta" -v b="$tb" 'BEGIN{exit !(a - b < 4)}' && ok "overlay costs the bar $(awk -v a="$ta" -v b="$tb" 'BEGIN{printf "%.1f", a-b}') points (taskbar on=$ta off=$tb, limit 4)" || bad "overlay costs the bar too much (on=$ta off=$tb)"
echo; echo "MONSET-CPU: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
