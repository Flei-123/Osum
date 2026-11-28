#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/vbres/run.sh -- gate for the VirtualBox timer-vCPU reserve: with the word vbres the last vCPU never runs tasks.
# Run through heavy:  /root/jarvis/bin/heavy bash tools/vbres/run.sh      VBRES_ACCELS="kvm tcg"  VBRES_KEEP=dir  VBRES_LOOPS=N
set -uo pipefail
cd "$(dirname "$0")/../.."
export FIRNLIB="${FIRNLIB:-$(pwd)/lib}"
pass=0; fail=0
ok()  { pass=$((pass+1)); printf '  OK    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }
D=$(mktemp -d); trap 'rm -rf "$D"' EXIT
ACCELS="${VBRES_ACCELS:-$([ -e /dev/kvm ] && echo kvm || echo tcg)}"
LOOPS="${VBRES_LOOPS:-2400}"
. tools/lib/firnenv.sh
PROGS="sh cat echo burn sleep"
mkdir -p "$D/bin"
bash tools/sync/build.sh "$D/bin" 0 $PROGS > "$D/b.txt" 2>&1 && ok "programs build" || { bad "programs"; head -10 "$D/b.txt"; echo "VBRES: $pass passed, $fail failed"; exit 1; }
./tools/build-kernel.sh "$D/k0.img" --stufe 0 > "$D/k.txt" 2>&1 && ok "kernel builds" || { bad "kernel"; tail -8 "$D/k.txt"; echo "VBRES: $pass passed, $fail failed"; exit 1; }
cat > "$D/s.sh" <<EOT
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
echo ==END==
EOT
bash tools/mkfsfi/mkfs.sh build "$D/d.img" 20000 /lib/ \
    "/lib/mono.ttf=assets/osum-mono.ttf" "/lib/sans.ttf=assets/osum-sans.ttf" \
    /bin/ /t/ /tmp/ /proc/ /dev/ /system/ /etc/ /var/ \
    $(for p in $PROGS; do echo "/bin/$p=$D/bin/$p.elf"; done) \
    "/t/s.sh=$D/s.sh" > "$D/mkfs.txt" 2>&1 || tail -3 "$D/mkfs.txt"
runvm() {
    local name=$1 acc=$2 words=$3 SMP=${4:-4}
    cp "$D/d.img" "$D/d-$name.img"
    timeout 280 qemu-system-x86_64 -accel "$acc" -machine q35 -cpu Skylake-Client -smp $SMP -kernel "$D/k0.img" -m 1024 \
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
    runvm res-$acc "$acc" "vbres"
    runvm off-$acc "$acc" "vbres novbres"
    runvm two-$acc "$acc" "vbres" 2
    runvm one-$acc "$acc" "vbres" 1
    B="$D/base-$acc.klar"; R="$D/res-$acc.klar"; O="$D/off-$acc.klar"; T="$D/two-$acc.klar"; E="$D/one-$acc.klar"
    [ -n "${VBRES_KEEP:-}" ] && { mkdir -p "$VBRES_KEEP"; cp "$D"/*.klar "$VBRES_KEEP/"; }
    for f in "$B" "$R" "$O" "$T" "$E"; do
        grep -qa "==END==" "$f" && ok "$acc $(basename "$f" .klar): script finished" || { bad "$acc $(basename "$f" .klar): script did not finish"; tail -5 "$f"; }
    done
    ! grep -qa "smp: reserved vcpu=" "$B" && ok "$acc base: nothing reserved on a non-VirtualBox host" || bad "$acc base: reserve active without the word"
    grep -qa "smp: reserved vcpu=3" "$R" && ok "$acc vbres: vcpu 3 reserved" || bad "$acc vbres: no reserve line for vcpu 3"
    ! grep -qa "smp: reserved vcpu=" "$O" && ok "$acc novbres: the word wins over vbres" || bad "$acc novbres: reserve active"
    grep -qa "smp: reserved vcpu=1" "$T" && ok "$acc vbres smp 2: vcpu 1 reserved" || bad "$acc vbres smp 2: no reserve line"
    ! grep -qa "smp: reserved vcpu=" "$E" && ok "$acc vbres smp 1: nothing reserved" || bad "$acc vbres smp 1: reserve active"
    bsum=""; rsum=""
    for c in 0 1 2 3; do
        bsum="$bsum cpu$c:$(window_busy "$B" L0 L1 $c)%/sw$(delta "$B" L0 L1 $c switches)"
        rsum="$rsum cpu$c:$(window_busy "$R" L0 L1 $c)%/sw$(delta "$R" L0 L1 $c switches)"
    done
    echo "  info  $acc base load window:$bsum"
    echo "  info  $acc vbres load window:$rsum"
    nb=0
    for c in 1 2 3; do [ "$(window_busy "$B" L0 L1 $c)" -ge 70 ] && nb=$((nb+1)); done
    [ "$nb" -ge 3 ] && ok "$acc base load: cpu1..3 busy (unchanged without the word)" || bad "$acc base load: only $nb of cpu1..3 busy"
    r3=$(window_busy "$R" L0 L1 3); s3=$(delta "$R" L0 L1 3 switches)
    [ "$r3" -le 5 ] && ok "$acc vbres load: cpu3 busy $r3 %" || bad "$acc vbres load: cpu3 busy $r3 % (> 5)"
    [ "$s3" -le 2 ] && ok "$acc vbres load: cpu3 $s3 switches" || bad "$acc vbres load: cpu3 $s3 switches (> 2)"
    nr=0
    for c in 1 2; do [ "$(window_busy "$R" L0 L1 $c)" -ge 70 ] && nr=$((nr+1)); done
    [ "$nr" -ge 2 ] && ok "$acc vbres load: cpu1 and cpu2 busy" || bad "$acc vbres load: only $nr of cpu1, cpu2 busy"
    [ "$(window_busy "$R" L0 L1 0)" -ge 70 ] && ok "$acc vbres load: cpu0 busy" || bad "$acc vbres load: cpu0 not busy"
    t1=$(window_busy "$T" L0 L1 1)
    [ "$t1" -le 5 ] && ok "$acc vbres smp 2: cpu1 busy $t1 %" || bad "$acc vbres smp 2: cpu1 busy $t1 % (> 5)"
done
echo "VBRES: $pass passed, $fail failed"
[ "$fail" = 0 ]
