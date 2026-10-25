#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
set -uo pipefail
HERE="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$HERE"
export FIRNLIB="$HERE/lib"
T=$(mktemp -d); trap 'kill $QPID 2>/dev/null; rm -rf "$T"' EXIT
QPID=""
pass=0; fail=0
ok()  { pass=$((pass+1)); printf '  OK    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }
bash vendor/firn/fetch-firnc.sh >/dev/null 2>&1

echo "== host: state names match the scheduler constants =="
python3 -I tools/psstate/names.py kernel/sched/sched.fi kernel/user/taskstate.fi > "$T/names.txt" 2>&1 && ok "every S_* constant has its own name, only S_NEW is called new" || { bad "state names"; cat "$T/names.txt"; }
sed 's/poll   \\0/new    \\0/' kernel/user/taskstate.fi > "$T/taskstate_bad.fi"
python3 -I tools/psstate/names.py kernel/sched/sched.fi "$T/taskstate_bad.fi" > /dev/null 2>&1 && bad "counter-proof: poll named new was not caught" || ok "counter-proof: poll named new is caught"

PROGS="init sh ps top sleep orientbus cat echo"
bash tools/sync/build.sh "$T/bin" 0 $PROGS > "$T/b.txt" 2>&1 || { tail "$T/b.txt"; echo "PSSTATE: build failed"; exit 1; }
bash tools/build-kernel.sh "$T/k.mb" --stufe 0 > "$T/k.txt" 2>&1 || { tail "$T/k.txt"; echo "PSSTATE: kernel build failed"; exit 1; }

mkdir -p "$T/inc"
cat > "$T/inittab" <<'TAB'
bus:*:respawn:/bin/orientbus serve
snap:*:once:/bin/sh /etc/snap.sh
TAB
printf '/bin/sleep 6\n/bin/ps\n/bin/top -n 1\n/bin/echo PSSTATE-DONE\n' > "$T/snap.sh"
printf 'konsole\n' > "$T/ziel"
SPEC=""
for p in $PROGS; do SPEC="$SPEC /bin/$p=$T/bin/$p.elf@755:0:0"; done
python3 tools/osum/mkfs.py build "$T/d.img" 20480 --v3 /bin/ /etc/ /run/ /var/ /var/log/@755:0:0 /proc/ /tmp/ /etc/actions.d/ \
    $SPEC /etc/inittab="$T/inittab"@644:0:0 /etc/ziel="$T/ziel"@644:0:0 /etc/snap.sh="$T/snap.sh"@755:0:0 > "$T/mkfs.txt" 2>&1 || { tail "$T/mkfs.txt"; echo "PSSTATE: mkfs failed"; exit 1; }

ACC=tcg; [ -w /dev/kvm ] && ACC=kvm
timeout 200 qemu-system-x86_64 -accel $ACC -kernel "$T/k.mb" -m 256 \
    -append "osum console=ttyS0 vfs" -serial "file:$T/ser.txt" -display none -no-reboot \
    -drive "file=$T/d.img,format=raw,if=ide" -device isa-debug-exit,iobase=0xf4,iosize=0x04 >"$T/qemu.out" 2>&1 &
QPID=$!
S="$T/ser.txt"
klar() { [ -f "$S" ] || return 0; tr -cd '\11\12\15\40-\176' < "$S"; }
i=0; while [ $i -lt 150 ] && ! klar | grep -aq 'PSSTATE-DONE'; do kill -0 $QPID 2>/dev/null || break; sleep 1; i=$((i+1)); done
klar | grep -aq 'PSSTATE-DONE' && ok "snapshot script ran" || { bad "snapshot script did not finish"; klar | tail -20; }
klar | grep -aE '^ *[0-9]+ +[0-9]+ .*orientbus' | head -3 > "$T/rows.txt"
grep -aq ' poll ' "$T/rows.txt" && ok "ps shows orientbus as poll" || { bad "ps does not show orientbus as poll"; cat "$T/rows.txt"; }
klar | grep -aE '^ *[0-9]+ +[0-9]+ +new ' > "$T/newrows.txt" || true
grep -aq 'orientbus' "$T/newrows.txt" && bad "orientbus still shown as new" || ok "orientbus not shown as new"
echo "PSSTATE: $pass ok / $fail fail"
[ "$fail" -eq 0 ]
