#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/protocol/run.sh -- LOG ROUND: THE FIVE MEASUREMENTS.
#
set -uo pipefail
cd "$(dirname "$0")/../.."

QEMU_X86=${QEMU_X86:-qemu-system-x86_64}
export FIRNLIB="$(pwd)/lib"
FIRNC=${FIRNC:-vendor/firn/bin/firnc}
ULD=kernel/user/user.ld
PROGS="sh ls cat echo log crash krach"
source_of() { case $1 in krach) echo noise ;; *) echo "$1" ;; esac; }
BLOCKS=4096

TMPD=$(mktemp -d)
trap 'rm -rf "$TMPD"' EXIT

pass=0
fail=0
ok()  { pass=$((pass+1)); printf '  OK    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }
num() { # name value op expected
    local name=$1 value=$2 op=$3 want=$4
    if [ -z "$value" ]; then bad "$name: no number found (expected $op $want)"; return; fi
    if [ "$value" -"$op" "$want" ] 2>/dev/null; then ok "$name: $value"
    else bad "$name: $value, expected $op $want"; fi
}
has() { grep -qaF -- "$2" "$1" && ok "$3" || bad "$3 -- '$2' is missing"; }
same() { [ "$2" = "$3" ] && ok "$1: $3" || bad "$1: '$3' instead of '$2'"; }
value() { grep -oaE "$2" "$1" | head -1 | grep -oE '[0-9]+$'; }

bash vendor/firn/fetch-firnc.sh >/dev/null || { echo "fetch-firnc.sh failed"; exit 1; }
command -v "$QEMU_X86" >/dev/null 2>&1 || {
    echo "LOG: skipped, $QEMU_X86 is missing"; exit 0; }

ACCEL=""
ACCELNAME="tcg"
if [ -r /dev/kvm ] && [ -w /dev/kvm ]; then
    ACCEL="-accel kvm -cpu host"
    ACCELNAME="kvm"
fi
echo "LOG: acceleration = $ACCELNAME"

run_vm() { # image cmdline output [more qemu args]
    local image=$1 cmdline=$2 out=$3
    shift 3
    timeout 240 $QEMU_X86 $ACCEL -kernel "$image" -m 256 -append "$cmdline" \
        -serial "file:$out" -display none -no-reboot "$@" \
        -device isa-debug-exit,iobase=0xf4,iosize=0x04 >/dev/null 2>&1
    return $?
}

run_vm_disk() { # image cmdline output disk
    run_vm "$1" "$2" "$3" -drive "file=$4,format=raw,if=ide,index=0"
}

echo "== 1. build: kernel with symbol table, and the three new programs =="
bash tools/build-kernel.sh "$TMPD/k0.mb" > "$TMPD/build.log" 2>&1 \
    && ok "kernel built ($(stat -c%s "$TMPD/k0.mb") Oktette)" \
    || { bad "the kernel cannot be built"
         sed 's/^/        /' "$TMPD/build.log" | head -15
         echo "LOG: $pass passed, $fail failed"; exit 1; }
K0="$TMPD/k0.mb"

n=$(grep -oaE 'symtab: [0-9]+ Symbole' "$TMPD/build.log" | grep -oE '[0-9]+')
num "symbols in the image" "$n" gt 3000
n=$(grep -oaE '[0-9]+ Zeilen' "$TMPD/build.log" | head -1 | grep -oE '[0-9]+')
num "source line entries in the image" "$n" gt 20000

bash tools/build-kernel.sh "$TMPD/knosym.mb" --ohne-symbole \
    > "$TMPD/build2.log" 2>&1 \
    && ok "--without-symbols builds as well" || bad "--without-symbols does not build"
if [ -f "$TMPD/knosym.mb" ]; then
    a=$(stat -c%s "$K0"); b=$(stat -c%s "$TMPD/knosym.mb")
    echo "        price of the tables: $((a - b)) octets ($a against $b)"
    num "the tables really cost space" "$((a - b))" gt 100000
fi

for f in boot isr switch smp hv; do
    as --64 -o "$TMPD/$f.o" "kernel/arch/x86_64/$f.s" 2>"$TMPD/as.err" \
        || bad "$f.s cannot be assembled"
done
as --64 -o "$TMPD/crt.o" kernel/user/crt.s 2>/dev/null || bad "crt.s"
for p in $PROGS; do
    q=$(source_of "$p")
    "$FIRNC" "kernel/user/$q.fi" -o "$TMPD/$p.o" >"$TMPD/e$p" 2>&1 \
        || { bad "$q.fi does not compile"; sed 's/^/        /' "$TMPD/e$p" | head -6; }
    ld -T "$ULD" --defsym=USER_ENTRY="_F0.u_start" \
        -o "$TMPD/$p.elf" "$TMPD/crt.o" "$TMPD/$p.o" 2>/dev/null \
        || bad "$p cannot be linked"
done
[ -f "$TMPD/log.elf" ] && ok "/bin/log, /bin/crash and /bin/krach built" \
                       || bad "the new programs are missing"

kn=$(grep -aoE 'const SYS_OSUM_KLOG: u64 = [0-9]+' kernel/sys/sys.fi | grep -oE '[0-9]+$')
un=$(grep -aoE 'const SYS_KLOG: u64 = [0-9]+' kernel/user/ulib.fi | grep -oE '[0-9]+$')
[ "$kn" = "$un" ] && [ -n "$kn" ] \
    && ok "SYS_KLOG is the same number in the kernel and in ulib ($kn)" \
    || bad "SYS_KLOG: kernel=$kn ulib=$un"
kn=$(grep -aoE 'const SYS_OSUM_KRACH: u64 = [0-9]+' kernel/sys/sys.fi | grep -oE '[0-9]+$')
un=$(grep -aoE 'const SYS_KRACH: u64 = [0-9]+' kernel/user/ulib.fi | grep -oE '[0-9]+$')
[ "$kn" = "$un" ] && [ -n "$kn" ] \
    && ok "SYS_KRACH is the same number in the kernel and in ulib ($kn)" \
    || bad "SYS_KRACH: kernel=$kn ulib=$un"

python3 tools/kernel/memmap.py kernel > "$TMPD/map.txt" 2>&1
has "$TMPD/map.txt" "0 collisions" "the memory map of kdata stays free of collisions"
KDS=$(sed -n 's/^const KDATA_SIZE: u64 = \(0x[0-9A-Fa-f]*\).*/\1/p' kernel/lib/kstate.fi | head -1)
grep -q "$KDS" "$TMPD/map.txt" \
    && ok "kdata is $KDS large (the ring needs 64 KiB contiguous)" \
    || bad "kdata does not have the expected size ($KDS)"
a=$(grep -aoE 'KDATA_SIZE, 0x[0-9A-F]+' kernel/arch/x86_64/boot.s | head -1 | grep -oE '0x[0-9A-F]+')
b=$(grep -aoE 'const KDATA_SIZE: u64 = 0x[0-9A-F]+' kernel/lib/kstate.fi | grep -oE '0x[0-9A-F]+')
[ "$a" = "$b" ] && ok "KDATA_SIZE is the same in boot.s and kstate.fi ($a)" \
                || bad "KDATA_SIZE: boot.s=$a kstate.fi=$b"

echo "== 2. (a) four cores, ten thousand lines each, one ring =="
run_vm "$K0" "nokbd nosched noproc nofs noring3 logall lograce" \
    "$TMPD/race.txt" -smp 4
if grep -qa 'smp: lograce' "$TMPD/race.txt"; then
    z=$(value "$TMPD/race.txt" 'lines=[0-9]+')
    g=$(value "$TMPD/race.txt" 'total=[0-9]+')
    r=$(value "$TMPD/race.txt" 'ring=[0-9]+')
    ro=$(value "$TMPD/race.txt" 'rotated=[0-9]+')
    kp=$(value "$TMPD/race.txt" 'broken=[0-9]+')
    ke=$(value "$TMPD/race.txt" 'cores=[0-9]+')
    num "cores that wrote" "$ke" eq 4
    num "lines the cores wrote" "$z" eq 40000
    num "lines the ring counted (none may be lost)" "$g" eq 40000
    num "lines still in the ring" "$r" eq 510
    num "lines the ring overwrote (40000 - 510)" "$ro" eq 39490
    num "interleaved entries (head and text from different cores)" "$kp" eq 0
else
    bad "the four-core run delivered no lograce line"
    tail -5 "$TMPD/race.txt" | sed 's/^/        /'
fi

echo "== 3. (e) what a filtered-out call costs =="
ms=$(value "$TMPD/race.txt" 'logbank calls=1000000  ns=[0-9]+  ms=[0-9]+')
je=$(value "$TMPD/race.txt" 'ns_je_10=[0-9]+')
if [ -n "$ms" ]; then
    echo "        1 M calls at level debug (filtered out): $ms ms, $je ns per 10 calls, $ACCELNAME"
    if [ "$ACCELNAME" = kvm ]; then
        num "one million filtered-out calls in milliseconds" "$ms" lt 100
    else
        num "one million filtered-out calls in milliseconds (TCG, only a bound against outliers)" \
            "$ms" lt 1000
        echo "        (the acceptance threshold of 100 ms applies to KVM; this ran on TCG)"
    fi
else
    bad "no measurement of the fast path found"
fi

echo "== 4. the log in operation: sources, levels, /proc and /dev =="
run_vm "$K0" "nokbd nosched noproc noring3 logdebug" "$TMPD/dbg.txt"
n=$(grep -ac ' [DIWE] ' "$TMPD/dbg.txt")
num "log lines on the serial line with logdebug" "$n" ge 1
grep -qaE '\[ *[0-9]+\] [0-9]+/[0-9]+ [DIWE] [a-z]+ *: ' "$TMPD/dbg.txt" \
    && ok "the format is right: [time] core/pid level source: text" \
    || bad "no line in the agreed format"
run_vm "$K0" "nokbd nosched noproc nofs noring3 logquiet" "$TMPD/quiet.txt"
n2=$(grep -ac ' [DI] ' "$TMPD/quiet.txt")
num "debug/info lines with logquiet (the threshold must work)" "${n2:-0}" eq 0

echo "== 5. the disk, the programs on it and the restart =="
printf 'protokoll\n' > "$TMPD/readme.txt"
SPEC="/bin/"
for p in $PROGS; do SPEC="$SPEC /bin/$p=$TMPD/$p.elf"; done
bash tools/mkfsfi/mkfs.sh build "$TMPD/disk.img" $BLOCKS $SPEC \
    /proc/ /dev/ /mnt/ /var/ /var/crash/ \
    /readme.txt="$TMPD/readme.txt" > "$TMPD/mkfs.txt" 2>&1 \
    && ok "OFS image with $BLOCKS blocks built" \
    || { bad "mkfs.py failed"; sed 's/^/        /' "$TMPD/mkfs.txt" | head; }

QUIET="nokbd vfs"
# ---- (d) A NULL POINTER IN RING 3.
run_vm_disk "$K0" "osum $QUIET logall krach script=krach prog;echo WEITERLAEUFT;log -n 3;exit" \
    "$TMPD/r3.txt" "$TMPD/disk.img"
rc=$?
has "$TMPD/r3.txt" "user fault" "(d) the null pointer in ring 3 was handled as a user fault"
has "$TMPD/r3.txt" "process killed" "(d) the program died"
has "$TMPD/r3.txt" "WEITERLAEUFT" "(d) the system keeps running afterwards"
report_path=$(grep -aoE '/var/crash/[0-9]+\.txt' "$TMPD/r3.txt" | head -1)
[ -n "$report_path" ] && ok "(d) a report was stored: $report_path" \
                 || bad "(d) no report was stored"
grep -qa 'crash: report' "$TMPD/r3.txt" \
    && ok "(d) the kernel says what became of the report" \
    || bad "(d) the kernel is silent about the report"

run_vm_disk "$K0" "osum $QUIET logall krach script=krach kern;exit" \
    "$TMPD/panicdisk.txt" "$TMPD/disk.img"
has "$TMPD/panicdisk.txt" "*** EXCEPTION" "(c) the forced kernel panic took place"
report_path=$(grep -aoE '/var/crash/[0-9]+\.txt' "$TMPD/panicdisk.txt" | tail -1)
[ -n "$report_path" ] && ok "(c) the kernel stored a report despite the panic: $report_path" \
                 || bad "(c) no report was stored on the panic"

run_vm_disk "$K0" "osum $QUIET script=crash;exit" \
    "$TMPD/after.txt" "$TMPD/disk.img"
has "$TMPD/after.txt" "crash: a report from the last boot is present" \
    "(c) the kernel finds the mark of the last run again"
has "$TMPD/after.txt" "A REPORT FROM THE LAST START" \
    "(c) /bin/crash reports it to the user"
has "$TMPD/after.txt" "CRASH REPORT" "(c) the report itself is shown"
has "$TMPD/after.txt" "-- backtrace" "(c) the report contains the backtrace"
has "$TMPD/after.txt" "-- log" "(c) the report contains the last log lines"
has "$TMPD/after.txt" "CRASH REPORT (KERNEL)" "(c) it is the report of the kernel panic"
n=$(grep -acE '^  #[0-9]+ [a-z]+\.[a-z_0-9]+\+0x' "$TMPD/after.txt")
num "(c) resolved symbols in the report" "${n:-0}" ge 1

# ---- /bin/log
run_vm_disk "$K0" "osum $QUIET logall script=log -z;log -p HALLOWELT;log -n 4;exit" \
    "$TMPD/tool.txt" "$TMPD/disk.img"
has "$TMPD/tool.txt" "lines:" "/bin/log -z shows the numbers of the ring"
has "$TMPD/tool.txt" "HALLOWELT" "/bin/log -p writes a line into the ring"
grep -qa 'prog *: HALLOWELT' "$TMPD/tool.txt" \
    && ok "the written line shows as source 'prog' in the ring" \
    || bad "the written line does not appear as a log line"
run_vm_disk "$K0" "osum $QUIET logall script=cat /proc/klog;exit" \
    "$TMPD/proc.txt" "$TMPD/disk.img"
has "$TMPD/proc.txt" "# klog" "/proc/klog delivers a head with the numbers"
run_vm_disk "$K0" "osum $QUIET logall script=cat /dev/klog;exit" \
    "$TMPD/dev.txt" "$TMPD/disk.img"
grep -qaE '\[ *[0-9]+\] [0-9]+/[0-9]+ [DIWE] ' "$TMPD/dev.txt" \
    && ok "/dev/klog delivers the same lines in the same format" \
    || bad "/dev/klog delivers nothing readable"

run_vm_disk "$K0" "osum $QUIET script=krach kern;echo LEBTNOCH;exit" \
    "$TMPD/latch.txt" "$TMPD/disk.img"
has "$TMPD/latch.txt" "LEBTNOCH" \
    "without 'krach' on the kernel command line the call 1861 is refused"

echo "== 5b. K-011: the report survives the warm restart in memory =="
#
run_vm_disk "$K0" "osum $QUIET logall krach script=krach kernfs;exit" \
    "$TMPD/cold1.txt" "$TMPD/disk.img"
has "$TMPD/cold1.txt" "on request, kind 2" "K-011: the panic with the lock held took place"
has "$TMPD/cold1.txt" "crash: filesystem locked, no report" \
    "K-011: the latch forbids the disk (as intended)"
run_vm_disk "$K0" "osum $QUIET logall script=crash;exit" \
    "$TMPD/cold2.txt" "$TMPD/disk.img"
n=$(grep -ac 'aus dem speicher gerettet' "$TMPD/cold2.txt")
num "COUNTER-PROOF cold: nothing is rescued after a cold start" "${n:-0}" eq 0
n=$(grep -ac 'on request, kind 2' "$TMPD/cold2.txt")
num "COUNTER-PROOF cold: no report of the kind-2 panic on the disk" "${n:-0}" eq 0

wsock="$TMPD/warm.sock"
rm -f "$wsock" "$TMPD/warm.txt"
timeout 240 $QEMU_X86 $ACCEL -kernel "$K0" -m 256 \
    -append "osum $QUIET logall krach crashhalt script=crash;krach kernfs;exit" \
    -serial "file:$TMPD/warm.txt" -display none \
    -drive "file=$TMPD/disk.img,format=raw,if=ide,index=0" \
    -monitor "unix:$wsock,server,nowait" \
    -device isa-debug-exit,iobase=0xf4,iosize=0x04 >/dev/null 2>&1 &
wpid=$!
wait_halt() { # how many 'kernel halted'
    local i=0
    while [ $i -lt 600 ]; do
        [ "$(grep -ac 'kernel halted' "$TMPD/warm.txt" 2>/dev/null)" -ge "$1" ] && return 0
        kill -0 "$wpid" 2>/dev/null || return 1
        sleep 0.2; i=$((i + 1))
    done
    return 1
}
if wait_halt 1; then
    ok "K-011 warm: first panic, machine halted"
    python3 - "$wsock" <<'PY'
import socket, sys, time
s = socket.socket(socket.AF_UNIX); s.connect(sys.argv[1]); time.sleep(0.3)
s.recv(4096); s.sendall(b"system_reset\n"); time.sleep(0.5); s.close()
PY
    wait_halt 2 && ok "K-011 warm: started after the reset and halted again" \
        || bad "K-011 warm: no second run after the reset"
else
    bad "K-011 warm: the first panic did not come"
fi
kill "$wpid" 2>/dev/null; wait "$wpid" 2>/dev/null; rm -f "$wsock"
awk '/kernel halted/ { n++; next } n == 1' "$TMPD/warm.txt" > "$TMPD/warm2.txt"
has "$TMPD/warm2.txt" "crash: report rescued from memory" \
    "K-011 warm: the second start finds the report in memory"
grep -qaE 'crash: report +/var/crash/[0-9]+\.txt +written' "$TMPD/warm2.txt" \
    && ok "K-011 warm: and stores it as a file under /var/crash" \
    || bad "K-011 warm: the rescued report was not stored"
has "$TMPD/warm2.txt" "CRASH REPORT (KERNEL)" "K-011 warm: /bin/crash shows it as the kernel report"
has "$TMPD/warm2.txt" "on request, kind 2" "K-011 warm: and it is the report of THIS panic (kind 2 in the log part)"

echo "== 6. (b) the panic screen, really read =="
sock="$TMPD/mon.sock"
rm -f "$sock" "$TMPD/panic.ppm" "$TMPD/panic.txt"
timeout 240 $QEMU_X86 $ACCEL -kernel "$K0" -m 256 \
    -append "nokbd nosched noproc noring3 gfx logall crashhalt krach krachjetzt" \
    -serial "file:$TMPD/panic.txt" -display none -no-reboot \
    -vga std -global VGA.edid=off \
    -monitor "unix:$sock,server,nowait" >/dev/null 2>&1 &
qpid=$!
i=0
while [ $i -lt 900 ]; do
    grep -qa 'kernel halted' "$TMPD/panic.txt" 2>/dev/null && break
    kill -0 "$qpid" 2>/dev/null || break
    sleep 0.2
    i=$((i + 1))
done
sleep 1
python3 tools/gfx/screenshot.py "$sock" "$TMPD/panic.ppm" 25 \
    > "$TMPD/shot.txt" 2>&1
kill "$qpid" 2>/dev/null
wait "$qpid" 2>/dev/null
rm -f "$sock"

if [ -s "$TMPD/panic.ppm" ]; then
    ok "a screenshot of the panic exists ($(stat -c%s "$TMPD/panic.ppm") octets)"
    python3 tools/protocol/screentext.py "$TMPD/panic.ppm" kernel/gfx/font.fi \
        > "$TMPD/screen.txt" 2>"$TMPD/screen.err"
    if [ -s "$TMPD/screen.txt" ]; then
        echo "        --- what is on the screen:"
        sed 's/^/        | /' "$TMPD/screen.txt" | head -32
        has "$TMPD/screen.txt" "KERNEL-PANIK" "(b) the screen says what is going on"
        has "$TMPD/screen.txt" "#PF" "(b) the screen names the exception"
        has "$TMPD/screen.txt" "RUECKSPUR" "(b) the screen has a backtrace section"
        has "$TMPD/screen.txt" "PROTOKOLL" "(b) the screen shows the last log lines"
        has "$TMPD/screen.txt" "KERN 0" "(b) the screen names the core number"
        n=$(grep -oaE '\b(rax|rbx|rcx|rdx|rsi|rdi|rbp|rsp|r8 |r9 |r1[0-5])=0x' \
            "$TMPD/screen.txt" | sort -u | wc -l)
        num "(b) distinct registers on the screen" "$n" eq 16
        chain=$(awk '/-- RUECKSPUR/ { an = 1; next } /^-- / { an = 0 } an { print $1 }' \
            "$TMPD/screen.txt" | sed 's/+.*//' | tr '\n' ' ')
        same "(b) the backtrace on the screen is exactly the call chain" \
            "crash.knall_b crash.knall_a crash.knall stage_late.crash_knall initstage.run initstage.run_all stages.run KERNEL_MAIN long_mode " "$chain"
        n=$(grep -ac '?' "$TMPD/screen.txt")
        num "(b) lines with unreadable cells (the glyphs must match exactly)" \
            "${n:-0}" le 1
    else
        bad "(b) no text could be read from the screenshot"
        sed 's/^/        /' "$TMPD/screen.err" | head -5
    fi
else
    bad "(b) no screenshot was produced"
    sed 's/^/        /' "$TMPD/shot.txt" | head -5
fi
has "$TMPD/panic.txt" "*** EXCEPTION" "(b) the same panic is also on the serial line"
trace_names() { # file -> the names of the kspur lines, one per line
    awk '/^  ktrace:/ { an = 1; next } an && /^      / { print $1; next } an { exit }' "$1" \
        | sed 's/+0x.*//'
}
has "$TMPD/panic.txt" "ktrace: rahmenkette" "(b) the backtrace walks the frame pointers, not the stack"
chain=$(trace_names "$TMPD/panic.txt" | tr '\n' ' ')
same "(b) the serial backtrace is exactly the call chain up to the start" \
    "crash.knall_b crash.knall_a crash.knall stage_late.crash_knall initstage.run initstage.run_all stages.run KERNEL_MAIN long_mode " "$chain"
n=$(grep -acE '^ +[a-z_0-9]+\.[a-z_0-9]+\+0x[0-9a-f]+ \([a-z_0-9]+\.fi:[0-9]+\)$' \
    "$TMPD/panic.txt")
num "(b) resolved symbols with file:line in the serial backtrace" "${n:-0}" ge 3
timeout 120 $QEMU_X86 $ACCEL -kernel "$K0" -m 256 \
    -append "nokbd nosched noproc noring3 logall krach krachjetzt stapelscan" \
    -serial "file:$TMPD/scan.txt" -display none -no-reboot \
    -device isa-debug-exit,iobase=0xf4,iosize=0x04 >/dev/null 2>&1
has "$TMPD/scan.txt" "ktrace: stapelscan" "COUNTER-PROOF: with 'stapelscan' the stack is scanned again"
stale=$(trace_names "$TMPD/scan.txt" | grep -cvE '^(crash\.knall(_a|_b)?|KERNEL_MAIN|long_mode)$')
num "COUNTER-PROOF: the scan reports entries that are not callers (legacy)" "${stale:-0}" ge 1
has "$TMPD/panic.txt" "die letzten Protokollzeilen" \
    "(b) the last log lines are also on the serial line"

echo "== 7. that the driver switch really took place =="
n=0
for f in nvme xhci usb ahci e1000 fs; do
    q=$(find kernel -name "$f.fi" -print -quit)
    k=$(bash tools/structure/srcview.sh "$q" 2>/dev/null | grep -ac 'klog\.' || true)
    [ "$k" -gt 0 ] && n=$((n + 1))
    printf '        %-6s %s calls of the log interface\n' "$f" "$k"
done
num "drivers that talk through the log interface" "$n" eq 6

echo "LOG: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
