#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/xhci/run.sh -- xHCI driver: no ERDP MMIO write on an empty event ring + STALLed EP0 is recovered (Y1, 17.10.2026).
#
# Problem (measured in VirtualBox 7.2): the HID keyboard/tablet STALLs SET_PROTOCOL/SET_IDLE. EP0 stays Halted, the next control
# transfer waits SPIN_LIMIT (2M) drain() rounds, and every round wrote ERDP (an MMIO write = VM exit, ~30 us) -> ~60 s boot stall.
# Fix: drain() writes ERDP only when it consumed events; ep0_recover() = Reset Endpoint + Set TR Dequeue after a failed control.
#
#   case new   word `usbstall`          : QEMU -trace counts ERDP writes (offset 0x38) over the boot; self test line
#                                         `usb: stalltest r1=<100+rc> halted=0 r2>=100` (STALL seen, EP0 usable again)
#   case old   words `usbstall xhciold` : COUNTER-PROOF: ERDP writes far above the new case, EP0 stays Halted (halted=1 or r2<100)
#   case quiet no `usbtrace`            : no `usb: t ` lines (trace is behind the word); with `usbtrace` they appear
set -uo pipefail
cd "$(dirname "$0")/../.."
ROOT=$(pwd)
export FIRNLIB="$ROOT/lib"
OUT=${1:-$(mktemp -d)}
mkdir -p "$OUT"
pass=0; fail=0
ok()  { pass=$((pass+1)); printf '  OK    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }
command -v qemu-system-x86_64 >/dev/null 2>&1 || { echo "XHCI: skipped, no qemu"; exit 0; }
PROGS="sh echo ls cat"

# run_case <tag> <extra words>   (count of ERDP writes -> $OUT/<tag>.erdp)
run_case() {
    local tag=$1 words=$2 D="$OUT/$1"
    mkdir -p "$D"
    rm -f "$D/trace.fifo"; mkfifo "$D/trace.fifo"
    # count runtime-register writes at offset 0x38 (interrupter 0 ERDP) without storing the (possibly huge) log
    awk '/usb_xhci_runtime_write/ {t++; if (t<=6) print > "'"$D/sample.txt"'"} /usb_xhci_runtime_write/ && /off 0x0*38,/ {n++} END{print n+0 > "'"$OUT/$tag.erdp"'"}' "$D/trace.fifo" &
    local apid=$!
    ALLTAGBUILD="$D.build" bash tools/alltag/build.sh "$D" kbd=no warten=3 \
        extra="usb hidgen $words" hold=no waitfor="usb: stalltest" progs="$PROGS" \
        qemu="-device qemu-xhci -device usb-kbd -trace usb_xhci_runtime_write -D $D/trace.fifo" > "$D.log" 2>&1
    wait "$apid" 2>/dev/null
    rm -f "$D/trace.fifo"
}

echo "== 1. new: ERDP writes during boot + STALL self test =="
run_case new "usbstall"
S="$OUT/new/serial.txt"
NEW=$(cat "$OUT/new.erdp" 2>/dev/null || echo -1)
L=$(grep -a 'usb: stalltest' "$S" | tail -1)
echo "  line: $L"
R1=$(sed -n 's/.*r1=\([0-9]*\).*/\1/p' <<<"$L"); H=$(sed -n 's/.*halted=\([0-9]*\).*/\1/p' <<<"$L"); R2=$(sed -n 's/.*r2=\([0-9]*\).*/\1/p' <<<"$L")
[ -n "$R1" ] && [ "$R1" -lt 100 ] && ok "STALLed request reported as error (r1=$R1)" || bad "STALL request not seen (r1=$R1)"
[ "$H" = 0 ] && ok "EP0 not left Halted" || bad "EP0 Halted after the STALL (halted=$H)"
[ -n "$R2" ] && [ "$R2" -ge 100 ] && ok "next control request works (r2=$R2)" || bad "next control request failed (r2=$R2)"
[ "$NEW" -ge 1 ] && [ "$NEW" -le 3000 ] && ok "ERDP writes over the whole boot: $NEW (want 1..3000)" || bad "ERDP writes: $NEW (want 1..3000)"
grep -aq 'usb: t ' "$S" && bad "trace lines without word usbtrace" || ok "no 'usb: t' lines without word usbtrace"

echo
echo "== 2. COUNTER-PROOF: words usbstall xhciold (old behaviour) =="
run_case old "usbstall xhciold"
OLD=$(cat "$OUT/old.erdp" 2>/dev/null || echo -1)
L=$(grep -a 'usb: stalltest' "$OUT/old/serial.txt" | tail -1)
echo "  line: $L"
H2=$(sed -n 's/.*halted=\([0-9]*\).*/\1/p' <<<"$L"); R22=$(sed -n 's/.*r2=\([0-9]*\).*/\1/p' <<<"$L")
{ [ "$H2" = 1 ] || { [ -n "$R22" ] && [ "$R22" -lt 100 ]; }; } && ok "old: EP0 stays Halted / next request fails (halted=$H2 r2=$R22)" || bad "old behaviour did not show the stall bug (halted=$H2 r2=$R22)"
[ "$OLD" -gt $((NEW * 20 + 20000)) ] && ok "old: ERDP writes $OLD >> new $NEW" || bad "old ERDP writes $OLD not far above new $NEW"

echo
echo "== 3. word usbtrace switches the trace on =="
run_case tr "usbstall usbtrace"
grep -aq 'usb: t ' "$OUT/tr/serial.txt" && ok "trace lines with word usbtrace" || bad "no trace lines with usbtrace"

echo
echo "XHCI: $pass ok / $fail fail"
[ "$fail" = 0 ]
