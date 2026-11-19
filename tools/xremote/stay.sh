#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
set -uo pipefail
cd "$(dirname "$0")/../.."
WD=${XR_WD:-/root/fxhp}
XRTOOLS=${XR_TOOLS:-/root/jarvis/data/orientos-xremote}
HOSTBIN=${XR_HOST:-$XRTOOLS/v2/freeviewer-host}
VIEWER=${XR_VIEWER:-$XRTOOLS/freeviewer-glibc}
RELAYDIR=${XR_RELAY:-/root/projects/freeviewer/relay}
NODEPATH=${XR_LIBS:-/root/jarvis/node_modules}
LIBGCC=${XR_LIBGCC:-$WD/fx-root/usr/lib/libgcc_s.so.1}
STAYSECS=${XR_STAY:-600}
HOSTSECS=${XR_HOSTSECS:-240}
TAILSECS=${XR_TAIL:-60}
MIN_FRAMES=${XR_MIN_FRAMES:-5}
ROUND_PAUSE=${XR_ROUND_PAUSE:-45}
EXTRA_WORDS=${XR_BOOT_WORDS:-}
BREAK=${XR_BREAK:-0}
RELAYPORT=$((19000 + $$ % 1000))
pass=0; fail=0
ok()  { pass=$((pass+1)); printf '  OK    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }
for f in "$HOSTBIN" "$VIEWER" "$RELAYDIR/relay.js" "$WD/fxrun/spec.txt" "$LIBGCC"; do
    [ -e "$f" ] || { echo "XRSTAY: missing $f"; exit 1; }
done
for t in qemu-system-x86_64 node musl-gcc python3 curl; do
    command -v "$t" >/dev/null 2>&1 || { echo "XRSTAY: skipped, $t missing"; exit 0; }
done
T=$(mktemp -d)
RP=""; VP=""
cleanup() {
    [ -s "$T/relay.pid" ] && kill "$(cat "$T/relay.pid")" 2>/dev/null
    [ -n "$RP" ] && kill "$RP" 2>/dev/null
    [ -n "$VP" ] && kill "$VP" 2>/dev/null
    rm -rf "$T"
}
trap cleanup EXIT
OUT=${XR_OUT:-$T/out}
mkdir -p "$OUT" "$T/relay" "$T/home" "$T/fx" "$T/wd/fxrun"
sed -e "s/@RELAYPORT@/$RELAYPORT/g" -e "s/@HOSTSECS@/$HOSTSECS/g" -e "s/@STAYSECS@/$((STAYSECS + 60))/g" -e "s/@TAILSECS@/$TAILSECS/g" tools/xremote/guest-stay.sh > "$T/xr3.sh"
cp tools/xremote/guest-desktop.sh "$T/guest.sh"
grep -E '/@755$|^/(bin|sbin)/|^/usr/(bin|sbin)/[a-z0-9_.-]*->/bin/busybox|^/lib/(ld-musl|libc\.musl)' "$WD/fxrun/spec.txt" > "$T/fx/spec.txt"
{
    echo "/opt/@755"; echo "/opt/xr/@755"; echo "/usr/@755"; echo "/usr/lib/@755"
    echo "/usr/lib/libgcc_s.so.1=$LIBGCC@755"
    echo "/opt/xr/freeviewer-host=$HOSTBIN@755"
} | awk '!seen[$0]++' >> "$T/fx/spec.txt"
cp "$T/fx/spec.txt" "$T/wd/fxrun/spec.txt"
cp "$RELAYDIR"/*.js "$T/relay/"
start_relay() {
    (cd "$T/relay" && NODE_PATH="$NODEPATH" FV_PORT=$RELAYPORT FV_DATA="$T/relay/hosts.json" FV_BUCH=0 sh -c 'echo $$ > "$0"; exec node relay.js' "$T/relay.pid" 2>&1 | while IFS= read -r l; do printf '%s %s\n' "$(date +%s)" "$l"; done >> "$T/relay.log") &
    RP=$!
    sleep 2
}
start_relay
curl -s -m 3 "http://127.0.0.1:$RELAYPORT/fv/health" | grep -q '"ok":true' && ok "relay up on port $RELAYPORT" || bad "relay did not start"
(
    i=0
    while [ $i -lt $((HOSTSECS + 300)) ]; do
        ID=$(grep -ao 'XR-ID [0-9]*' "$OUT/ser.txt" 2>/dev/null | head -1 | cut -d' ' -f2)
        [ -n "$ID" ] && break
        sleep 1; i=$((i + 1))
    done
    [ -n "$ID" ] || exit 0
    echo "$ID" > "$T/hostid"
    export HOME="$T/home" FV_RELAY="ws://127.0.0.1:$RELAYPORT/fv/ws" FV_ALLOW_INSECURE_RELAY=1 FV_NOP2P=1
    sleep 15
    date +%s > "$T/viewer.start"
    ROUND=0
    BROKEN=0
    while [ $(( $(date +%s) - $(cat "$T/viewer.start") )) -lt "$STAYSECS" ]; do
        if [ "$BREAK" = 1 ] && [ "$BROKEN" = 0 ] && [ $(( $(date +%s) - $(cat "$T/viewer.start") )) -ge $((STAYSECS / 2)) ]; then
            BROKEN=1
            kill -9 "$(cat "$T/relay.pid")" 2>/dev/null
            sleep 3
            start_relay
        fi
        ROUND=$((ROUND + 1))
        timeout 90 "$VIEWER" --connect "$ID" xrpass "$MIN_FRAMES" 2>&1 | while IFS= read -r l; do printf '%s %s\n' "$(date +%s)" "$l"; done > "$T/viewer.$ROUND.txt"
        sleep "$ROUND_PAUSE"
    done
    echo "$ROUND" > "$T/rounds"
    date +%s > "$T/viewer.end"
    sleep 5
    curl -s -m 5 "http://127.0.0.1:$RELAYPORT/fv/online?ids=$ID" > "$T/online.txt"
) &
VP=$!
BOOTARGS="gfx disp wm wmdauer wmshell osum vfs bus fremdtrace nic nip=10.0.2.15/24 ngw=10.0.2.2 $EXTRA_WORDS script=sh /etc/fx.sh;exit"
env GUI=1 "EXTRA=/etc/xr3.sh=$T/xr3.sh@755" KERNEL=${KERNEL:-} DONE=XR-END TMO=${XR_TMO:-1800} MEM=1024 \
    KARGS="$BOOTARGS" \
    QEMU_EXTRA="-vga std -netdev user,id=n0 -device virtio-net-pci,netdev=n0,mac=52:54:00:5b:1d:01" \
    SPEC="$T/wd/fxrun/spec.txt" bash tools/linuxapps/run.sh "$WD" "$T/guest.sh" "$OUT" > "$T/linuxapps.log" 2>&1
wait "$VP" 2>/dev/null; VP=""
S="$OUT/ser.clean"
tail -n 3 "$T/linuxapps.log" | sed 's/^/        /'
[ -s "$T/hostid" ] && ok "host registered at the relay (ID $(cat "$T/hostid"))" || bad "host never printed an ID"
V0=$(cat "$T/viewer.start" 2>/dev/null || echo 0); V1=$(cat "$T/viewer.end" 2>/dev/null || echo 0)
ROUNDS=$(cat "$T/rounds" 2>/dev/null || echo 0)
LASTED=$((V1 - V0))
echo "        $ROUNDS viewer sessions over ${LASTED}s"
[ "$LASTED" -ge "$STAYSECS" ] && [ "$ROUNDS" -ge 3 ] && ok "$ROUNDS viewer sessions over ${LASTED}s (>= ${STAYSECS}s)" || bad "only $ROUNDS viewer sessions over ${LASTED}s of ${STAYSECS}s"
POOR=0
r=1
while [ "$r" -le "$ROUNDS" ]; do
    n=$(grep -ac ' frame ' "$T/viewer.$r.txt" 2>/dev/null)
    echo "        session $r: ${n:-0} frames"
    [ "${n:-0}" -ge "$MIN_FRAMES" ] || POOR=$((POOR + 1))
    r=$((r + 1))
done
[ "$POOR" = 0 ] && ok "every viewer session received >= $MIN_FRAMES frames" || bad "$POOR of $ROUNDS viewer sessions got fewer than $MIN_FRAMES frames: $(grep -a -i 'ended\|beendet\|offline\|busy\|error' "$T"/viewer.[0-9]*.txt 2>/dev/null | grep -v ALSA | tail -n 2 | tr '\n' ';')"
HON=$(grep -ac 'host online' "$T/relay.log"); PAIR=$(grep -ac ' paired ' "$T/relay.log")
HOFF=$(grep -a 'host offline' "$T/relay.log" | awk -v e="$V1" '$1 < e' | wc -l)
echo "        relay: host online x$HON, host offline during the test x$HOFF, paired x$PAIR"
[ "$HON" = 1 ] && [ "$HOFF" = 0 ] && ok "host stayed registered at the relay, no re-registration" || bad "relay saw host online x$HON, offline x$HOFF before the end"
[ "$PAIR" = "$ROUNDS" ] && ok "one pairing per viewer session ($PAIR)" || bad "relay saw $PAIR pairings for $ROUNDS sessions"
grep -aq 'relay session failed' "$S" && bad "host log: $(grep -a 'relay session failed' "$S" | head -1 | cut -c1-160)" || ok "host log has no relay session failure"
grep -aq '"online":true' "$T/online.txt" 2>/dev/null && ok "host still online at the relay after the last session" || bad "host offline at the relay after the sessions: $(cat "$T/online.txt" 2>/dev/null)"
ORPH=$(grep -ac 'inet: tcp orphan' "$S")
echo "        kernel tcp orphan lines: $ORPH"
[ "$ORPH" = 0 ] && ok "kernel reaped no TCP connection during the session" || bad "kernel reaped $ORPH TCP connections: $(grep -a 'inet: tcp orphan' "$S" | head -2 | tr '\n' ';')"
echo "== $pass ok, $fail fail"
if [ -n "${KEEP:-}" ]; then
    mkdir -p "${KEEP_DIR:-/tmp/xremote-stay-keep}"; cp -r "$OUT" "$T"/viewer.*txt "$T/relay.log" "${KEEP_DIR:-/tmp/xremote-stay-keep}/" 2>/dev/null
fi
[ "$fail" -eq 0 ]
