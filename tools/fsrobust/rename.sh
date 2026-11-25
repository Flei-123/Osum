#!/usr/bin/env bash
set -uo pipefail
cd "$(dirname "$0")/../.."
export FIRNLIB="$(pwd)/lib"
. tools/lib/firnenv.sh
RUNS=${FSR_RUNS:-80}
PAR=${FSR_PAR:-4}
PROGS="sh ls cat echo fsrren fsck"
TMPD=$(mktemp -d)
trap 'rm -rf "$TMPD"' EXIT
bash tools/build-kernel.sh "$TMPD/k.mb" >"$TMPD/build.txt" 2>&1 || { echo "build failed"; tail -5 "$TMPD/build.txt"; exit 1; }
as --64 -o "$TMPD/crt.o" kernel/user/crt.s
SPEC="/bin/ /tmp/ /dev/ /proc/"
for p in $PROGS; do
    "$FIRNC" "kernel/user/$p.fi" -o "$TMPD/$p.o" >"$TMPD/e$p" 2>&1 || { echo "compile $p failed"; head -5 "$TMPD/e$p"; exit 1; }
    ld -T kernel/user/user.ld --defsym=USER_ENTRY="_F0.u_start" -o "$TMPD/$p.elf" "$TMPD/crt.o" "$TMPD/$p.o" 2>/dev/null
    strip --strip-all "$TMPD/$p.elf" 2>/dev/null
    SPEC="$SPEC /bin/$p=$TMPD/$p.elf"
done
bash tools/mkfsfi/mkfs.sh build "$TMPD/base.img" 65536 --v3 --inodes=1024 --journal --time=1780000000 $SPEC >/dev/null 2>&1 || { echo mkfs failed; exit 1; }
mkdir -p "$TMPD/runs"
one() {
    local nr=$1 live="$TMPD/runs/l$1.img" s1="$TMPD/runs/w$1.txt" s2="$TMPD/runs/v$1.txt"
    cp --sparse=always "$TMPD/base.img" "$live"
    local drv=(-drive "file=$live,format=raw,if=ide,index=0,cache=directsync")
    qemu-system-x86_64 -accel tcg -kernel "$TMPD/k.mb" -m 512 -append "osum vfs nokbd $EXTRA script=fsrren w" \
        -serial "file:$s1" -display none -no-reboot "${drv[@]}" -device isa-debug-exit,iobase=0xf4,iosize=0x04 >/dev/null 2>&1 &
    local q=$!
    for _ in $(seq 1 1200); do
        tr -d '\000' < "$s1" 2>/dev/null | grep -qa 'fsrw: los' && break
        kill -0 $q 2>/dev/null || break
        sleep 0.05
    done
    sleep "$(awk "BEGIN{printf \"%.3f\", (120 + (($RANDOM*32768+$RANDOM) % 2600))/1000}")"
    kill -9 $q 2>/dev/null; wait $q 2>/dev/null
    timeout 900 qemu-system-x86_64 -accel tcg -kernel "$TMPD/k.mb" -m 512 -append "osum vfs nokbd $EXTRA script=fsrren v;fsck /dev/hda;exit" \
        -serial "file:$s2" -display none -no-reboot "${drv[@]}" -device isa-debug-exit,iobase=0xf4,iosize=0x04 >/dev/null 2>&1
    local t; t=$(tr -d '\000' < "$s2" 2>/dev/null)
    local pp ch bd fe at
    pp=$(echo "$t" | grep -a '^fsrren: pp = ' | head -1 | sed 's/.* = //')
    ch=$(echo "$t" | grep -a '^fsrren: ch = ' | head -1 | sed 's/.* = //')
    bd=$(echo "$t" | grep -a '^fsrren: body = ' | head -1 | sed 's/.* = //')
    at=$(echo "$t" | grep -a '^fsrren: at = ' | head -1 | sed 's/.* = //')
    fe=$(echo "$t" | grep -a '^fsck: errors = ' | head -1 | sed 's/.* = //')
    echo "run=$nr pp=${pp:-?} ch=${ch:-?} body=${bd:-?} fsck=${fe:-?} at=${at:-?}"
    rm -f "$live"
}
export -f one
export TMPD EXTRA="${FSR_EXTRA:-}"
seq 1 "$RUNS" | xargs -P "$PAR" -I{} bash -c 'one {}' > "$TMPD/res.txt"
sort -t= -k2 -n "$TMPD/res.txt"
bad=$(grep -vc 'pp=1 ch=1 body=1 fsck=0 ' "$TMPD/res.txt")
echo "RENAME-CRASH: runs=$(wc -l < "$TMPD/res.txt") bad=$bad"
