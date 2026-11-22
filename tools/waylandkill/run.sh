#!/usr/bin/env bash
. "$(dirname "${BASH_SOURCE[0]}")/../lib/brand-env.sh"
# SPDX-License-Identifier: GPL-2.0-only
# tools/waylandkill/run.sh -- wayd survives killed clients and closes their windows.
#
#   bash tools/waylandkill/run.sh [<work dir>]        (start it through /root/jarvis/bin/heavy)
#
#   1. three clients with a window are killed one after another: wayd logs the closed windows, stays up, the wm table keeps only live windows
#   2. counter-proof: BASE_WAYD=<elf of the old wayd> must leave the windows of the killed clients in the wm table
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
PROGS="sh sleep echo wayd kill"
CLIENTS=3

. tools/lib/firnenv.sh
bash tools/sync/build.sh "$TMPD/bin" 0 $PROGS > "$TMPD/b.txt" 2>&1 \
    && ok "programs build" || { bad "programs do not build"; tail -10 "$TMPD/b.txt"; echo "WL-KILL: $pass passed, $fail failed"; exit 1; }
./tools/build-kernel.sh "$TMPD/k0.img" --stufe 0 > "$TMPD/k.txt" 2>&1 \
    && ok "kernel builds" || { bad "kernel does not build"; echo "WL-KILL: $pass passed, $fail failed"; exit 1; }

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
    && ok "wlin builds" || { bad "wlin does not build"; head -5 "$TMPD/wl.txt"; echo "WL-KILL: $pass passed, $fail failed"; exit 1; }

{
    echo "wayd /tmp/wayland-0 2000000000 &"
    echo "sleep 2"
    for i in $(seq 1 "$CLIENTS"); do
        echo "wlin /tmp/wayland-0 300 K$i &"
        echo "PID=\$!"
        echo "sleep 6"
        echo "kill \$PID"
        echo "sleep 3"
    done
    echo "wlin /tmp/wayland-0 300 LAST &"
    echo "sleep 8"
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

up() { grep -ao "wlin\[$2\]: window up" "$TMPD/$1/clean.txt" | sort -u | wc -l; }
closed() { grep -ac "wayd: closed windows of client n=" "$TMPD/$1/clean.txt"; }
ended() { grep -ac "wayd: msgs=" "$TMPD/$1/clean.txt"; }
stale() { awk '/^wm: fenliste/ {n=0; next} /^wm: fen i=.* w=200 h=120 / {n++} END {print n+0}' "$TMPD/$1/clean.txt"; }

run_case new "$TMPD/bin/wayd.elf"
for i in $(seq 1 "$CLIENTS") LAST; do
    name=K$i; [ "$i" = LAST ] && name=LAST
    [ "$(up new "$name")" -ge 1 ] && ok "client $name opened a window" || bad "client $name opened no window"
done
C=$(closed new)
[ "$C" -ge "$CLIENTS" ] && ok "wayd closed the windows of $C killed clients" || bad "wayd closed windows of only $C clients"
[ "$(ended new)" -eq 0 ] && ok "wayd is still running" || bad "wayd ended"
S=$(stale new)
[ "$S" -le 1 ] && ok "wm table holds $S client window after the kills (only the live one)" || bad "wm table holds $S client windows (stale windows of killed clients)"

if [ -n "${BASE_WAYD:-}" ]; then
    run_case old "$BASE_WAYD"
    O=$(stale old)
    [ "$O" -gt 1 ] && ok "counter-proof: old wayd leaves $O stale windows in the wm table" || bad "counter-proof: old wayd left no stale windows"
fi
echo "WL-KILL: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
