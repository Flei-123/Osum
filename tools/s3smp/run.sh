#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/s3smp/run.sh -- DD-12 / K-004c: STANDBY (S3) ON MACHINES WITH SEVERAL CORES.
#
# The kernel parks every application processor before the sleep and starts
# it again after the wake-up (kernel/arch/x86_64/smp.fi park_all/unpark_all,
# kernel/pwr/s3.fi suspend). This runner sleeps a QEMU machine with 2 and
# with 4 cores, three times in a row (the kernel's own `s3smp` entry, which
# runs AFTER the other cores stand in their scheduler loops -- the state of a
# running desktop), and reads the per-core counters the kernel prints
# (`s3: kern vor|nach <core> online= ticks= idle= sw=`).
#
# SECTIONS
#   1. build: the kernel and a Limine disk for it (like tools/s3/run.sh).
#   2. -smp 2 and -smp 4, three cycles each: the VM is really suspended every
#      time (QEMU monitor), the kernel parked all but the boot core
#      (online=1), brought all back (online=N), and EVERY core's timer ticks,
#      idle turns AND context switches grew within 300 ms after the
#      wake-up -- a core that is "online" but dead would not move them. The
#      wall clock advanced by the time slept, the kernel ran on to its end.
#   3. counter-check `s3nostart` (cores parked and NOT started again): the
#      same check must FAIL -- proof that the counters measure the restart.
set -uo pipefail
cd "$(dirname "$0")/../.."
. tools/lib/qemu.sh

LIMINE=${LIMINE_DIR:-/root/jarvis/projects/u_DiS4in7esMF1/orientos/vendor/limine}
TMPD=$(mktemp -d)
trap '[ -n "${S3SMP_KEEP:-}" ] && { rm -rf "$S3SMP_KEEP"; mkdir -p "$S3SMP_KEEP"; cp "$TMPD"/l-*.txt "$S3SMP_KEEP"/ 2>/dev/null; }; rm -rf "$TMPD"' EXIT
pass=0; fail=0
ok()  { pass=$((pass+1)); printf '  OK    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }
num() { local name=$1 value=$2 op=$3 want=$4
    if [ -z "$value" ]; then bad "$name: no number (expected $op $want)"; return; fi
    if [ "$value" -"$op" "$want" ] 2>/dev/null; then ok "$name: $value"
    else bad "$name: $value, expected $op $want"; fi
}
has() { grep -qaF "$2" "$1" && ok "$3" || bad "$3 -- '$2' missing"; }

for w in qemu-system-x86_64 sgdisk mkfs.vfat mcopy socat; do
    command -v "$w" >/dev/null 2>&1 || { echo "S3SMP: skipped, $w missing"; exit 0; }
done
[ -x "$LIMINE/limine" ] || { echo "S3SMP: skipped, Limine missing"; exit 0; }

CYCLES=3

mkimg() { # kernel img cmdline
    local t="$TMPD/esp.img"
    printf 'timeout: 0\ndefault_entry: 1\n/s3\n    protocol: multiboot1\n    path: boot():/osum.mb\n    cmdline: %s\n' "$3" > "$TMPD/limine.conf"
    rm -f "$2" "$t"
    dd if=/dev/zero of="$2" bs=1M count=0 seek=48 status=none
    sgdisk --clear --new=1:2048:+40M --typecode=1:EF00 "$2" >/dev/null 2>&1 || return 1
    dd if=/dev/zero of="$t" bs=1M count=40 status=none
    mkfs.vfat -F 32 "$t" >/dev/null 2>&1 || return 1
    mcopy -i "$t" "$LIMINE/limine-bios.sys" ::/limine-bios.sys || return 1
    mcopy -i "$t" "$TMPD/limine.conf" ::/limine.conf || return 1
    mcopy -i "$t" "$1" ::/osum.mb || return 1
    dd if="$t" of="$2" bs=512 seek=2048 conv=notrunc status=none
    rm -f "$t"
    "$LIMINE/limine" bios-install "$2" >/dev/null 2>&1
}

echo "== 1. build =="
bash tools/build-kernel.sh "$TMPD/k" > "$TMPD/b.txt" 2>&1 \
    && ok "kernel built ($(stat -c%s "$TMPD/k") bytes)" \
    || { bad "kernel build"; tail -8 "$TMPD/b.txt" | sed 's/^/        /'; echo "S3SMP: $pass OK, $fail FAIL"; exit 1; }
mkimg "$TMPD/k" "$TMPD/a.img" "s3smp nokbd noproc nofs noring3" && ok "disk with Limine and the kernel" || bad "disk image"
mkimg "$TMPD/k" "$TMPD/n.img" "s3smp s3nostart nokbd noproc nofs noring3" || bad "disk image (nostart)"

# lauf name img smp
lauf() {
    local name=$1 img=$2 smp=$3 cyc=${4:-$CYCLES}
    local sock="$TMPD/mon.$1" L="$TMPD/l-$1.txt"
    rm -f "$L"
    STATES=""; T_SLEEP=(); T_WAKE=()
    timeout 240 $QEMU_X86 -m 256 -smp "$smp" -drive "file=$img,format=raw,if=ide" \
        -serial "file:$L" -display none -no-reboot -vga std \
        -monitor "unix:$sock,server,nowait" \
        -device isa-debug-exit,iobase=0xf4,iosize=0x04 >/dev/null 2>&1 &
    local pid=$! c i st n
    for c in $(seq 1 "$cyc"); do
        for i in $(seq 1 600); do
            n=$(grep -ac 's3: schlafe' "$L" 2>/dev/null)
            [ "${n:-0}" -ge "$c" ] && break
            kill -0 "$pid" 2>/dev/null || break
            sleep 0.2
        done
        sleep 1
        st=$(echo 'info status' | socat - "UNIX-CONNECT:$sock" 2>/dev/null | tr -d '\r' | grep -ao 'VM status: .*' | head -1)
        STATES="$STATES|$st"
        case $st in *suspended*) ;; *) break ;; esac
        sleep 2   # a real sleep of a few seconds, so the clock has something to catch up
        echo system_wakeup | socat - "UNIX-CONNECT:$sock" >/dev/null 2>&1
        for i in $(seq 1 100); do
            n=$(grep -ac 's3: kern nach' "$L" 2>/dev/null)
            [ "${n:-0}" -ge $((c * smp)) ] && break
            kill -0 "$pid" 2>/dev/null || break
            sleep 0.2
        done
    done
    for i in $(seq 1 ${WAITEND:-150}); do kill -0 "$pid" 2>/dev/null || break; sleep 0.2; done
    kill "$pid" 2>/dev/null; wait "$pid" 2>/dev/null; RC=$?
}

