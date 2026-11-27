#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/wayland/damage.sh -- wayd paints only damaged rectangles (WM_BLIT) and a full-damage commit costs one syscall.
#
#   /root/jarvis/bin/heavy bash tools/wayland/damage.sh [<work dir>]      (BASE_WAYD=<elf> runs the same client against an older wayd)
#
#   1. wldamage commits 100 noise frames with full damage; the client prints the elapsed milliseconds (compare against BASE_WAYD)
#   2. one commit damages only a blue block while a green block was also changed without damage: the screen shows the blue block
#      at the exact place and NO green (wayd honours the damage region)
set -uo pipefail
cd "$(dirname "$0")/../.."
ROOT=$(pwd)
export FIRNLIB="${FIRNLIB:-$ROOT/lib}"
pass=0; fail=0
ok()  { pass=$((pass+1)); printf '  OK    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }
note(){ printf '        %s\n' "$1"; }
finish() { echo "WL-DAMAGE: $pass passed, $fail failed"; [ "$fail" -eq 0 ]; exit $?; }

TMPD=${1:-$(mktemp -d)}
[ -n "${1:-}" ] || trap 'rm -rf "$TMPD"' EXIT
mkdir -p "$TMPD/bin"
WLB=${WLBUILD:-/root/wl-build}
PROGS="sh sleep echo cat ls wayd"

echo "== 1. build =="
. tools/lib/firnenv.sh
bash tools/sync/build.sh "$TMPD/bin" 0 $PROGS > "$TMPD/b.txt" 2>&1 && ok "firnc0 builds $(echo $PROGS | wc -w) programs" || { bad "the programs do not build"; tail -10 "$TMPD/b.txt" | sed 's/^/        /'; finish; }
./tools/build-kernel.sh "$TMPD/k0.img" --stufe 0 > "$TMPD/k.txt" 2>&1 && ok "the kernel builds" || { bad "the kernel does not build"; tail -5 "$TMPD/k.txt" | sed 's/^/        /'; finish; }
if musl-gcc -static -O2 -nostartfiles -T tools/foreign/osum.ld -Wl,--build-id=none -D_GNU_SOURCE \
        -I"$WLB/musl-root/include" -I"$WLB/wayland-1.21.0/gen" -o "$TMPD/wldamage" \
        tools/foreign/start.s tools/foreign/osum_main.c tools/wayland/wldamage.c \
        "$WLB/wayland-1.21.0/gen/xdg-shell-protocol.c" -L"$WLB/musl-root/lib" -lwayland-client -lffi 2>"$TMPD/wl.txt"; then
    ok "wldamage builds (libwayland-client, static musl)"
else
    bad "wldamage does not build (needs $WLB)"; head -5 "$TMPD/wl.txt" | sed 's/^/        /'; finish
fi

cat > "$TMPD/g.sh" <<EOS
wayd /tmp/wayland-0 2000000000 &
sleep 2
wldamage /tmp/wayland-0 &
sleep 700
echo ==FERTIG==
EOS
A=(build "$TMPD/disk.img" 32768 /lib/ "/lib/mono.ttf=assets/osum-mono.ttf"
   "/lib/sans.ttf=assets/osum-sans.ttf" /bin/ /t/ /tmp/ /var/ /var/log/ /etc/ /usr/ /usr/share/ /usr/share/wayd/
   "/bin/wldamage=$TMPD/wldamage" "/t/g.sh=$TMPD/g.sh")
[ -f assets/osum-icons.ttf ] && A+=("/lib/icons.ttf=assets/osum-icons.ttf")
[ -f assets/osum-sans-bold.ttf ] && A+=("/lib/bold.ttf=assets/osum-sans-bold.ttf")
for p in $PROGS; do
    if [ "$p" = wayd ] && [ -n "${BASE_WAYD:-}" ]; then A+=("/bin/wayd=$BASE_WAYD"); else A+=("/bin/$p=$TMPD/bin/$p.elf"); fi
done
bash tools/mkfsfi/mkfs.sh "${A[@]}" > "$TMPD/mkfs.txt" 2>&1 && ok "the disk is built" || { bad "mkfs"; finish; }

echo "== 2. boot =="
SOCK="$TMPD/mon.sock"; rm -f "$SOCK"
ACC=(); [ -w /dev/kvm ] && ACC=(-accel kvm -cpu host)
timeout 900 qemu-system-x86_64 "${ACC[@]}" -kernel "$TMPD/k0.img" -m 768 \
    -append "gfx disp wm wmdauer wmshell osum vfs bus script=sh /t/g.sh;exit" \
    -serial "file:$TMPD/ser.txt" -display none -no-reboot -vga std \
    -monitor "unix:$SOCK,server,nowait" \
    -drive "file=$TMPD/disk.img,format=raw,if=ide,index=0" \
    -device isa-debug-exit,iobase=0xf4,iosize=0x04 > "$TMPD/qemu.txt" 2>&1 &
QPID=$!
trap 'kill $QPID 2>/dev/null; [ -n "${1:-}" ] || rm -rf "$TMPD"' EXIT
waitfor() {
    local i=0
    while [ $i -lt $(( $2 * 5 )) ]; do
        grep -qaF -- "$1" "$TMPD/ser.txt" 2>/dev/null && return 0
        kill -0 "$QPID" 2>/dev/null || return 1
        sleep 0.2; i=$((i + 1))
    done
    return 1
}
clean() { tr -cd '\11\12\15\40-\176' < "$TMPD/ser.txt" | tr -d '\r'; }

waitfor "wldamage: partial_committed=1" 400 && ok "the client finished all phases" || { bad "the client did not finish"; clean | tail -20 | sed 's/^/        /'; finish; }
sleep 3
printf 'screendump %s\n' "$TMPD/s.ppm" | timeout 20 socat - "UNIX-CONNECT:$SOCK" >/dev/null 2>&1
sleep 3
ms=$(clean | grep -ao "wldamage: noise_ms=[0-9]*" | head -1 | sed 's/.*=//')
note "100 full-damage noise commits: ${ms:-?} ms"
[ -n "${ms:-}" ] && ok "noise timing printed" || bad "noise timing missing"
if out=$(python3 -I tools/wayland/damagepix.py "$TMPD/s.ppm" 2>&1); then
    ok "blue block exactly at the damaged place, no green (damage region honoured)"
else
    bad "damage region wrong"
fi
note "$out"
finish
