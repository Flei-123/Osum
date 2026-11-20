#!/usr/bin/env bash
. "$(dirname "${BASH_SOURCE[0]}")/../lib/brand-env.sh"
# SPDX-License-Identifier: GPL-2.0-only
# tools/waylandmany/run.sh -- wayd serves more than four clients at once (Firefox parent + content processes).
#
#   bash tools/waylandmany/run.sh [<work dir>]        (start it through /root/jarvis/bin/heavy)
#
#   1. nine wlin programs connect to one wayd; every one must open its window
#   2. counter-proof: BASE_WAYD=<elf of the old wayd> must leave programs without a window
set -uo pipefail
cd "$(dirname "$0")/../.."
ROOT=$(pwd)
export FIRNLIB="${FIRNLIB:-$ROOT/lib}"
pass=0; fail=0
ok()  { pass=$((pass+1)); printf '  OK    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }

TMPD=${1:-$(mktemp -d)}
[ -n "${1:-}" ] || trap 'rm -rf "$TMPD"' EXIT
mkdir -p "$TMPD/bin"
WLB=${WLBUILD:-/root/wl-build}
PROGS="sh sleep echo wayd"
CLIENTS=${CLIENTS:-9}

. tools/lib/firnenv.sh
bash tools/sync/build.sh "$TMPD/bin" 0 $PROGS > "$TMPD/b.txt" 2>&1 \
    && ok "programs build" || { bad "programs do not build"; tail -10 "$TMPD/b.txt"; echo "WL-MANY: $pass passed, $fail failed"; exit 1; }
./tools/build-kernel.sh "$TMPD/k0.img" --stufe 0 > "$TMPD/k.txt" 2>&1 \
    && ok "kernel builds" || { bad "kernel does not build"; echo "WL-MANY: $pass passed, $fail failed"; exit 1; }

GEN="$TMPD/gen"; mkdir -p "$GEN"; WPX=/usr/share/wayland-protocols
for pr in stable/viewporter/viewporter unstable/xdg-decoration/xdg-decoration-unstable-v1; do
    b=$(basename "$pr"); wayland-scanner client-header "$WPX/$pr.xml" "$GEN/$b-client-protocol.h" 2>>"$TMPD/gen.txt"
    wayland-scanner private-code "$WPX/$pr.xml" "$GEN/$b-protocol.c" 2>>"$TMPD/gen.txt"
done
musl-gcc -static -O2 -nostartfiles -T tools/foreign/osum.ld -Wl,--build-id=none -D_GNU_SOURCE \
    -I"$WLB/musl-root/include" -I"$WLB/wayland-1.21.0/gen" -I"$GEN" -o "$TMPD/wlin" \
    tools/foreign/start.s tools/foreign/osum_main.c tools/wayland/wlin.c \
    "$WLB/wayland-1.21.0/gen/xdg-shell-protocol.c" "$GEN/viewporter-protocol.c" "$GEN/xdg-decoration-unstable-v1-protocol.c" \
    -L"$WLB/musl-root/lib" -lwayland-client -lffi 2>"$TMPD/wl.txt" \
    && ok "wlin builds" || { bad "wlin does not build"; head -5 "$TMPD/wl.txt"; echo "WL-MANY: $pass passed, $fail failed"; exit 1; }

{
    echo "wayd /tmp/wayland-0 2000000000 &"
    echo "sleep 2"
    for i in $(seq 1 "$CLIENTS"); do
        echo "wlin /tmp/wayland-0 300 P$i &"
        echo "sleep 3"
    done
    echo "sleep 8"
    echo "echo ==W-READY=="
    echo "sleep 20"
    echo "echo ==FERTIG=="
} > "$TMPD/g.sh"

run_case() { # label wayd-elf
    local label=$1 wayd=$2 d="$TMPD/$1"
    mkdir -p "$d"
    local A=(build "$d/disk.img" 32768 /lib/ "/lib/mono.ttf=assets/osum-mono.ttf"
        "/lib/sans.ttf=assets/osum-sans.ttf" /bin/ /t/ /tmp/ /var/ /var/log/ /etc/ /usr/ /usr/share/ /usr/share/wayd/
        "/bin/wlin=$TMPD/wlin" "/t/g.sh=$TMPD/g.sh")
    [ -f assets/osum-icons.ttf ] && A+=("/lib/icons.ttf=assets/osum-icons.ttf")
    [ -f assets/osum-sans-bold.ttf ] && A+=("/lib/bold.ttf=assets/osum-sans-bold.ttf")
    local p
    for p in $PROGS; do
        if [ "$p" = wayd ]; then A+=("/bin/wayd=$wayd"); else A+=("/bin/$p=$TMPD/bin/$p.elf"); fi
    done
    bash tools/mkfsfi/mkfs.sh "${A[@]}" > "$d/mkfs.txt" 2>&1 || { bad "$label: mkfs"; return 1; }
    local ACC=(); [ -w /dev/kvm ] && ACC=(-accel kvm -cpu host)
    timeout 600 qemu-system-x86_64 "${ACC[@]}" -kernel "$TMPD/k0.img" -m 768 \
        -append "gfx disp wm wmdauer wmshell osum vfs bus script=sh /t/g.sh;exit" \
        -serial "file:$d/ser.txt" -display none -no-reboot -vga std \
        -drive "file=$d/disk.img,format=raw,if=ide,index=0" \
        -device isa-debug-exit,iobase=0xf4,iosize=0x04 > "$d/qemu.txt" 2>&1 &
    local qpid=$! i=0
    while [ $i -lt 1500 ]; do
        grep -qaF -- "==FERTIG==" "$d/ser.txt" 2>/dev/null && break
        kill -0 "$qpid" 2>/dev/null || break
        sleep 0.4; i=$((i + 1))
    done
    kill "$qpid" 2>/dev/null; wait "$qpid" 2>/dev/null
    tr -cd '\11\12\15\40-\176' < "$d/ser.txt" | tr -d '\r' > "$d/clean.txt"
}

up_count() { grep -ao "wlin\[P[0-9]*\]: window up" "$TMPD/$1/clean.txt" | sort -u | wc -l; }

run_case new "$TMPD/bin/wayd.elf"
N=$(up_count new)
[ "$N" -ge "$CLIENTS" ] && ok "$N of $CLIENTS programs opened a window" || { bad "only $N of $CLIENTS programs opened a window"; tail -15 "$TMPD/new/clean.txt" | sed 's/^/        /'; }

if [ -n "${BASE_WAYD:-}" ]; then
    run_case old "$BASE_WAYD"
    O=$(up_count old)
    [ "$O" -lt "$CLIENTS" ] && ok "counter-proof: old wayd served only $O of $CLIENTS" || bad "counter-proof: old wayd served all $CLIENTS"
fi
echo "WL-MANY: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
