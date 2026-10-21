#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/liveswap/run.sh -- UPD-1 / r566: replacing the file of a RUNNING program.
#
#   bash tools/liveswap/run.sh
#
# Guest script: `sleep 3 &`, then /bin/sleep is replaced (mv new over it) while it runs.
#   A  before the swap: `sleep hello` (old binary) prints nothing                       (counter-proof)
#   B  swap by rename, the running instance is still listed by `ps`, a new start runs the NEW binary (prints hello)
#   C  swap by unlink + rename of a second running program (/bin/nap), same expectations
#   W  a foreground `nap2 8` gives the background jobs time to end
#   D  the old instances end on their own (zombie), nothing faulted, the kernel finished
set -uo pipefail
cd "$(dirname "$0")/../.."
ROOT=$(pwd)
export FIRNLIB="$ROOT/lib"
pass=0; fail=0
ok()  { pass=$((pass+1)); printf '  OK    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
bash vendor/firn/fetch-firnc.sh >/dev/null 2>&1
PROGS="sh ls cat echo mv rm sleep ps"
mkdir -p "$T/bin"
bash tools/sync/build.sh "$T/bin" 0 $PROGS > "$T/b.txt" 2>&1 && ok "programs build" || { bad "programs build"; head -15 "$T/b.txt"; echo "LIVESWAP: $pass passed, $fail failed"; exit 1; }
./tools/build-kernel.sh "$T/k0.img" --stufe 0 > "$T/k.txt" 2>&1 && ok "kernel builds" || { bad "kernel build"; echo "LIVESWAP: $pass passed, $fail failed"; exit 1; }
cat > "$T/s.sh" <<'EOS'
echo ==A==
sleep 6 &
ps
sleep hello
echo ==B==
mv /bin/new /bin/sleep
ps
sleep hello
echo ==C==
nap 6 &
rm /bin/nap
mv /bin/new2 /bin/nap
ps
nap hello2
echo ==W==
nap2 8
echo ==D==
ps
echo ==END==
EOS
python3 tools/osum/mkfs.py build "$T/d.img" 20000 /bin/ /t/ /tmp/ /proc/ /dev/ /system/ /etc/ /var/ \
    $(for p in $PROGS; do echo "/bin/$p=$T/bin/$p.elf"; done) \
    "/bin/nap=$T/bin/sleep.elf" "/bin/nap2=$T/bin/sleep.elf" "/bin/new=$T/bin/echo.elf" "/bin/new2=$T/bin/echo.elf" \
    "/t/s.sh=$T/s.sh" > "$T/mkfs.txt" 2>&1 || tail -3 "$T/mkfs.txt"
ACC=tcg; [ -e /dev/kvm ] && ACC=kvm
timeout 200 qemu-system-x86_64 -accel "$ACC" -smp 1 -kernel "$T/k0.img" -m 512 \
    -append "osum vfs nokbd script=sh /t/s.sh;exit" \
    -serial "file:$T/o.txt" -display none -no-reboot \
    -drive "file=$T/d.img,format=raw,if=ide,index=0" \
    -device isa-debug-exit,iobase=0xf4,iosize=0x04 >/dev/null 2>&1
tr -cd '\11\12\15\40-\176' < "$T/o.txt" > "$T/o.klar"
cp "$T/o.klar" "${LIVESWAP_OUT:-/dev/null}" 2>/dev/null
part() { awk -v a="==$1==" -v b="==$2==" 'index($0,a){f=1;next} index($0,b){f=0} f' "$T/o.klar"; }
pidof_job() { grep -a -o '^\[[0-9]*\] [0-9]*' | awk '{print $2}' | head -1; }
row() { awk -v p="$1" '$1==p' ; }
PA=$(part A B | pidof_job)
PC=$(part C W | pidof_job)
[ -n "$PA" ] && ok "A: background sleep started (pid $PA)" || bad "A: no background job line"
part A B | row "$PA" | grep -aq ' sleep ' && ok "A: the running instance is listed by ps" || bad "A: instance $PA missing in ps"
part A B | grep -aq hello && bad "A: old binary printed hello (counter-proof broken)" || ok "A: old binary prints nothing (counter-proof)"
part B C | row "$PA" | grep -aqE ' (sleep|run|wait) ' && ok "B: after the rename the old instance $PA still runs" || bad "B: old instance $PA gone after the swap"
part B C | grep -aqx hello && ok "B: a new start runs the NEW binary (hello)" || bad "B: new start did not run the new binary"
[ -n "$PC" ] && ok "C: second background program started (pid $PC)" || bad "C: no second background job line"
part C W | row "$PC" | grep -aqE ' (sleep|run|wait) ' && ok "C: unlink + rename: the old instance $PC still runs" || bad "C: old instance $PC gone after unlink + rename"
part C W | grep -aqx hello2 && ok "C: a new start runs the NEW binary (hello2)" || bad "C: new start did not run the new binary"
part D END | row "$PA" | grep -aq zombie && ok "D: instance $PA ended on its own" || bad "D: instance $PA not ended cleanly"
part D END | row "$PC" | grep -aq zombie && ok "D: instance $PC ended on its own" || bad "D: instance $PC not ended cleanly"
grep -aiqE 'panic|kernel fault|page fault|exception' "$T/o.klar" && bad "D: fault on the serial line" || ok "D: 0 faults"
grep -aq '^kernel: done' "$T/o.klar" && ok "D: the kernel finished" || bad "D: kernel did not finish"
echo "LIVESWAP: $pass passed, $fail failed"
[ "$fail" = 0 ]
