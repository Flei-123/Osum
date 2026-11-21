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
OLD_REF=${OLD_REF:-3fde7534e}

pass=0; fail=0
ok()  { pass=$((pass+1)); printf '  OK    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }
has() { if grep -aq "$2" "$3"; then ok "$1"; else bad "$1"; fi; }
hasnt() { if grep -aq "$2" "$3"; then bad "$1"; else ok "$1"; fi; }

command -v qemu-system-x86_64 >/dev/null 2>&1 || { echo "INITWM: skipped, qemu missing"; exit 0; }

T=$(mktemp -d)
trap 'git worktree remove --force "$T/old" >/dev/null 2>&1; rm -rf "$T"' EXIT

echo "== 1. build =="
if [ -n "${KERNEL:-}" ]; then cp "$KERNEL" "$T/new.img"; else bash tools/build-kernel.sh "$T/new.img" --stufe 0 > "$T/kb.txt" 2>&1; fi
[ -s "$T/new.img" ] && ok "kernel (new)" || { bad "kernel build"; tail -5 "$T/kb.txt"; }
if [ -n "${OLD_KERNEL:-}" ]; then cp "$OLD_KERNEL" "$T/old.img"; else
    git worktree add --detach "$T/old" "$OLD_REF" > "$T/wt.txt" 2>&1
    (cd "$T/old" && FIRNLIB="$(pwd)/lib" bash tools/build-kernel.sh "$T/old.img" --stufe 0 > "$T/kbo.txt" 2>&1)
fi
[ -s "$T/old.img" ] && ok "kernel (old, $OLD_REF)" || { bad "old kernel build"; tail -5 "$T/kbo.txt"; }
as --64 -o "$T/crt.o" kernel/user/crt.s
built=0
for p in $PROGS; do
    "$FIRNC" "kernel/user/$p.fi" -o "$T/p.o" > "$T/e.txt" 2>&1 \
        && ld -T "$ULD" --defsym=USER_ENTRY="_F0.u_start" -o "$T/$p.elf" "$T/crt.o" "$T/p.o" 2>/dev/null \
        && strip --strip-all "$T/$p.elf" && built=$((built+1)) || { bad "build $p"; head -4 "$T/e.txt"; }
done
[ "$built" = "$(echo $PROGS | wc -w)" ] && ok "programs built ($built)" || bad "programs built: $built"

echo "== 2. image =="
printf 'mark:grafik:once:/bin/echo WMINIT-ALIVE\nstale:grafik:once:/bin/cat /run/autostart.done\n' > "$T/inittab"
printf 'grafik\n' > "$T/ziel"
printf 'wmpkg:grafik:once:/apps/wm.osp/bin/hello BUNDLE-ALIVE\n' > "$T/bundle-inittab"
printf 'STALEMARK\n' > "$T/stale"
spec=""
for p in $PROGS; do spec="$spec /bin/$p=$T/$p.elf@755:0:0"; done
cp "$T/echo.elf" "$T/hello.elf"
bash tools/mkfsfi/mkfs.sh build "$T/a.img" $BLOCKS /bin/ /etc/ /run/ /var/ /var/log/ /apps/ /apps/wm.osp/ /apps/wm.osp/bin/ \
    $spec "/etc/inittab=$T/inittab@644:0:0" "/etc/ziel=$T/ziel@644:0:0" "/run/autostart.done=$T/stale@644:0:0" \
    "/apps/wm.osp/bin/hello=$T/hello.elf@644:0:0" "/apps/wm.osp/INITTAB=$T/bundle-inittab@644:0:0" > "$T/mkfs.txt" 2>&1 && ok "image" || { bad "mkfs"; tail -3 "$T/mkfs.txt"; }

run_case() {
    cp "$T/a.img" "$T/live-$1.img"
    timeout 120 qemu-system-x86_64 -kernel "$T/$2.img" -m 256 \
        -append "osum wmshell nokbd nosched noproc nofs noring3" \
        -serial "file:$T/$1.txt" -display none -no-reboot \
        -drive "file=$T/live-$1.img,format=raw,if=ide,index=0" \
        -device isa-debug-exit,iobase=0xf4,iosize=0x04 >/dev/null 2>&1
    rm -f "$T/live-$1.img"
}

echo "== 3. boot with wmshell =="
run_case new new
has "init starts although wmshell owns the shell" "osum: pid1 init (wm)" "$T/new.txt"
has "init mounted and parsed the table" "init: dienste=" "$T/new.txt"
has "INITTAB service ran" "WMINIT-ALIVE" "$T/new.txt"
has "bundle INITTAB drop-in ran, 0644 binary made executable by init" "BUNDLE-ALIVE" "$T/new.txt"
hasnt "stale /run marker was cleared at boot" "STALEMARK" "$T/new.txt"
run_case old old
hasnt "COUNTER-PROOF old kernel: init never starts under wmshell" "WMINIT-ALIVE" "$T/old.txt"

echo
echo "INITWM: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
