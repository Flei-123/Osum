#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
set -uo pipefail
cd "$(dirname "$0")/../.."
export FIRNLIB="$(pwd)/lib"
. tools/lib/firnenv.sh
firnenv_need_firnc1

ULD=kernel/user/user.ld
BLOCKS=8192
PROGS="init svc sh ls cat echo sleep"
BUNDLE=/apps/xremote.osp

pass=0; fail=0
ok()  { pass=$((pass+1)); printf '  OK    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }
is()  { if [ "$2" = "$3" ]; then ok "$1: $2"; else bad "$1: '$2', expected '$3'"; fi; }
col() { grep -aE "^$2 (running|stopped|done|waiting|failed) [0-9]+ [0-9]+ [0-9]+ [0-9]+ [a-z,]+" "$1" | tail -1 | awk -v c="$3" '{print $c}'; }

command -v qemu-system-x86_64 >/dev/null 2>&1 || { echo "XRINITSVC: skipped, qemu missing"; exit 0; }

T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT

echo "== 1. build =="
if [ -n "${KERNEL:-}" ]; then cp "$KERNEL" "$T/k0.img"; else bash tools/build-kernel.sh "$T/k0.img" --stufe 0 > "$T/kb.txt" 2>&1; fi
[ -s "$T/k0.img" ] && ok "kernel" || { bad "kernel build"; tail -5 "$T/kb.txt"; }
as --64 -o "$T/crt.o" kernel/user/crt.s
built=0
for p in $PROGS; do
    "$FIRNC" "kernel/user/$p.fi" -o "$T/p.o" > "$T/e.txt" 2>&1 \
        && ld -T "$ULD" --defsym=USER_ENTRY="_F0.u_start" -o "$T/$p.elf" "$T/crt.o" "$T/p.o" 2>/dev/null \
        && strip --strip-all "$T/$p.elf" && built=$((built+1)) || { bad "build $p"; head -4 "$T/e.txt"; }
done
is "programs built" "$built" "$(echo $PROGS | wc -w)"
bash tools/xremote/build-daemon.sh "$T/xremoted.elf" && ok "xremoted builds as a standalone ELF" || bad "xremoted build"
[ "$(cat pakete/xremote/INITTAB)" = "xremote:grafik:respawn:$BUNDLE/bin/xremoted:unless=/bin/xremoted" ] && ok "bundle INITTAB line" || bad "bundle INITTAB line: $(cat pakete/xremote/INITTAB)"

echo "== 2. images =="
printf 'sh:*:ctrl:/bin/sh\n' > "$T/inittab"
printf 'grafik\n' > "$T/ziel"
printf 'echo ==BEGIN==\nsleep 4\nsvc status\necho ==END==\n' > "$T/short.sh"
image() { # out bundle-inittab-source|- extra...
    local out=$1 tab=$2; shift 2
    local spec="" p
    for p in $PROGS; do spec="$spec /bin/$p=$T/$p.elf@755:0:0"; done
    local tabarg=()
    [ "$tab" != "-" ] && tabarg=("$BUNDLE/INITTAB=$tab@644:0:0")
    bash tools/mkfsfi/mkfs.sh build "$out" $BLOCKS /bin/ /etc/ /run/ /var/ /var/log/ /t/ /apps/ $BUNDLE/ $BUNDLE/bin/ \
        $spec "/etc/inittab=$T/inittab@644:0:0" "/etc/ziel=$T/ziel@644:0:0" "/t/short.sh=$T/short.sh@644:0:0" \
        "$BUNDLE/bin/xremoted=$T/xremoted.elf@644:0:0" "${tabarg[@]}" "$@" > "$T/mkfs.txt" 2>&1
}
image "$T/a.img" pakete/xremote/INITTAB && ok "image A: bundle with INITTAB, no /bin/xremoted" || bad "mkfs A"
image "$T/b.img" pakete/xremote/INITTAB "/bin/xremoted=$T/xremoted.elf@755:0:0" && ok "image B: same plus /bin/xremoted" || bad "mkfs B"
image "$T/c.img" - && ok "image C: bundle without INITTAB" || bad "mkfs C"

run_case() {
    cp "$2" "$T/live-$1.img"
    timeout 300 qemu-system-x86_64 -kernel "$T/k0.img" -m 256 \
        -append "osum nokbd nosched noproc nofs noring3 script=sh /t/short.sh" \
        -serial "file:$T/$1.txt" -display none -no-reboot \
        -drive "file=$T/live-$1.img,format=raw,if=ide,index=0" \
        -device isa-debug-exit,iobase=0xf4,iosize=0x04 >/dev/null 2>&1
    rm -f "$T/live-$1.img"
}

echo "== 3. boot =="
run_case a "$T/a.img"
is "A: xremoted from the bundle runs (init makes it executable)" "$(col "$T/a.txt" xremote 2)" "running"
run_case b "$T/b.img"
is "B: unless=/bin/xremoted keeps the packaged copy stopped" "$(col "$T/b.txt" xremote 2)" "stopped"
is "B: and it never started" "$(col "$T/b.txt" xremote 4)" "0"
run_case c "$T/c.img"
is "COUNTER-PROOF C: without INITTAB nothing starts" "$(grep -ac '^xremote ' "$T/c.txt")" "0"

echo
echo "XRINITSVC: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
