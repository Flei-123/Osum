#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
set -uo pipefail
cd "$(dirname "$0")/../.."
. tools/lib/tmpdir.sh
export FIRNLIB="$(pwd)/lib"
. tools/lib/firnenv.sh
TMPD=$(mktemp -d)
osum_tmp_guard "${1:-}" "$TMPD"
trap 'rm -rf "$TMPD"' EXIT
pass=0; fail=0
ok()  { pass=$((pass+1)); printf '  OK    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }
ACCEL=""
if [ -r /dev/kvm ] && [ -w /dev/kvm ]; then ACCEL="-accel kvm -cpu Skylake-Client,pmu=on"; fi
MEM=${SWAP_MEM:-64}
MIB=${SWAP_MIB:-44}
bash tools/build-kernel.sh "$TMPD/k.mb" > "$TMPD/build.log" 2>&1 || { bad "kernel build"; tail -5 "$TMPD/build.log"; exit 1; }
as --64 -o "$TMPD/crt.o" kernel/user/crt.s || bad "crt.s"
SPEC="/bin/ /etc/ /tmp/ /proc/ /dev/ /mnt/ /var/"
for p in sh echo swaptest; do
    "$FIRNC" "kernel/user/$p.fi" -o "$TMPD/$p.o" > "$TMPD/e$p" 2>&1 || { bad "$p.fi compile"; head -3 "$TMPD/e$p"; continue; }
    ld -T kernel/user/user.ld --defsym=USER_ENTRY="_F0.u_start" -o "$TMPD/$p.elf" "$TMPD/crt.o" "$TMPD/$p.o" 2>/dev/null || bad "$p link"
    SPEC="$SPEC /bin/$p=$TMPD/$p.elf"
done
bash tools/mkfsfi/mkfs.sh build "$TMPD/base.img" 262144 --v3 $SPEC > "$TMPD/mkfs.txt" 2>&1 || { bad "mkfs"; exit 1; }
qboot() {
    local t=$1 words=$2
    cp "$TMPD/base.img" "$TMPD/$t.img"
    timeout -s KILL 240 qemu-system-x86_64 $ACCEL -machine q35 -smp 2 -kernel "$TMPD/k.mb" -m "$MEM" \
        -append "osum nokbd vfs smpfrueh $words script=swaptest $MIB;echo swapdone;exit" \
        -serial "file:$TMPD/$t.ser" -display none -global ICH9-LPC.noreboot=false \
        -drive "file=$TMPD/$t.img,format=raw,if=none,id=d0" -device ide-hd,drive=d0,bus=ide.0 \
        -device isa-debug-exit,iobase=0xf4,iosize=0x04 < /dev/null > /dev/null 2>&1
    tr -d '\000\r' < "$TMPD/$t.ser" > "$TMPD/$t.txt"
}
last_num() { grep -a "^$2" "$TMPD/$1.txt" | tail -1 | grep -oE '[0-9]+' | tail -1; }
swap_field() { grep -a '^swap: out=' "$TMPD/$1.txt" | tail -1 | grep -oE "$2=[0-9]+" | grep -oE '[0-9]+'; }
echo "== A. swap on: $MIB MiB of anonymous memory in $MEM MiB of RAM =="
qboot a "swap"
grep -qa "^swaptest: done" "$TMPD/a.txt" && ok "A swaptest ran to the end" || bad "A swaptest did not finish"
[ "$(last_num a 'swaptest: pass1 b')" = 0 ] && ok "A pass 1: every page holds its value" || bad "A pass 1 bad pages: $(last_num a 'swaptest: pass1 b')"
[ "$(last_num a 'swaptest: pass2 b')" = 0 ] && ok "A pass 2: rewritten pages hold the new value" || bad "A pass 2 bad pages: $(last_num a 'swaptest: pass2 b')"
[ "$(last_num a 'swaptest: pass3 b')" = 0 ] && ok "A pass 3: second read-back identical" || bad "A pass 3 bad pages: $(last_num a 'swaptest: pass3 b')"
[ "${a_out:=$(swap_field a out)}" != "" ] && [ "$a_out" -gt 0 ] && ok "A pages went out to /swapfile: $a_out" || bad "A no swap-out reported"
a_in=$(swap_field a in)
[ "${a_in:-0}" -gt 0 ] && ok "A pages came back from /swapfile: $a_in" || bad "A no swap-in reported"
grep -qa "swaptest: done" "$TMPD/a.txt" && ! sed -n '/^swaptest: pages/,$p' "$TMPD/a.txt" | grep -qaE "panic|user fault" && ok "A no panic, no user fault" || bad "A panic or user fault"
grep -qax "swapdone" "$TMPD/a.txt" && ok "A shell reached the end of the script" || bad "A swapdone missing"
echo "== B. counter-proof without the word: no swap, the same load cannot finish =="
qboot b ""
if grep -qa "^swaptest: done" "$TMPD/b.txt" && [ "$(last_num b 'swaptest: pass1 b')" = 0 ] && [ "$(last_num b 'swaptest: pass2 b')" = 0 ]; then
    bad "B finished without swap, counter-proof inactive"
else
    ok "B without swap the load fails or is killed"
fi
[ -z "$(swap_field b out)" ] && ok "B no swap traffic reported" || bad "B swap traffic without the word"
echo "== C. counter-proof small load: swap on but nothing to evict =="
MIB=8 qboot c "swap"
grep -qa "^swaptest: done" "$TMPD/c.txt" && ok "C small load finishes" || bad "C small load did not finish"
[ -z "$(swap_field c out)" ] && ok "C no page was swapped out with plenty of RAM" || bad "C unexpected swap-out $(swap_field c out)"
echo
if [ -n "${SWAP_OUT:-}" ]; then mkdir -p "$SWAP_OUT"; cp "$TMPD"/*.ser "$SWAP_OUT/" 2>/dev/null; fi
echo "SWAP: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
