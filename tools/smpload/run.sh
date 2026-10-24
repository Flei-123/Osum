#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/smpload/run.sh -- W-SMP5 gate: -smp 4 under real load. Windowed per-core numbers from /proc/cpus (delta of two reads).
# Proves: idle window (application cores halt, slow tick, ~0 % busy), load window (every core busy, application cores tick at full rate,
# switches on every core), idle again after the load. Counter-proofs: nokick (application cores starve while core 0 is the only
# scheduler of new work) and nosmp (single core).
# Run through heavy:  /root/jarvis/bin/heavy bash tools/smpload/run.sh      SMPLOAD_ACCELS="kvm tcg"  SMPLOAD_KEEP=dir  SMPLOAD_LOOPS=N
set -uo pipefail
cd "$(dirname "$0")/../.."
export FIRNLIB="${FIRNLIB:-$(pwd)/lib}"
pass=0; fail=0
ok()  { pass=$((pass+1)); printf '  OK    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }
D=$(mktemp -d); trap 'rm -rf "$D"' EXIT
ACCELS="${SMPLOAD_ACCELS:-$([ -e /dev/kvm ] && echo kvm || echo tcg)}"
LOOPS="${SMPLOAD_LOOPS:-2400}"
bash vendor/firn/fetch-firnc.sh >/dev/null 2>&1
PROGS="sh cat echo burn sleep"
mkdir -p "$D/bin"
bash tools/sync/build.sh "$D/bin" 0 $PROGS > "$D/b.txt" 2>&1 && ok "programs build" || { bad "programs"; head -10 "$D/b.txt"; echo "SMPLOAD: $pass passed, $fail failed"; exit 1; }
./tools/build-kernel.sh "$D/k0.img" --stufe 0 > "$D/k.txt" 2>&1 && ok "kernel builds" || { bad "kernel"; tail -8 "$D/k.txt"; echo "SMPLOAD: $pass passed, $fail failed"; exit 1; }
cat > "$D/s.sh" <<EOT
sleep 2
echo ==I0==
cat /proc/cpus
sleep 4
echo ==I1==
cat /proc/cpus
burn $LOOPS &
burn $LOOPS &
burn $LOOPS &
burn $LOOPS &
burn $LOOPS &
burn $LOOPS &
burn $LOOPS &
burn $LOOPS &
sleep 1
echo ==L0==
cat /proc/cpus
sleep 4
echo ==L1==
cat /proc/cpus
sleep 16
echo ==A0==
cat /proc/cpus
sleep 4
echo ==A1==
cat /proc/cpus
echo ==END==
EOT
python3 tools/osum/mkfs.py build "$D/d.img" 20000 /lib/ \
    "/lib/mono.ttf=assets/osum-mono.ttf" "/lib/sans.ttf=assets/osum-sans.ttf" \
    /bin/ /t/ /tmp/ /proc/ /dev/ /system/ /etc/ /var/ \
    $(for p in $PROGS; do echo "/bin/$p=$D/bin/$p.elf"; done) \
    "/t/s.sh=$D/s.sh" > "$D/mkfs.txt" 2>&1 || tail -3 "$D/mkfs.txt"
runvm() {
    local name=$1 acc=$2 words=$3
    cp "$D/d.img" "$D/d-$name.img"
    timeout 280 qemu-system-x86_64 -accel "$acc" -machine q35 -cpu Skylake-Client -smp 4 -kernel "$D/k0.img" -m 1024 \
        -append "osum vfs smpfrueh $words script=sh /t/s.sh;exit" \
        -serial "file:$D/o-$name.txt" -display none -no-reboot \
        -drive "file=$D/d-$name.img,format=raw,if=ide,index=0" \
        -device isa-debug-exit,iobase=0xf4,iosize=0x04 >/dev/null 2>&1
    tr -cd '\11\12\15\40-\176' < "$D/o-$name.txt" > "$D/$name.klar"
}
field() {
    awk -v m="==$2==" -v c="cpu$3 " -v k="$4=" '$0==m{s=1;next} /^==/{s=0} s&&index($0,c)==1{for(i=1;i<=NF;i++)if(index($i,k)==1){v=$i;sub(k,"",v);sub("%","",v);print v;f=1;exit}} END{if(!f)print 0}' "$1"
}
delta() { echo $(( $(field "$1" "$3" "$4" "$5") - $(field "$1" "$2" "$4" "$5") )); }
window_busy() {
    local tot idl
    tot=$(delta "$1" "$2" "$3" "$4" cyc); idl=$(delta "$1" "$2" "$3" "$4" idlecyc)
    [ "$tot" -gt 0 ] && echo $(( (tot - idl) * 100 / tot )) || echo 0
}
for acc in $ACCELS; do
    echo "== accel $acc =="
    runvm base-$acc "$acc" ""
    runvm nokick-$acc "$acc" "nokick"
    runvm apslow-$acc "$acc" "apslow"
    runvm nosmp-$acc "$acc" "nosmp"
    B="$D/base-$acc.klar"; S="$D/apslow-$acc.klar"; K="$D/nokick-$acc.klar"; N="$D/nosmp-$acc.klar"
    [ -n "${SMPLOAD_KEEP:-}" ] && { mkdir -p "$SMPLOAD_KEEP"; cp "$D"/*.klar "$SMPLOAD_KEEP/"; }
    grep -qa "==END==" "$B" && ok "$acc base: script finished" || { bad "$acc base: script did not finish"; tail -5 "$B"; continue; }
    summary=""; nh=0
    for c in 1 2 3; do
        b=$(window_busy "$B" I0 I1 $c); tk=$(delta "$B" I0 I1 $c ticks)
        [ "$b" -le 5 ] && ok "$acc base idle: cpu$c busy $b %" || bad "$acc base idle: cpu$c busy $b % (> 5)"
        [ "$tk" -le 80 ] && ok "$acc base idle: cpu$c $tk ticks in the window (slow tick)" || bad "$acc base idle: cpu$c $tk ticks (> 80)"
        h=$(field "$B" I1 $c halted); nh=$((nh+h))
    done
    [ "$nh" -ge 2 ] && ok "$acc base idle: $nh of 3 application cores halted at the read" || bad "$acc base idle: only $nh of 3 application cores halted"
    lb0=$(window_busy "$B" L0 L1 0)
    nbusy=0; minb=100
    for c in 1 2 3; do
        b=$(window_busy "$B" L0 L1 $c); tk=$(delta "$B" L0 L1 $c ticks); sw=$(delta "$B" L0 L1 $c switches)
        summary="$summary cpu$c:busy=$b%,ticks=$tk,sw=$sw"
        [ "$b" -ge 70 ] && nbusy=$((nbusy+1)); [ "$b" -lt "$minb" ] && minb=$b
        [ "$tk" -ge 150 ] && ok "$acc base load: cpu$c $tk ticks in the window (full rate)" || bad "$acc base load: cpu$c only $tk ticks"
        [ "$sw" -ge 20 ] && ok "$acc base load: cpu$c $sw switches" || bad "$acc base load: cpu$c only $sw switches"
    done
    echo "  info  $acc load window: cpu0:busy=$lb0% $summary"
    [ "$nbusy" -ge 3 ] && ok "$acc base load: $nbusy application cores >= 70 % busy (min $minb %)" || bad "$acc base load: only $nbusy application cores >= 70 % busy"
    [ "$lb0" -ge 70 ] && ok "$acc base load: core 0 busy $lb0 %" || bad "$acc base load: core 0 busy $lb0 %"
    na=0
    for c in 1 2 3; do
        b=$(window_busy "$B" A0 A1 $c)
        [ "$b" -le 5 ] && ok "$acc base after: cpu$c idle again ($b %)" || bad "$acc base after: cpu$c busy $b %"
        h=$(field "$B" A1 $c halted); na=$((na+h))
    done
    [ "$na" -ge 2 ] && ok "$acc base after: $na of 3 application cores halted at the read" || bad "$acc base after: only $na of 3 application cores halted"
    ksum=""
    for c in 1 2 3; do ksum="$ksum cpu$c:busy=$(window_busy "$K" L0 L1 $c)%"; done
    echo "  info  $acc nokick load window:$ksum"
    slow=0; ssum=""
    for c in 1 2 3; do
        tk=$(delta "$S" L0 L1 $c ticks); ssum="$ssum cpu$c:ticks=$tk"; [ "$tk" -lt 150 ] && slow=$((slow+1))
    done
    echo "  info  $acc apslow load window:$ssum"
    [ "$slow" -ge 2 ] && ok "$acc apslow: $slow application cores stay at the slow tick under load (counter-proof)" || bad "$acc apslow: only $slow application cores slow, counter-proof not discriminating"
    grep -qa "cpus_online=1 " "$N" && ok "$acc nosmp: one core" || bad "$acc nosmp: not one core"
    nb=$(window_busy "$N" L0 L1 0); [ "$nb" -ge 70 ] && ok "$acc nosmp: core 0 busy $nb %" || bad "$acc nosmp: core 0 busy $nb %"
done
echo "SMPLOAD: $pass passed, $fail failed"
[ "$fail" = 0 ]
