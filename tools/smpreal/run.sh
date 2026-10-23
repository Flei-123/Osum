#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/smpreal/run.sh -- W-SMP2 gate: -smp 4 (q35, Skylake-Client), `cat /proc/cpus`, four burn tasks, kick IPI.
# Proves: /proc/cpus head + per-core lines, boot line "smp: N of M online", that with the kick MORE than one core takes load
# (busy% per core), and counter-proofs `nosmp` (1 core, why=nosmp) and `nokick` (kick=off, 0 kicks sent).
# Run through heavy:  /root/jarvis/bin/heavy bash tools/smpreal/run.sh     (SMPREAL_ACCELS="kvm tcg" to choose)
set -uo pipefail
cd "$(dirname "$0")/../.."
export FIRNLIB="${FIRNLIB:-$(pwd)/lib}"
pass=0; fail=0
ok()  { pass=$((pass+1)); printf '  OK    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }
has() { grep -qaF -- "$2" "$1" && ok "$3" || bad "$3 -- '$2' missing"; }
D=$(mktemp -d); trap 'rm -rf "$D"' EXIT
ACCELS="${SMPREAL_ACCELS:-$([ -e /dev/kvm ] && echo "kvm tcg" || echo tcg)}"
bash vendor/firn/fetch-firnc.sh >/dev/null 2>&1
PROGS="sh cat echo burn"
mkdir -p "$D/bin"
bash tools/sync/build.sh "$D/bin" 0 $PROGS > "$D/b.txt" 2>&1 && ok "programs build" || { bad "programs"; head -10 "$D/b.txt"; echo "SMPREAL: $pass passed, $fail failed"; exit 1; }
./tools/build-kernel.sh "$D/k0.img" --stufe 0 > "$D/k.txt" 2>&1 && ok "kernel builds" || { bad "kernel"; tail -8 "$D/k.txt"; echo "SMPREAL: $pass passed, $fail failed"; exit 1; }
cat > "$D/s.sh" <<'EOT'
echo ==BOOT==
cat /proc/cpus
burn 60 &
burn 60 &
burn 60 &
burn 60 &
burn 12
echo ==LOAD==
cat /proc/cpus
cat /proc/stat
echo ==END==
EOT
python3 tools/osum/mkfs.py build "$D/d.img" 20000 /lib/ \
    "/lib/mono.ttf=assets/osum-mono.ttf" "/lib/sans.ttf=assets/osum-sans.ttf" \
    /bin/ /t/ /tmp/ /proc/ /dev/ /system/ /etc/ /var/ \
    $(for p in $PROGS; do echo "/bin/$p=$D/bin/$p.elf"; done) \
    "/t/s.sh=$D/s.sh" > "$D/mkfs.txt" 2>&1 || tail -3 "$D/mkfs.txt"
runvm() { # name accel words
    local name=$1 acc=$2 words=$3
    cp "$D/d.img" "$D/d-$name.img"
    timeout 280 qemu-system-x86_64 -accel "$acc" -machine q35 -cpu Skylake-Client -smp 4 -kernel "$D/k0.img" -m 1024 \
        -append "osum vfs smpfrueh $words script=sh /t/s.sh;exit" \
        -serial "file:$D/o-$name.txt" -display none -no-reboot \
        -drive "file=$D/d-$name.img,format=raw,if=ide,index=0" \
        -device isa-debug-exit,iobase=0xf4,iosize=0x04 >/dev/null 2>&1
    tr -cd '\11\12\15\40-\176' < "$D/o-$name.txt" > "$D/$name.klar"
}
# number of cores 1..3 whose busy% >= 15 in the ==LOAD== block
busy_cores() { awk '/==LOAD==/{s=1} /==END==/{s=0} s&&/^cpu[1-9] /{for(i=1;i<=NF;i++)if($i~/^busy=/){v=$i;sub("busy=","",v);sub("%","",v);if(v+0>=15)n++}} END{print n+0}' "$1"; }
for acc in $ACCELS; do
    echo "== accel $acc =="
    runvm base-$acc "$acc" ""
    runvm nokick-$acc "$acc" "nokick"
    runvm nosmp-$acc "$acc" "nosmp"
    B="$D/base-$acc.klar"; K="$D/nokick-$acc.klar"; N="$D/nosmp-$acc.klar"
    has "$B" "cpus_online=4 cpus_madt=4 failed=0" "$acc base: head line 4 online"
    has "$B" "smp: 4 of 4 online, madt=4, failed: none" "$acc base: boot line"
    has "$B" "why=ok" "$acc base: why=ok on the cores"
    has "$B" "kick=on" "$acc base: kick on"
    nb=$(busy_cores "$B"); [ "$nb" -ge 1 ] && ok "$acc base: $nb application core(s) took load (busy>=15%)" || bad "$acc base: no application core took load"
    kb=$(awk '/==LOAD==/{s=1} s&&/^cpus_online/{for(i=1;i<=NF;i++)if($i~/^kicks=/){sub("kicks=","",$i);print $i}}' "$B"); [ "${kb:-0}" -ge 1 ] && ok "$acc base: $kb kick IPIs sent" || { bad "$acc base: no kick sent"; awk '/==LOAD==/{s=1} /==END==/{s=0} s' "$B" | head -14 | cut -c1-200; }
    has "$K" "kick=off" "$acc nokick: kick off"
    kk=$(awk '/==LOAD==/{s=1} s&&/^cpus_online/{for(i=1;i<=NF;i++)if($i~/^kicks=/){sub("kicks=","",$i);print $i}}' "$K"); [ "${kk:-1}" = 0 ] && ok "$acc nokick: 0 kicks sent (counter-proof)" || bad "$acc nokick: kicks=$kk"
    nk=$(busy_cores "$K"); echo "  info  $acc busy application cores: with kick $nb, nokick $nk"
    has "$N" "cpus_online=1 " "$acc nosmp: one core online"
    has "$N" "why=nosmp" "$acc nosmp: why=nosmp"
    has "$N" "failed: c1(apic 1,nosmp" "$acc nosmp: boot line names the reason"
done
echo "SMPREAL: $pass passed, $fail failed"
[ "$fail" = 0 ]
