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
printf 'echo ==BEGIN==\nsleep 4\ncat /etc/xremote.conf\ncat /etc/xremote.secret\necho ==END==\n' > "$T/seed.sh"
printf 'enabled=0\n' > "$T/conf-off"
image() { # out bundle-inittab-source|- extra...
    local out=$1 tab=$2; shift 2
    local spec="" p
    for p in $PROGS; do spec="$spec /bin/$p=$T/$p.elf@755:0:0"; done
    local tabarg=()
    [ "$tab" != "-" ] && tabarg=("$BUNDLE/INITTAB=$tab@644:0:0")
    bash tools/mkfsfi/mkfs.sh build "$out" $BLOCKS /bin/ /etc/ /run/ /var/ /var/log/ /t/ /apps/ $BUNDLE/ $BUNDLE/bin/ \
        $spec "/etc/inittab=$T/inittab@644:0:0" "/etc/ziel=$T/ziel@644:0:0" "/t/short.sh=$T/short.sh@644:0:0" "/t/seed.sh=$T/seed.sh@644:0:0" \
        "$BUNDLE/bin/xremoted=$T/xremoted.elf@644:0:0" "${tabarg[@]}" "$@" > "$T/mkfs.txt" 2>&1
}
image "$T/a.img" pakete/xremote/INITTAB && ok "image A: bundle with INITTAB, no /bin/xremoted" || bad "mkfs A"
image "$T/b.img" pakete/xremote/INITTAB "/bin/xremoted=$T/xremoted.elf@755:0:0" && ok "image B: same plus /bin/xremoted" || bad "mkfs B"
image "$T/c.img" - && ok "image C: bundle without INITTAB" || bad "mkfs C"
image "$T/d.img" pakete/xremote/INITTAB "$BUNDLE/DEFAULTS=pakete/xremote/DEFAULTS@644:0:0" && ok "image D: bundle with DEFAULTS" || bad "mkfs D"
image "$T/e.img" pakete/xremote/INITTAB && ok "image E: bundle without DEFAULTS" || bad "mkfs E"
image "$T/f.img" pakete/xremote/INITTAB "$BUNDLE/DEFAULTS=pakete/xremote/DEFAULTS@644:0:0" "/etc/xremote.conf=$T/conf-off@644:0:0" && ok "image F: DEFAULTS and an existing conf" || bad "mkfs F"

run_case() {
    local script=${3:-/t/short.sh}
    cp "$2" "$T/live-$1.img"
    timeout 300 qemu-system-x86_64 -kernel "$T/k0.img" -m 256 \
        -append "osum nokbd nosched noproc nofs noring3 script=sh $script" \
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
run_case d "$T/d.img" /t/seed.sh
grep -aq '^enabled=1' "$T/d.txt" && grep -aq '^fixed=1' "$T/d.txt" && ok "D: the package DEFAULTS seed enabled=1 and fixed=1" || bad "D: conf not seeded"
grep -aq '^password=admin1234' "$T/d.txt" && ok "D: the default password lands in /etc/xremote.secret" || bad "D: secret not seeded"
run_case e "$T/e.img" /t/seed.sh
is "COUNTER-PROOF E: without DEFAULTS no conf is created" "$(grep -ac '^enabled=' "$T/e.txt")" "0"
run_case f "$T/f.img" /t/seed.sh
grep -aq '^enabled=0' "$T/f.txt" && ! grep -aq '^password=admin1234' "$T/f.txt" && ok "F: an existing conf is never overwritten" || bad "F: seeding overwrote the user conf"

echo
echo "XRINITSVC: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
