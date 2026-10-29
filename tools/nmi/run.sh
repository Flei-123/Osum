#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/nmi/run.sh -- gate for the freeze logger (kernel/diag/hang.fi, hangcpu.fi): NMI snapshot of every cpu,
# report in the reboot-safe RAM band, /var/crash/<time>-hang.txt on the next boot.
#   /root/jarvis/bin/heavy bash tools/nmi/run.sh     KERNEL=<osum.mb> reuses a kernel, NMI_KEEP=<dir> keeps logs + reports.
set -uo pipefail
cd "$(dirname "$0")/../.."
export FIRNLIB="${FIRNLIB:-$(pwd)/lib}"
pass=0; fail=0
ok()  { pass=$((pass+1)); printf '  OK    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }
D=$(mktemp -d); trap 'rm -rf "$D"' EXIT
ACC=$([ -e /dev/kvm ] && echo kvm || echo tcg)
PROGS="sh cat echo sleep"
finish() { [ -n "${NMI_KEEP:-}" ] && { mkdir -p "$NMI_KEEP"; cp "$D"/*.klar "$D"/*.hang "$NMI_KEEP/" 2>/dev/null; }; echo "NMI: $pass passed, $fail failed"; [ "$fail" = 0 ]; exit $?; }
bash vendor/firn/fetch-firnc.sh >/dev/null 2>&1
mkdir -p "$D/bin"
bash tools/sync/build.sh "$D/bin" 0 $PROGS > "$D/b.txt" 2>&1 && ok "programs build" || { bad "programs"; head -10 "$D/b.txt"; finish; }
K="${KERNEL:-}"
if [ -z "$K" ]; then
    K="$D/k.mb"
    ./tools/build-kernel.sh "$K" --stufe 0 > "$D/k.txt" 2>&1 && ok "kernel builds" || { bad "kernel"; tail -8 "$D/k.txt"; finish; }
fi
script() { for i in $(seq 1 30); do echo "echo ==P$i=="; echo "sleep 2"; echo "echo tick"; done; echo "echo ==END=="; }
script > "$D/s.sh"
python3 tools/osum/mkfs.py build "$D/base.img" 20000 /lib/ \
    "/lib/mono.ttf=assets/osum-mono.ttf" "/lib/sans.ttf=assets/osum-sans.ttf" \
    /bin/ /t/ /tmp/ /proc/ /dev/ /system/ /etc/ /var/ \
    $(for p in $PROGS; do echo "/bin/$p=$D/bin/$p.elf"; done) \
    "/t/s.sh=$D/s.sh" > "$D/mkfs.txt" 2>&1 || tail -3 "$D/mkfs.txt"
runvm() {
    local name=$1 secs=$2 smp=$3 cpu=$4 words=$5
    [ "$smp" -gt 1 ] && words="smpfrueh $words"
    cp "$D/base.img" "$D/d-$name.img"
    (timeout -s KILL "$secs" qemu-system-x86_64 -accel "$ACC" -machine q35 -cpu "$cpu" -smp "$smp" -m 1024 -kernel "$K" \
        -append "osum vfs $words script=sh /t/s.sh;exit" \
        -serial "file:$D/o-$name.txt" -display none \
        -global ICH9-LPC.noreboot=false -watchdog-action reset \
        -drive "file=$D/d-$name.img,format=raw,if=ide,index=0" </dev/null >/dev/null 2>&1) 2>/dev/null
    tr -cd '\11\12\15\40-\176' < "$D/o-$name.txt" > "$D/$name.klar"
    : > "$D/$name.hang"
    for f in $(python3 tools/osum/mkfs.py list "$D/d-$name.img" 2>/dev/null | grep -ao '/var/crash/[0-9]*-hang\.txt' | sort -u); do
        python3 tools/osum/mkfs.py cat "$D/d-$name.img" "$f" >> "$D/$name.hang" 2>/dev/null
    done
    rm -f "$D/d-$name.img" "$D/o-$name.txt"
}
SK="Skylake-Client,pmu=on"
runvm lock 90 2 "$SK" "wdt=10 wdtlock=15" &
runvm cspin 90 2 "$SK" "wdt=10 wdtcspin=15" &
runvm pmu1 90 1 "$SK" "wdt=10 wdtcspin=15" &
runvm halt 90 2 "$SK" "wdt=10 wdthang=15" &
runvm soft 110 2 "$SK" "wdt=20 wdtspin=15" &
runvm nonmi 75 2 "$SK" "wdt=10 wdtlock=15 nonmi" &
runvm idle 70 2 "$SK" "" &
runvm csts 75 2 "$SK" "wdt=10 wdtlock=15 nonmi wdtnosts" &
runvm cunc 75 2 "$SK" "wdt=10 wdtlock=15 nonmi wdtnosts wdtnomark" &
desk() {
    local img="${NMI_IMG:-}"
    if [ -z "$img" ]; then
        IMAGE_ID=nmigate bash tools/usbimg/build.sh "$D/img" > "$D/img.txt" 2>&1
        img="$D/img/xoffios-usb.img"
    fi
    [ -f "$img" ] && NMI_SMP=4 bash tools/nmi/desktop.sh "$img" "$D/desk.klar" "${NMI_DESK_S:-60}"
}
desk &
wait
boots() { grep -ac '^wdt: \(armed\|off\|absent\|failed\)' "$D/$1.klar"; }
has() { grep -qa -- "$2" "$D/$1.klar"; }
hhas() { grep -qa -- "$2" "$D/$1.hang"; }
cpu0() { awk '/^cpu 0: task=/{f=1} /^cpu [1-9]: task=|^-- /{f=0} f' "$D/$1.hang"; }
report_checks() {
    local n=$1 reason=$2 sym=$3
    [ -s "$D/$n.hang" ] && ok "$n: /var/crash/*-hang.txt written on the next boot" || { bad "$n: no hang file ($(boots $n) boots; $(grep -a '^hang:\|absturz' "$D/$n.klar" | head -4 | tr '\n' '|'))"; return; }
    hhas "$n" "=== OSUM HANG REPORT ===" && ok "$n: report header" || bad "$n: header missing"
    hhas "$n" "reason: $reason" && ok "$n: reason $reason" || bad "$n: reason $(grep -a '^reason' "$D/$n.hang")"
    cpu0 "$n" | grep -qa "[ .]$sym+0x" && ok "$n: cpu 0 stopped in $sym ($(cpu0 "$n" | grep -a -m1 'rip:' | tr -s ' '))" || bad "$n: cpu 0 not in $sym ($(cpu0 "$n" | grep -a -m1 'rip:'))"
    grep -qa '^cpu 0: task=[0-9]* pid=[0-9]* name=' "$D/$n.hang" && ok "$n: task of cpu 0 recorded" || bad "$n: no task line"
    grep -aA20 '^cpu 0: task=' "$D/$n.hang" | grep -qa '^    [a-z_.]*+0x' && ok "$n: backtrace with symbols" || bad "$n: no symbolic backtrace"
}
echo "== a. lock deadlock (irqs off, stress lock taken twice on cpu0), 2 cpus =="
has lock "wdt: planted lock deadlock" && ok "lock: deadlock planted" || bad "lock: not planted"
has lock "^hang: detected reason=hard" && ok "lock: detected ($(grep -a -m1 '^hang: detected' "$D/lock.klar"))" || bad "lock: not detected"
report_checks lock hard lock_take
hhas lock "lock stress held-by cpu=0" && ok "lock: held lock named" || bad "lock: held lock missing ($(grep -aA2 '^locks:' "$D/lock.hang" | tr '\n' '|'))"
hhas lock "waiting-for-lock stress" && ok "lock: waiting cpu names the lock" || bad "lock: waiting lock missing"
hhas lock "irqs=off" && ok "lock: irqs=off recorded" || bad "lock: irq state missing"
echo "== b. spin with irqs off on cpu0, 2 cpus =="
report_checks cspin hard planted_cspin
grep -a 'hang: detected' "$D/cspin.klar" | head -1 | grep -q 'cpu=0' && ok "cspin: culprit cpu 0" || bad "cspin: culprit $(grep -a -m1 'hang: detected' "$D/cspin.klar")"
echo "== c. spin with irqs off, ONE cpu: only the PMU NMI can see it =="
has pmu1 "^hang: on .* pmu=[1-9]" && ok "pmu1: PMU found" || bad "pmu1: no PMU ($(grep -a -m1 '^hang: on' "$D/pmu1.klar"))"
has pmu1 "^hang: detected reason=hard-self" && ok "pmu1: detected by the PMU NMI (hard-self)" || bad "pmu1: not detected"
report_checks pmu1 hard-self planted_cspin
echo "== d. cli; hlt on cpu0 (peer sees it) =="
report_checks halt hard-peer planted_hang
echo "== e. soft lockup: syscall spins with irqs on =="
has soft "wdt: planted spin" && ok "soft: spin planted" || bad "soft: not planted"
has soft "^hang: detected reason=\(soft\|stall\)" && ok "soft: logged ($(grep -a -m1 '^hang: detected' "$D/soft.klar"))" || bad "soft: not logged"
[ -s "$D/soft.hang" ] && ok "soft: hang file after the watchdog reset" || bad "soft: no hang file ($(boots soft) boots)"
cpu0 soft | grep -qaE 'rip: (wdt\.sys_hook|apic\.tsc)\+0x' && ok "soft: rip in the spin or its interrupt tick read" || bad "soft: rip $(cpu0 soft | grep -a -m1 'rip:')"
hhas soft "irqs=on" && ok "soft: irqs=on recorded" || bad "soft: irq state"
echo "== f. counter-proof nonmi: same deadlock, no handler =="
has nonmi "hang: off by word nonmi" && ok "nonmi: logger off" || bad "nonmi: not off"
[ "$(boots nonmi)" -ge 2 ] && ok "nonmi: watchdog still resets ($(boots nonmi) boots)" || bad "nonmi: no reset"
! grep -qa '^cpu 0: task=' "$D/nonmi.hang" && ok "nonmi: no snapshot (cause lost without the handler)" || bad "nonmi: snapshot exists"
hhas nonmi "snapshot: none" && ok "nonmi: minimal report names the lost snapshot" || bad "nonmi: no minimal report ($(head -c 200 "$D/nonmi.hang" | tr '\n' '|'))"
has nonmi "^hang: detected" && bad "nonmi: detected although off" || ok "nonmi: nothing detected"
lastboots() { grep -a '^wdt: armed' "$D/$1.klar" | sed -n 's/.*last_boot=\([a-z]*\).*/\1/p' | tr '\n' ' '; }
echo "== f2. last_boot after the reset =="
[ "$(lastboots halt | cut -d" " -f1-2)" = "normal watchdog" ] && ok "halt: last_boot normal then watchdog" || bad "halt: last_boot sequence '$(lastboots halt)'"
[ "$(lastboots nonmi | cut -d' ' -f1-2)" = "normal watchdog" ] && ok "nonmi: last_boot watchdog from the TCO status" || bad "nonmi: last_boot '$(lastboots nonmi)'"
[ "$(lastboots csts | cut -d' ' -f1-2)" = "normal watchdog" ] && ok "csts: last_boot watchdog from the CMOS mark alone (TCO bits ignored)" || bad "csts: last_boot '$(lastboots csts)'"
hhas csts "source: planted" && ok "csts: minimal hang report names the planted source" || bad "csts: report $(head -c 200 "$D/csts.hang" | tr '\n' '|')"
[ "$(lastboots cunc | cut -d' ' -f1-2)" = "normal unclean" ] && ok "cunc: unmarked reset without TCO bits reads unclean" || bad "cunc: last_boot '$(lastboots cunc)'"
[ "$(lastboots idle | cut -d" " -f1)" = "normal" ] && ok "idle: last_boot normal" || bad "idle: last_boot '$(lastboots idle)'"
echo "== g. no false alarm in a normal run =="
has idle "==P20==" && ok "idle: script runs" || bad "idle: script stuck"
has idle "^hang: detected" && bad "idle: false alarm $(grep -a -m1 '^hang: detected' "$D/idle.klar")" || ok "idle: no false alarm"
[ "$(boots idle)" = 1 ] && ok "idle: one boot" || bad "idle: $(boots idle) boots"
echo "== h. desktop image, 4 cpus, PMU on: login and ${NMI_DESK_S:-60} s on the desktop without a crash =="
if [ ! -s "$D/desk.klar" ]; then
    bad "desk: no serial log ($(tail -2 "$D/img.txt" 2>/dev/null | tr '\n' '|'))"
else
    has desk "^hang: on .* pmu=[1-9]" && ok "desk: logger on with PMU" || bad "desk: $(grep -a -m1 '^hang:' "$D/desk.klar")"
    grep -q '^logged-in 1' "$D/desk.klar.steps" && ok "desk: logged in" || bad "desk: login failed ($(tr '\n' ' ' < "$D/desk.klar.steps"))"
    grep -q '^settled 1' "$D/desk.klar.steps" && ok "desk: desktop survived the settle time" || bad "desk: did not settle"
    n=$(grep -ac 'EXCEPTION\|ABSTURZ' "$D/desk.klar"); [ "$n" = 0 ] && ok "desk: no crash" || bad "desk: $n crash lines ($(grep -a -m1 'EXCEPTION' "$D/desk.klar"))"
    has desk "^hang: detected" && bad "desk: false alarm $(grep -a -m1 '^hang: detected' "$D/desk.klar")" || ok "desk: no false alarm"
    [ "$(boots desk)" = 1 ] && ok "desk: one boot" || bad "desk: $(boots desk) boots"
fi
finish
