#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/wdt/run.sh -- gate for the Intel TCO hardware watchdog (kernel/drv/wdt).
#   /root/jarvis/bin/heavy bash tools/wdt/run.sh        KERNEL=<osum.mb> reuses a kernel, WDT_KEEP=<dir> keeps serial logs,
#   WDT_DESK=<usb image> adds the desktop idle run (WDT_DESK_SECS, default 330).
# QEMU q35 with -global ICH9-LPC.noreboot=false -watchdog-action reset and WITHOUT -no-reboot: a watchdog reset is a second boot.
set -uo pipefail
cd "$(dirname "$0")/../.."
export FIRNLIB="${FIRNLIB:-$(pwd)/lib}"
pass=0; fail=0
ok()  { pass=$((pass+1)); printf '  OK    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }
D=$(mktemp -d); trap 'rm -rf "$D"' EXIT
ACC=$([ -e /dev/kvm ] && echo kvm || echo tcg)
PROGS="sh cat echo sleep"
finish() { [ -n "${WDT_KEEP:-}" ] && { mkdir -p "$WDT_KEEP"; cp "$D"/*.klar "$WDT_KEEP/" 2>/dev/null; }; echo "WDT: $pass passed, $fail failed"; [ "$fail" = 0 ]; exit $?; }
bash vendor/firn/fetch-firnc.sh >/dev/null 2>&1
mkdir -p "$D/bin"
bash tools/sync/build.sh "$D/bin" 0 $PROGS > "$D/b.txt" 2>&1 && ok "programs build" || { bad "programs"; head -10 "$D/b.txt"; finish; }
K="${KERNEL:-}"
if [ -z "$K" ]; then
    K="$D/k.mb"
    ./tools/build-kernel.sh "$K" --stufe 0 > "$D/k.txt" 2>&1 && ok "kernel builds" || { bad "kernel"; tail -8 "$D/k.txt"; finish; }
fi
probe() { echo "echo ==$1=="; echo "cat /proc/watchdog"; }
script_busy() { for i in $(seq 1 18); do probe "P$i"; echo "sleep 2"; done; echo "echo ==END=="; }
script_idle() { probe P1; echo "sleep $1"; probe P2; echo "echo ==END=="; }
script_hang() { probe P1; echo "sleep 3"; probe P2; echo "cat /proc/watchdog_hang"; echo "echo ==AFTER=="; echo "sleep 60"; }
mkimg() {
    local name=$1; shift
    python3 tools/osum/mkfs.py build "$D/$name.img" 20000 /lib/ \
        "/lib/mono.ttf=assets/osum-mono.ttf" "/lib/sans.ttf=assets/osum-sans.ttf" \
        /bin/ /t/ /tmp/ /proc/ /dev/ /system/ /etc/ /var/ \
        $(for p in $PROGS; do echo "/bin/$p=$D/bin/$p.elf"; done) \
        "/t/s.sh=$D/$name.sh" "$@" > "$D/mkfs-$name.txt" 2>&1 || tail -3 "$D/mkfs-$name.txt"
}
script_busy > "$D/busy.sh"; mkimg busy
script_idle 100 > "$D/idle.sh"; mkimg idle
script_hang > "$D/hang.sh"; mkimg hang
printf 'gen=00000002 vor=00000001 v=00 ok=0\n' > "$D/erp.txt"
printf '00000002\n' > "$D/akt.txt"
cp "$D/busy.sh" "$D/trial.sh"; mkimg trial "/system/ERPROBUNG=$D/erp.txt" "/system/AKTUELL=$D/akt.txt"
runvm() {
    local name=$1 img=$2 secs=$3 words=$4
    cp "$D/$img.img" "$D/d-$name.img"
    (timeout -s KILL "$secs" qemu-system-x86_64 -accel "$ACC" -machine q35 -cpu Skylake-Client -smp 2 -m 1024 -kernel "$K" \
        -append "osum vfs $words script=sh /t/s.sh;exit" \
        -serial "file:$D/o-$name.txt" -display none \
        -global ICH9-LPC.noreboot=false -watchdog-action reset \
        -drive "file=$D/d-$name.img,format=raw,if=ide,index=0" </dev/null >/dev/null 2>&1) 2>/dev/null
    tr -cd '\11\12\15\40-\176' < "$D/o-$name.txt" > "$D/$name.klar"
    rm -f "$D/d-$name.img" "$D/o-$name.txt"
}
boots() { grep -ac '^wdt: \(armed\|off\|absent\|failed\)' "$D/$1.klar"; }
boots_until_end() { sed -n '1,/^==END==/p' "$D/$1.klar" | grep -ac '^wdt: \(armed\|off\|absent\|failed\)'; }
has() { grep -qa -- "$2" "$D/$1.klar"; }
val() { awk -v m="==$2==" -v k="$3" '$0==m{s=1;next} /^==/{s=0} s&&$1==k{print $2;exit}' "$D/$1.klar"; }
lastp() { sed -n '1,/^==END==/p' "$D/$1.klar" | grep -ao '^==P[0-9]*==' | tail -1 | tr -d '='; }
second_boot_watchdog() { grep -a '^wdt: armed' "$D/$1.klar" | sed -n 2p | grep -q 'last_boot=watchdog'; }
runvm busy busy 50 "wdt=10" 2>/dev/null &
runvm hang hang 50 "wdt=10 wdthang=15" 2>/dev/null &
runvm spin busy 75 "wdt=10 wdtspin=15" 2>/dev/null &
runvm blind busy 75 "wdt=10 wdtspin=15 wdtblind" 2>/dev/null &
runvm panic busy 50 "wdt=10 wdtpanic=15" 2>/dev/null &
runvm off busy 50 "wdt=off wdthang=15" 2>/dev/null &
runvm procfs hang 50 "wdt=10" 2>/dev/null &
runvm idle idle 125 "" 2>/dev/null &
runvm trial trial 130 "wdt=10 wdthang=12" 2>/dev/null &
wait
echo "== a. wdt=10, busy shell =="
[ "$(boots_until_end busy)" = 1 ] && has busy "==END==" && ok "one boot until the script ends" || bad "boots before ==END==: $(boots_until_end busy)"
has busy "wdt: armed chip=1" && ok "armed on ICH9 (chip=1)" || bad "not armed: $(grep -a '^wdt:' "$D/busy.klar" | head -2)"
L=$(lastp busy); f1=$(val busy P2 feeds); fN=$(val busy "$L" feeds)
[ -n "$f1" ] && [ -n "$fN" ] && [ "$fN" -gt "$f1" ] && ok "feeds rise ($f1 -> $fN at $L)" || bad "feeds do not rise ($f1 -> $fN)"
[ "$(val busy "$L" starved)" = 0 ] && ok "starved 0" || bad "starved $(val busy "$L" starved)"
[ "$(val busy P1 state)" = armed ] && ok "/proc/watchdog state armed" || bad "/proc/watchdog state $(val busy P1 state)"
[ "$(val busy P1 noreboot)" = 0 ] && ok "no_reboot cleared" || bad "no_reboot $(val busy P1 noreboot)"
echo "== b. wdthang=15 (cli; hlt on cpu0) =="
has hang "wdt: planted hang" && ok "hang planted" || bad "hang not planted"
[ "$(boots hang)" -ge 2 ] && ok "watchdog reset: $(boots hang) boots" || bad "no second boot after the hang"
second_boot_watchdog hang && ok "second boot reports last_boot=watchdog" || bad "second boot does not report last_boot=watchdog"
echo "== b2. wdtspin=15 (syscalls spin with interrupts on) =="
has spin "wdt: planted spin" && ok "spin planted" || bad "spin not planted"
[ "$(boots spin)" -ge 2 ] && ok "watchdog reset: $(boots spin) boots" || bad "no second boot after the spin"
has blind "wdt: planted spin" && ok "counter-proof wdtblind: spin planted" || bad "counter-proof: spin not planted"
[ "$(boots blind)" = 1 ] && ok "counter-proof wdtblind: feeding without progress check keeps the spinning system up (1 boot)" || bad "counter-proof wdtblind: $(boots blind) boots"
echo "== c. wdtpanic=15 (kernel fault) =="
has panic "wdt: planted kernel fault" && ok "fault planted" || bad "fault not planted"
has panic "EXCEPTION 14" && ok "kernel reported the fault" || bad "no fault report"
[ "$(boots panic)" -ge 2 ] && ok "watchdog reset after the panic: $(boots panic) boots" || bad "no second boot after the panic"
echo "== d. wdt=off =="
has off "wdt: off by word" && ok "off by word" || bad "not off"
[ "$(boots_until_end off)" = 1 ] && has off "==END==" && [ "$(boots off)" = 1 ] && ok "one boot, no reset (also not after the halt at the end)" || bad "boots: $(boots off)"
has off "wdt: planted hang" && bad "hang planted although off" || ok "nothing planted while off"
[ "$(val off P1 state)" = off ] && ok "/proc/watchdog state off" || bad "/proc/watchdog state $(val off P1 state)"
echo "== e1. default 60 s, shell idle in sleep 100 =="
[ "$(boots idle)" = 1 ] && ok "no false reset over 100 s idle" || bad "false reset: $(boots idle) boots"
has idle "==END==" && ok "script finished" || bad "script did not finish"
[ "$(val idle P1 timeout_s)" = 60 ] && ok "default timeout 60 s" || bad "timeout $(val idle P1 timeout_s)"
echo "== f. cat /proc/watchdog_hang =="
has procfs "==P2==" && ok "probe before the hang" || bad "no probe"
has procfs "wdt: planted hang" && ok "hang requested through /proc/watchdog_hang" || bad "hang not requested"
[ "$(boots procfs)" -ge 2 ] && ok "watchdog reset: $(boots procfs) boots" || bad "no second boot"
second_boot_watchdog procfs && ok "last_boot=watchdog after the reset" || bad "last_boot not watchdog"
echo "  info  after the script ends the kernel halts; the watchdog then resets (boots in the busy run: $(boots busy))"
echo "== g. A/B trial: watchdog resets count as failed starts =="
grep -a '^ab: ' "$D/trial.klar" | head -6 | sed 's/^/        /'
has trial "ab: gen=2 versuch=1 " && ok "first start counted" || bad "first start not counted"
has trial "ab: gen=2 versuch=2 " && ok "watchdog reset counted as second start" || bad "second start not counted"
has trial "ab: ERPROBUNG gescheitert" && ok "next start after watchdog resets: trial declared failed" || bad "trial not declared failed"
if [ -n "${WDT_DESK:-}" ]; then
    SECS="${WDT_DESK_SECS:-330}"
    echo "== e2. desktop image idle $SECS s, default watchdog =="
    cp "$WDT_DESK" "$D/desk.img"
    timeout -s KILL "$SECS" qemu-system-x86_64 -accel "$ACC" -machine q35 -cpu Skylake-Client -smp 4 -m 1024 \
        -drive "file=$D/desk.img,format=raw" -nic user,model=e1000 -serial "file:$D/o-desk.txt" -display none \
        -global ICH9-LPC.noreboot=false -watchdog-action reset </dev/null >/dev/null 2>&1
    tr -cd '\11\12\15\40-\176' < "$D/o-desk.txt" > "$D/desk.klar"; rm -f "$D/desk.img" "$D/o-desk.txt"
    has desk "wdt: armed" && ok "desktop: armed" || bad "desktop: not armed"
    [ "$(boots desk)" = 1 ] && ok "desktop: no false reset in $SECS s" || bad "desktop: $(boots desk) boots"
    has desk "wdt: no progress" && echo "  info  desktop: starve episodes $(grep -ac 'wdt: no progress' "$D/desk.klar")"
fi
finish