# field of the c-th 's3: kern <tag> <core> ...' line
core_val() { # log tag cycle core key
    tr -d '\r' < "$1" | grep -a "^s3: kern $2 $4 " | sed -n "$3p" | grep -oE " $5=[0-9]+" | head -1 | sed 's/.*=//'
}

for smp in 2 4; do
    echo "== 2.$smp. -smp $smp, $CYCLES cycles =="
    lauf "smp$smp" "$TMPD/a.img" "$smp"
    L="$TMPD/l-smp$smp.txt"
    num "the VM really slept (monitor: suspended)" "$(echo "$STATES" | tr '|' '\n' | grep -ac suspended)" eq "$CYCLES"
    num "kernel parked the other cores (online=1)" "$(grep -ac 's3: kerne geparkt online=1' "$L")" eq "$CYCLES"
    num "kernel brought them back (online=$smp)" "$(grep -ac "s3: kerne wieder online=$smp\$" "$L")" eq "$CYCLES"
    num "no refusal (kerne nicht geparkt)" "$(grep -ac 's3: kerne nicht geparkt' "$L")" eq 0
    num "every sleep returned rc=0" "$(grep -ac 's3: smp zyklus=[0-9] rc=0' "$L")" eq "$CYCLES"
    allgrow=1; detail=""
    for c in $(seq 1 "$CYCLES"); do
        for k in $(seq 0 $((smp-1))); do
            tv=$(core_val "$L" vor "$c" "$k" ticks); tn=$(core_val "$L" nach "$c" "$k" ticks)
            iv=$(core_val "$L" vor "$c" "$k" idle); in_=$(core_val "$L" nach "$c" "$k" idle)
            sv=$(core_val "$L" vor "$c" "$k" sw); sn=$(core_val "$L" nach "$c" "$k" sw)
            on=$(core_val "$L" nach "$c" "$k" online)
            # the boot core's idle counter stays 0 (it runs the kernel, not an idle loop) -- its ticks must grow
            idleok=1; [ "$k" != 0 ] && { [ -z "$iv" ] || [ -z "$in_" ] || [ "$in_" -le "$iv" ]; } && idleok=0
            if [ -z "$tv" ] || [ -z "$tn" ] || [ "$tn" -lt $((tv + 10)) ] || [ "$idleok" != 1 ] || [ "$on" != 1 ]; then
                allgrow=0; detail="$detail [cycle $c core $k ticks $tv->$tn idle $iv->$in_ online=$on]"
            fi
            # a core that runs again does at least one context switch (idle <-> task or a tick)
            [ "$sn" -ge "$sv" ] 2>/dev/null || { allgrow=0; detail="$detail [cycle $c core $k sw $sv->$sn]"; }
        done
    done
    [ "$allgrow" = 1 ] && ok "every core: timer ticks AND idle turns grew by at least 10 ticks within 300 ms after each wake-up, all online" \
        || bad "cores did not all run again:$detail"
    # the clock: the wall clock advanced by roughly the time the host kept the VM asleep (>= 2 s)
    slept=$(tr -d '\r' < "$L" | grep -a 's3: uhr schlaf=' | sed 's/.*schlaf=\([0-9]*\) s.*/\1/' | awk '{s+=$1; n++} END {print (n==3 && s>=6) ? 1 : 0}')
    num "the wall clock caught up (3 sleeps of >= 2 s each, summed >= 6 s)" "$slept" eq 1
    has "$L" "kernel: done" "the kernel ran on to its end after the last wake-up"
    num "return code of the machine (isa-debug-exit)" "$RC" eq 21
done

echo "== 3. counter-check s3nostart: cores parked and NOT started again =="
lauf "nostart" "$TMPD/n.img" 2 1
L="$TMPD/l-nostart.txt"
num "slept" "$(echo "$STATES" | tr '|' '\n' | grep -ac suspended)" ge 1
tv=$(core_val "$L" vor 1 1 ticks); tn=$(core_val "$L" nach 1 1 ticks)
# 300 ms of a running core are ~30 timer ticks at 100 Hz; a parked one may take one or two
# more before it halts, never ten
if [ -n "$tn" ] && [ -n "$tv" ] && [ "$tn" -lt $((tv + 10)) ]; then ok "the check catches it: core 1 did not tick ($tv -> $tn)"
else bad "counter-check: core 1 ticks $tv -> $tn (expected no growth)"; fi
on=$(core_val "$L" nach 1 1 online)
[ "$on" = 0 ] && ok "and it is still reported offline" || bad "core 1 online=$on after s3nostart (expected 0)"

echo
echo "S3SMP: $pass OK, $fail FAIL"
[ "$fail" = 0 ]
