#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/idlebudget/run.sh -- EVERY TASK OF THE IDLE DESKTOP STAYS UNDER ITS BUDGET (W-W, 18.10.2026).
#
#   [BASE=<rev>] bash tools/idlebudget/run.sh
#
# VirtualBox (z11), idle desktop, after the netd fix: `ps` still showed taskbar ~36 %, starter ~23 %
# (+ child ~17 %), jarvismini ~11 %, boot ~25 %. Causes found in the code: the taskbar loop woke 40x/s
# and ran ~15 pollers every round; wlib.step (launcher, mini, settings ...) woke 100x/s with its full step.
# Fix: quiet backoff (taskbar 50 ms after 2 s of no sign of life; wlib.step 40 ms after ~3 s more).
#
# Method = tools/netdidle: eh6 machine, e1000 on a chatty udp link (40 frames/s), two `ps` 30 s apart,
# per-task share from tools/menualive/check.py table. Two trees at once: HEAD and BASE (default HEAD~1).
#   1. the widget's method (everything but idle) < 15 %;
#   2. taskbar < 3 %, starter < 3 %, every user task < 5 %, boot (the kernel desktop loop) < 15 %;
#   3. COUNTER-PROOF: on the tree before, the taskbar uses at least 1 point more than now.
# QEMU/KVM shows the effect ~10x smaller than VirtualBox (taskbar 3.1-3.7 % -> 0.0 %); the budgets are
# for QEMU. The VirtualBox numbers need a real image (z-series) and `ps` twice.
set -uo pipefail
cd "$(dirname "$0")/../.."
ROOT=$(pwd)
TMPD=$(mktemp -d)
BT=$TMPD/base
cleanup() { git worktree remove --force "$BT" >/dev/null 2>&1; rm -rf "$TMPD"; kill $(jobs -p) 2>/dev/null; }
trap cleanup EXIT
pass=0; fail=0
ok()  { pass=$((pass+1)); printf '  OK    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }
FPS=${FPS:-40}

run_tree() { # <tree> <out>
    local qp=$((20000 + RANDOM % 20000)) hp=$((40000 + RANDOM % 20000))
    python3 "$ROOT/tools/idlebudget/flood.py" "$qp" "$FPS" 150 "$hp" > "$2.flood" 2>&1 &
    local fp=$!
    ( cd "$1" && bash vendor/firn/fetch-firnc.sh >/dev/null 2>&1
      EH_NETDEV="-netdev socket,id=n0,udp=127.0.0.1:$hp,localaddr=127.0.0.1:$qp -device e1000,netdev=n0,mac=52:54:00:aa:bb:cc" \
      DESIGNBUILD="$2/build" bash tools/design/eh6.sh "$2/o" res=1280x800 accel=kvm netz=ja \
        drehbuch="$ROOT/tools/idlebudget/dreh.txt" > "$2/o.log" 2>&1 )
    kill $fp 2>/dev/null
}
share() { # <table-file> <kind-or-name>  -> sum of shares
    awk -v k="$2" '{ if ($0 ~ ("kind=" k " ") || $0 ~ ("name=" k " ")) { sub(/.*share=/, ""); s += $0 } } END { printf "%.1f", s }' "$1"
}

mkdir -p "$TMPD/new" "$TMPD/old"
git worktree add --detach "$BT" "${BASE:-HEAD~1}" >/dev/null 2>&1 || { echo "base worktree failed"; exit 1; }
run_tree "$ROOT" "$TMPD/new" &
run_tree "$BT" "$TMPD/old" &
wait
for t in new old; do
    S="$TMPD/$t/o/serial.txt"
    python3 tools/menualive/check.py table "$S" > "$TMPD/$t.tab" 2>&1
    python3 tools/menualive/check.py cpu "$S" notkind:idle > "$TMPD/$t.busy" 2>&1
    [ -n "${KEEP:-}" ] && { mkdir -p "$KEEP"; cp "$S" "$KEEP/$t.serial.txt"; cp "$TMPD/$t.tab" "$KEEP/$t.tab"; }
    echo "== $t =="; head -8 "$TMPD/$t.tab" | sed 's/^/        /'; sed 's/^/        /' "$TMPD/$t.busy"
done
pct() { sed -n 's/.*share=\([-0-9.]*\).*/\1/p' "$1" | head -1; }
b=$(pct "$TMPD/new.busy")
awk -v s="${b:--1}" 'BEGIN{exit !(s >= 0 && s < 15)}' && ok "widget method: the core is ${b} % busy (limit 15 %)" || bad "widget method: ${b:-?} % busy (limit 15 %)"
tb=$(share "$TMPD/new.tab" taskbar); st=$(share "$TMPD/new.tab" starter); bo=$(share "$TMPD/new.tab" boot)
[ -s "$TMPD/new.tab" ] && ! grep -q 'share=-1' "$TMPD/new.tab" || bad "no usable ps listings in the new run"
awk -v s="$tb" 'BEGIN{exit !(s < 3)}' && ok "taskbar uses $tb % (limit 3 %)" || bad "taskbar uses $tb % (limit 3 %)"
awk -v s="$st" 'BEGIN{exit !(s < 3)}' && ok "starter uses $st % (limit 3 %)" || bad "starter uses $st % (limit 3 %)"
awk -v s="$bo" 'BEGIN{exit !(s < 15)}' && ok "boot (kernel desktop loop) uses $bo % (limit 15 %)" || bad "boot uses $bo % (limit 15 %)"
mx=$(grep -a 'kind=user' "$TMPD/new.tab" | head -1 | sed -n 's/.*share=\([0-9.]*\).*/\1/p')
awk -v s="${mx:-0}" 'BEGIN{exit !(s < 5)}' && ok "the busiest user task uses ${mx:-0} % (limit 5 %)" || bad "the busiest user task uses ${mx:-?} % (limit 5 %)"
tbo=$(share "$TMPD/old.tab" taskbar)
awk -v n="$tb" -v o="$tbo" 'BEGIN{exit !(o >= n + 1.0)}' && ok "COUNTER-PROOF: the tree before used $tbo % for the taskbar (now $tb %)" \
    || bad "COUNTER-PROOF: the tree before used $tbo % for the taskbar, now $tb % -- the check does not see the backoff"
echo; echo "IDLEBUDGET: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
