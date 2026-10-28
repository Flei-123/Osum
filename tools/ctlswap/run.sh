#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
set -uo pipefail
cd "$(dirname "$0")/../.."
ROOT=$(pwd)
export FIRNLIB="$ROOT/lib"
pass=0; fail=0
ok()  { pass=$((pass+1)); printf '  OK    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }
has()  { grep -aqF -- "$2" "$1" && ok "$3" || bad "$3 -- '$2' missing"; }
hasnt() { grep -aqF -- "$2" "$1" && bad "$3 -- '$2' present" || ok "$3"; }
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
bash vendor/firn/fetch-firnc.sh >/dev/null 2>&1
PROGS="sh ls cat echo jarvisctl"
mkdir -p "$T/bin"
bash tools/sync/build.sh "$T/bin" 0 $PROGS > "$T/b.txt" 2>&1 && ok "programs build" || { bad "programs build"; head -15 "$T/b.txt"; echo "CTLSWAP: $pass passed, $fail failed"; exit 1; }
./tools/build-kernel.sh "$T/k0.img" --stufe 0 > "$T/k.txt" 2>&1 && ok "kernel builds" || { bad "kernel build"; echo "CTLSWAP: $pass passed, $fail failed"; exit 1; }
printf 'CAT-FILE-BODY\n' > "$T/hello.txt"
cat > "$T/s0.sh" <<'EOS'
echo ==A==
tgt /t/hello.txt
jarvisctl swap /tmp/new /bin/tgt
tgt /t/hello.txt
echo ==B==
jarvisctl swap --undo /bin/tgt
tgt /t/hello.txt
jarvisctl swap --undo /bin/tgt
EOS
cat > "$T/s1.sh" <<'EOS'
echo ==C==
jarvisctl swap /tmp/new /apps/g.osp/start
/apps/g.osp/start /t/hello.txt
ls /apps/g.osp
jarvisctl swap --undo /apps/g.osp/start
/apps/g.osp/start /t/hello.txt
EOS
cat > "$T/s2.sh" <<'EOS'
echo ==D==
jarvisctl swap /etc/hello.txt /bin/tgt
jarvisctl swap /tmp/new /etc/evil
jarvisctl swap /tmp/../etc/hello.txt /bin/tgt
jarvisctl swap /tmp/new /bin/../etc/evil
jarvisctl swap /tmp/new
echo ==D2==
cat /tmp/missing
echo ==D3==
jarvisctl swap /tmp/missing /bin/tgt
echo ==D4==
tgt /t/hello.txt
EOS
cat > "$T/s3.sh" <<'EOS'
echo ==E==
jarvisctl swap /tmp/new /bin/fresh
fresh /t/hello.txt
jarvisctl swap --undo /bin/fresh
echo ==END==
EOS
python3 tools/osum/mkfs.py build "$T/d.img" 20000 /bin/ /t/ /tmp/ /proc/ /dev/ /system/ /etc/ /var/ /apps/ /apps/g.osp/ \
    $(for p in $PROGS; do echo "/bin/$p=$T/bin/$p.elf"; done) \
    "/bin/tgt=$T/bin/echo.elf" "/apps/g.osp/start=$T/bin/echo.elf" "/tmp/new=$T/bin/cat.elf" "/etc/hello.txt=$T/hello.txt" \
    "/t/hello.txt=$T/hello.txt" "/t/s0.sh=$T/s0.sh" "/t/s1.sh=$T/s1.sh" "/t/s2.sh=$T/s2.sh" "/t/s3.sh=$T/s3.sh" > "$T/mkfs.txt" 2>&1 || tail -3 "$T/mkfs.txt"
ACC=tcg; [ -e /dev/kvm ] && ACC=kvm
timeout 200 qemu-system-x86_64 -accel "$ACC" -smp 1 -kernel "$T/k0.img" -m 512 \
    -append "osum vfs nokbd script=sh /t/s0.sh;sh /t/s1.sh;sh /t/s2.sh;sh /t/s3.sh;exit" \
    -serial "file:$T/o.txt" -display none -no-reboot \
    -drive "file=$T/d.img,format=raw,if=ide,index=0" \
    -device isa-debug-exit,iobase=0xf4,iosize=0x04 >/dev/null 2>&1
tr -cd '\11\12\15\40-\176' < "$T/o.txt" > "$T/o.klar"
cp "$T/o.klar" "${CTLSWAP_OUT:-/dev/null}" 2>/dev/null
part() { awk -v a="==$1==" -v b="==$2==" 'index($0,a){f=1;next} index($0,b){f=0} f' "$T/o.klar" > "$T/p.$1"; }
part A B; part B C; part C D; part D E; part E END
has "$T/p.A" "/t/hello.txt" "A: before the swap tgt is echo (prints its argument)"
has "$T/p.A" "swap: ok " "A: swap reports ok"
has "$T/p.A" "swap: previous file kept as /bin/tgt.old" "A: previous file kept as .old"
has "$T/p.A" "CAT-FILE-BODY" "A: after the swap tgt is the new binary (cat)"
has "$T/p.B" "swap: undone, previous file is back" "B: undo reports"
has "$T/p.B" "/t/hello.txt" "B: after the undo tgt is echo again"
hasnt "$T/p.B" "CAT-FILE-BODY" "B: new binary gone after undo"
has "$T/p.B" "swap: nothing to undo" "B: second undo has nothing to undo"
has "$T/p.C" "CAT-FILE-BODY" "C: /apps/<x>.osp/start swapped"
has "$T/p.C" "swap: undone" "C: /apps start undone"
has "$T/p.D" "source must be a plain file path" "D: source outside /tmp, /var/jarvis refused"
has "$T/p.D" "destination must be /bin/<name> or /apps/<x>.osp/<name>" "D: destination outside /bin, /apps refused"
has "$T/p.D" "cannot read the source file" "D: missing source refused"
hasnt "$T/p.D" "CAT-FILE-BODY" "D: no refused call changed tgt"
has "$T/p.D" "usage: jarvisctl swap" "D: missing argument prints usage"
has "$T/p.E" "swap: destination was new, there is no previous file" "E: new destination works"
has "$T/p.E" "CAT-FILE-BODY" "E: new destination runs"
grep -aiqE 'panic|kernel fault|page fault|exception' "$T/o.klar" && bad "fault on the serial line" || ok "0 faults"
grep -aq '^kernel: done' "$T/o.klar" && ok "the kernel finished" || bad "kernel did not finish"
echo "CTLSWAP: $pass passed, $fail failed"
[ "$fail" = 0 ]
