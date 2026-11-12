#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
set -uo pipefail
cd "$(dirname "$0")/../.."
ROOT=$(pwd)
export FIRNLIB="$ROOT/lib"
pass=0; fail=0
ok()  { pass=$((pass+1)); printf '  OK    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }
D=${KEEP:-$(mktemp -d)}; mkdir -p "$D"
trap '[ -n "${KEEP:-}" ] || rm -rf "$D"' EXIT
: "${OSUM_QEMU_ACCEL:=tcg}"
[ -e /dev/kvm ] && [ "$OSUM_QEMU_ACCEL" = tcg ] && OSUM_QEMU_ACCEL=kvm
. tools/lib/firnenv.sh
finish() { echo "WBLAZY: $pass passed, $fail failed"; [ "$fail" -eq 0 ]; exit $?; }
ROUNDS=${ROUNDS:-60}
CMD_RATIO=${CMD_RATIO:-3}
KERNEL_IN=${KERNEL:-}

echo "== 1. build =="
PROGS="sh shasum echo sleep sync wbw"
mkdir -p "$D/bin" "$D/usrc"
cp -r kernel/user/. "$D/usrc/"
cp tools/wblazy/wbw.fi "$D/usrc/wbw.fi"
USRC="$D/usrc" bash tools/sync/build.sh "$D/bin" 0 $PROGS > "$D/b.txt" 2>&1 && ok "programs build" || { bad "programs"; head -10 "$D/b.txt"; finish; }
if [ -n "$KERNEL_IN" ]; then
    cp "$KERNEL_IN" "$D/k.img"
else
    ./tools/build-kernel.sh "$D/k.img" --stufe 0 > "$D/k.txt" 2>&1 && ok "kernel builds" || { bad "kernel"; tail -5 "$D/k.txt"; finish; }
fi
head -c 4096 /dev/zero | tr '\0' 'A' > "$D/a.bin"
hash_of() { head -c 4096 /dev/zero | tr '\0' "$1" | sha256sum | cut -d' ' -f1; }
HASH_A=$(hash_of A); HASH_B=$(hash_of B); HASH_C=$(hash_of C)
SPEC="/bin/ /tmp/ /proc/ /dev/"
for p in $PROGS; do SPEC="$SPEC /bin/$p=$D/bin/$p.elf"; done
bash tools/mkfsfi/mkfs.sh build "$D/base.img" 16384 --v3 --inodes=256 $SPEC "/tmp/a=$D/a.bin" > "$D/mkfs.txt" 2>&1 \
    && ok "plain image built (no journal)" || { bad "mkfs"; tail -3 "$D/mkfs.txt"; finish; }

boot() {
    local name=$1 img=$2 words=$3 script=$4 kill_after=$5
    local serial=$D/o-$name.txt
    timeout 240 qemu-system-x86_64 -accel "$OSUM_QEMU_ACCEL" -smp 1 -kernel "$D/k.img" -m 512 \
        -append "osum nokbd vfs $words script=$script" \
        -serial "file:$serial" -display none -no-reboot \
        -drive "file=$img,format=raw,if=none,id=d0,cache=directsync" -device ahci,id=ahci -device ide-hd,drive=d0,bus=ahci.0 \
        -trace "ahci_populate_sglist,file=$D/$name.t" \
        -device isa-debug-exit,iobase=0xf4,iosize=0x04 >/dev/null 2>&1 &
    local pid=$!
    if [ "$kill_after" != none ]; then
        for _ in $(seq 1 2400); do
            [ -f "$serial" ] && tr -d '\r' < "$serial" | grep -qa '^MARK' && break
            kill -0 "$pid" 2>/dev/null || break
            sleep 0.05
        done
        sleep "$kill_after"
        pkill -9 -P "$pid" 2>/dev/null
        kill -9 "$pid" 2>/dev/null
    fi
    wait "$pid" 2>/dev/null
    touch "$D/$name.t"
    tr -cd '\11\12\15\40-\176' < "$serial" > "$D/$name.klar"
}

content() {
    local name=$1 img=$2 words=${3:-}
    boot "$name" "$img" "$words" "shasum /tmp/a;exit" none
    grep -a -o '^[0-9a-f]\{64\}  /tmp/a' "$D/$name.klar" | head -1 | cut -c1-64
}

barrier() {
    local name=$1 words=$2 script=$3 kill_after=$4 want=$5 what=$6
    cp "$D/base.img" "$D/$name.img"
    boot "$name" "$D/$name.img" "$words" "$script" "$kill_after"
    local got; got=$(content "$name-check" "$D/$name.img")
    [ "$got" = "$want" ] && ok "$what" || bad "$what (hash ${got:-none})"
}

echo "== 2. barriers (kill -9) =="
barrier sync "" "wbw /tmp/a B 1;sync;echo MARK;sleep 30;exit" 0.3 "$HASH_B" "sync(2) persists the overwrite before kill -9"
barrier exit "" "wbw /tmp/a B 1;exit" none "$HASH_B" "script end (shutdown path) persists the overwrite"
barrier idle "" "wbw /tmp/a B 1;echo MARK;sleep 30;exit" 4 "$HASH_B" "idle flush persists the overwrite within 4 s"
barrier nolazy nowblazy "wbw /tmp/a B 1;echo MARK;sleep 30;exit" 0.1 "$HASH_B" "counter-proof nowblazy: overwrite on disk right after the write"

echo "== 3. read after write =="
cp "$D/base.img" "$D/raw.img"
boot raw "$D/raw.img" "" "wbw /tmp/a C $ROUNDS;shasum /tmp/a;exit" none
[ "$(grep -a -c "^$HASH_C  /tmp/a" "$D/raw.klar")" -ge 1 ] && ok "same boot: read returns the new data" || bad "same boot: read returns stale data"
[ "$(content raw-again "$D/raw.img")" = "$HASH_C" ] && ok "next boot: new data persisted" || bad "next boot: stale data"

echo "== 4. device commands =="
count() { local c; c=$(grep -c ahci_populate_sglist "$D/$1" 2>/dev/null); echo "${c:-0}"; }
for mode in lazy nolazy; do
    words=""; [ "$mode" = nolazy ] && words="nowblazy"
    cp "$D/base.img" "$D/cmd-$mode.img"; cp "$D/base.img" "$D/ref-$mode.img"
    boot "cmd-$mode" "$D/cmd-$mode.img" "$words" "wbw /tmp/a B $ROUNDS;exit" none
    boot "ref-$mode" "$D/ref-$mode.img" "$words" "wbw /tmp/a B 0;exit" none
done
lazy=$(( $(count cmd-lazy.t) - $(count ref-lazy.t) )); nolazy=$(( $(count cmd-nolazy.t) - $(count ref-nolazy.t) ))
echo "  device commands for $ROUNDS overwrites: lazy=$lazy nowblazy=$nolazy"
[ "$lazy" -gt 0 ] && [ $(( lazy * CMD_RATIO )) -le "$nolazy" ] \
    && ok "at least ${CMD_RATIO}x fewer device commands ($nolazy -> $lazy)" || bad "command ratio too small ($nolazy -> $lazy)"
[ "$nolazy" -ge "$ROUNDS" ] && ok "nowblazy: at least one command per overwrite ($nolazy)" || bad "nowblazy: fewer commands than overwrites ($nolazy)"
finish
