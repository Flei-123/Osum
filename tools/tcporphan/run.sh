#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/tcporphan/run.sh -- the TCP table (MAXCONN slots of lib/net/tcp.fi) must not be held by orphans whose peer is gone.
#
#   /root/jarvis/bin/heavy bash tools/tcporphan/run.sh [noorphanreap]
#
# MAXCONN guest connections fill the table, the network disappears (netdev_del), the programs end (FIN never acknowledged),
# then new connections are tried. With the reaper they get a slot (eviction under pressure, aging after 20 s). The word
# noorphanreap is the counter-proof: connect() fails with "Too many open files in system".
set -uo pipefail
cd "$(dirname "$0")/../.."
WD=${XR_WD:-/root/fxhp}
WORD=${1:-}
PORT=$((19000 + $$ % 900))
CONNS=$(sed -n 's/^const MAXCONN: usize = //p' lib/net/tcp.fi)
pass=0; fail=0
ok()  { pass=$((pass+1)); printf '  OK    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }
[ -e "$WD/fxrun/spec.txt" ] || { echo "TCPORPHAN: missing $WD/fxrun/spec.txt"; exit 1; }
T=$(mktemp -d)
PIDS=()
cleanup() {
    for p in "${PIDS[@]:-}"; do [ -n "$p" ] && kill "$p" 2>/dev/null; done
    rm -rf "$T"
}
trap cleanup EXIT
OUT=$T/out
MONSOCK=$T/mon.sock
mkdir -p "$OUT" "$T/fx" "$T/wd/fxrun"
python3 tools/tcporphan/peer.py silent "$PORT" & PIDS+=($!)
(
    while true; do
        grep -aq '^TO-BLACKHOLE' "$OUT/ser.txt" 2>/dev/null && break
        sleep 1
    done
    python3 tools/tcporphan/monsend.py "$MONSOCK" "netdev_del n0"
) & PIDS+=($!)
sed -e "s/@PORT@/$PORT/g" -e "s/@CONNS@/$CONNS/g" tools/tcporphan/guest.sh > "$T/guest.sh"
grep -E '/@755$|^/(bin|sbin)/|^/usr/(bin|sbin)/[a-z0-9_.-]*->/bin/busybox|^/lib/(ld-musl|libc\.musl)' "$WD/fxrun/spec.txt" > "$T/wd/fxrun/spec.txt"
KERNEL=${KERNEL:-} DONE=TO-END TMO=${TO_TMO:-600} MEM=512 \
    KARGS="osum vfs nokbd nosched noproc nofs fremdtrace gfx nic nip=10.0.2.15/24 ngw=10.0.2.2 $WORD" \
    QEMU_EXTRA="-monitor unix:$MONSOCK,server,nowait -vga std -netdev user,id=n0 -device virtio-net-pci,netdev=n0,mac=52:54:00:5b:1d:0a" \
    SPEC="$T/wd/fxrun/spec.txt" bash tools/linuxapps/run.sh "$WD" "$T/guest.sh" "$OUT" > "$T/linuxapps.log" 2>&1
tail -n 2 "$T/linuxapps.log" | sed 's/^/        /'
C=$OUT/ser.clean
grep -a '^TO-\|inet: tcp orphan' "$C" | head -20
line() { grep -a "^$1" "$C" | head -1; }
has() { echo "$1" | grep -q -- "$2" && echo 1 || echo 0; }
chk() { if [ "$1" = 1 ]; then ok "$2"; else bad "$2"; fi; }
L=$(line TO-OPEN);   chk "$(has "$L" "rows=$((CONNS - 1))")" "$((CONNS - 1)) connections fill the table, one slot stays reserved for the bridge ($L)"
L=$(line TO-CLOSED); chk "$(has "$L" 'rows=0')" "all programs ended, sockets gone from the table ($L)"
L=$(line TO-NEW1); L2=$(line TO-NEW2)
if [ "$WORD" = noorphanreap ]; then
    chk "$(has "$L" 'rows=0')" "counter-proof: without the reaper the orphans keep every slot, connect() gets none ($L)"
else
    chk "$(has "$L" 'rows=1')" "a new connection gets a slot while orphans fill the table ($L)"
    chk "$(has "$L2" 'rows=1')" "and again after the orphans aged out ($L2)"
    N=$(grep -ac 'inet: tcp orphan' "$C")
    chk "$([ "$N" -ge 1 ] && echo 1 || echo 0)" "orphans were evicted or aged out ($N log lines)"
fi
echo "== $pass ok, $fail fail"
[ "$fail" -eq 0 ]
