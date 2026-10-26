#!/usr/bin/env bash
set -uo pipefail
cd "$(dirname "$0")/../.."
. tools/lib/qemu.sh

TMPD=$(mktemp -d)
trap 'rm -rf "$TMPD"' EXIT
pass=0
fail=0
ok() { pass=$((pass+1)); printf '  OK    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }

K=${AML_KERNEL:-}
if [ -z "$K" ]; then
    K="$TMPD/osum.mb"
    bash vendor/firn/fetch-firnc.sh >/dev/null || { echo "fetch-firnc failed"; exit 1; }
    bash tools/build-kernel.sh "$K" >/dev/null 2>&1 || { echo "kernel build failed"; exit 1; }
fi

for n in hwregion hwregion2 hwfail; do
    iasl -oa -p "$TMPD/$n" tools/aml/asl/$n.asl >/dev/null 2>&1 || { echo "iasl failed: $n"; exit 1; }
done

run() {
    local out=$1
    shift
    timeout 120 $QEMU_X86 -kernel "$K" -m 128 -append "osum aml nopwr" \
        -serial "file:$out" -display none -no-reboot "$@" \
        -device isa-debug-exit,iobase=0xf4,iosize=0x04 >/dev/null 2>&1
}

hold_line() { grep -a -m1 '^amlhold:' "$1" | tr -d '\r\000'; }
field() { echo "$1" | grep -o "$2=[0-9]*" | head -1 | sed 's/.*=//'; }

run "$TMPD/base.txt"
base=$(hold_line "$TMPD/base.txt")
[ -n "$base" ] && ok "baseline hold line: $base" || bad "baseline run printed no amlhold line"
base_nodes=$(field "$base" nodes)

run "$TMPD/hw.txt" \
    -acpitable "sig=SSDT,rev=2,oem_id=OSUM,oem_table_id=HWREG1,file=$TMPD/hwregion.aml" \
    -acpitable "sig=SSDT,rev=2,oem_id=OSUM,oem_table_id=HWREG2,file=$TMPD/hwregion2.aml"
line=$(hold_line "$TMPD/hw.txt")
echo "    $line"
grep -a '^amlfail:' "$TMPD/hw.txt" | tr -d '\r\000' | sed 's/^/    /'
[ -n "$line" ] || { bad "no amlhold line with the hardware-region tables"; echo "AML hwregion: $pass ok, $fail failed"; exit 1; }

[ "$(field "$line" e)" = "0" ] && ok "no error with real-firmware region operands" || bad "hold error e=$(field "$line" e)"
[ "$(field "$line" bad)" = "0" ] && ok "no bad table" || bad "bad=$(field "$line" bad)"
[ "$(field "$line" defer)" = "7" ] && ok "name operands deferred (7)" || bad "defer=$(field "$line" defer), expected 7"
[ "$(field "$line" skip)" -ge 2 ] 2>/dev/null && ok "unevaluable operand expressions skipped structurally ($(field "$line" skip))" || bad "skip=$(field "$line" skip), expected at least 2"
nodes=$(field "$line" nodes)
added=$((nodes - base_nodes))
[ "$added" -ge 50 ] 2>/dev/null && ok "every device and its trailing names loaded ($added new nodes)" || bad "only $added new nodes"

run "$TMPD/only1.txt" -acpitable "sig=SSDT,rev=2,oem_id=OSUM,oem_table_id=HWREG1,file=$TMPD/hwregion.aml"
l1=$(hold_line "$TMPD/only1.txt")
[ "$(field "$l1" e)" = "0" ] && ok "forward operand into a table that never arrives stays deferred" || bad "single table: $l1"

run "$TMPD/bad.txt" -acpitable "sig=SSDT,rev=2,oem_id=OSUM,oem_table_id=HWFAIL,file=$TMPD/hwfail.aml"
bl=$(hold_line "$TMPD/bad.txt")
fl=$(grep -a -m1 '^amlfail:' "$TMPD/bad.txt" | tr -d '\r\000')
echo "    $bl"
echo "    $fl" | cut -c1-200
[ "$(field "$bl" bad)" = "1" ] && ok "unresolvable field region counted as one bad table" || bad "failing table run: $bl"
echo "$fl" | grep -q 'SSDT off=[0-9]* e=9 path=[^ ]*F1 ctx=[0-9a-f]\{32,\}' && ok "failure line carries scope path and context bytes" || bad "failure line incomplete: $fl"

echo "AML hwregion: $pass ok, $fail failed"
[ "$fail" -eq 0 ]
