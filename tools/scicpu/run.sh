#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/scicpu/run.sh -- an asserted-looking SCI line must not eat the idle CPU.
#   bash tools/scicpu/run.sh   (SCICPU_KERNEL=<k0.img> reuses a built kernel)
set -uo pipefail
cd "$(dirname "$0")/../.."
T=${SCICPU_KEEP:-$(mktemp -d)}; [ -n "${SCICPU_KEEP:-}" ] || trap 'rm -rf "$T"' EXIT
pass=0; fail=0
ok()  { pass=$((pass+1)); echo "  OK    $1"; }
bad() { fail=$((fail+1)); echo "  FAIL  $1"; }
: "${OSUM_QEMU_ACCEL:=tcg}"
[ -w /dev/kvm ] && [ "$OSUM_QEMU_ACCEL" = tcg ] && OSUM_QEMU_ACCEL=kvm
export FIRNLIB="$PWD/lib"
command -v qemu-system-x86_64 >/dev/null 2>&1 || { echo "  SKIP  qemu missing"; exit 0; }
mkdir -p "$T/bin"
bash tools/sync/build.sh "$T/bin" 0 sh echo sleep cat > "$T/b.txt" 2>&1 && ok "user programs build" || { bad "user programs do not build"; tail -5 "$T/b.txt"; }
K="${SCICPU_KERNEL:-$T/k0.img}"
if [ -z "${SCICPU_KERNEL:-}" ]; then
    ./tools/build-kernel.sh "$K" --stufe 0 > "$T/k.txt" 2>&1 && ok "the kernel builds" || { bad "the kernel does not build"; tail -5 "$T/k.txt"; }
fi
cat > "$T/s.sh" <<'SCRIPT'
sleep -m 500
echo ==A==
cat /proc/stat
cat /proc/hotkeys
sleep -m 4000
echo ==B==
cat /proc/stat
cat /proc/hotkeys
sleep -m 500
echo ==END==
SCRIPT
run_case() {
    local n=$1 words=$2
    python3 tools/osum/mkfs.py build "$T/$n.img" 20000 /bin/ /etc/ /run/ /tmp/ /t/ /proc/ /dev/ /system/ /var/ \
        "/bin/sh=$T/bin/sh.elf" "/bin/echo=$T/bin/echo.elf" "/bin/sleep=$T/bin/sleep.elf" "/bin/cat=$T/bin/cat.elf" \
        "/t/s.sh=$T/s.sh" > "$T/$n.mkfs" 2>&1 || { bad "$n mkfs failed"; return; }
    timeout 240 qemu-system-x86_64 -accel "$OSUM_QEMU_ACCEL" -kernel "$K" -m 512 -smp 2 \
        -append "osum vfs nokbd nosched acpiev $words script=sh /t/s.sh;exit" \
        -serial "file:$T/$n.ser" -display none -no-reboot \
        -drive "file=$T/$n.img,format=raw,if=ide,index=0" \
        -device isa-debug-exit,iobase=0xf4,iosize=0x04 >/dev/null 2>&1
    tr -cd '\11\12\15\40-\176' < "$T/$n.ser" | tr -d '\r' > "$T/$n.txt"
}
section() { awk -v m="==$2==" 'index($0, m) { on = 1; next } /==(A|B|END)==/ { on = 0 } on' "$T/$1.txt"; }
cpu0() { section "$1" "$2" | awk '/^cpu  /{print $2+$4, $5; exit}'; }
irqs() { section "$1" "$2" | awk '/^traps /{print $2; exit}'; }
measure() {
    local n=$1
    local a b ia ib
    a=$(cpu0 "$n" A); b=$(cpu0 "$n" B); ia=$(irqs "$n" A); ib=$(irqs "$n" B)
    if [ -z "$a" ] || [ -z "$b" ] || [ -z "$ia" ] || [ -z "$ib" ]; then
        echo "-1 -1"
        return
    fi
    local ba=${a% *} ida=${a#* } bb=${b% *} idb=${b#* }
    local busy=$((bb - ba)) idle=$((idb - ida))
    local total=$((busy + idle))
    [ "$total" -gt 0 ] || { echo "-1 -1"; return; }
    echo "$((busy * 100 / total)) $((ib - ia))"
}
check() {
    local n=$1 label=$2 cmp=$3 want=$4
    local res pct irq
    res=$(measure "$n"); pct=${res% *}; irq=${res#* }
    echo "  INFO  $label: cpu0 busy ${pct} %, traps in window ${irq}"
    [ "$pct" -ge 0 ] || { bad "$label: no measurement"; return; }
    case $cmp in
        low)  [ "$pct" -le "$want" ] && ok "$label: cpu0 busy <= $want %" || bad "$label: cpu0 busy $pct % > $want %" ;;
        high) [ "$pct" -ge "$want" ] && ok "$label: cpu0 busy >= $want %" || bad "$label: cpu0 busy $pct % < $want %" ;;
    esac
}
echo "== 1. normal routing (MADT override honoured)"
run_case base ""
check base "default" low 30
echo "== 2. stuck level source (PM1 timer status never cleared), storm guard on"
run_case guard "scistorm noscistray"
check guard "stuck SCI source + guard" low 30
echo "== 3. counter-proof: same source, no storm guard"
run_case storm "scistorm noscistray noscistorm"
check storm "stuck SCI source, no guard" high 50
echo; echo "scicpu: $pass ok, $fail fail"
[ "$fail" -eq 0 ]
