#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/xremote/run.sh -- gate for the FreeViewer host (freeviewer-host, musl) running inside the Osum guest.
#
#   /root/jarvis/bin/heavy bash tools/xremote/run.sh
#
# Env: XR_WD (linuxapps workdir with fxrun/spec.txt, default /root/fxhp), XR_HOST (freeviewer-host musl binary),
#      XR_VIEWER (glibc freeviewer used as the remote viewer on the build host), XR_RELAY (relay dir with relay.js),
#      XR_LIBS (node_modules parent for the relay), KERNEL (prebuilt kernel image), KEEP=1 keeps the output dir.
# Proves: the host starts in the guest, registers at a relay over the guest NIC, a viewer receives frames of the REAL
#         guest screen through the osum_shot backend, and viewer input arrives as osum_tipp strokes. Controls are
#         counters read before the session (zero) and the viewer's frame size against the kernel's own screen size.
set -uo pipefail
cd "$(dirname "$0")/../.."
ROOT=$(pwd)
WD=${XR_WD:-/root/fxhp}
HOSTBIN=${XR_HOST:-/root/jarvis/data/staff_wt/orientos/fv-host/target/x86_64-unknown-linux-musl/release/freeviewer-host}
VIEWER=${XR_VIEWER:-/root/jarvis/data/staff_wt/orientos/x1-out/freeviewer-glibc}
RELAYDIR=${XR_RELAY:-/root/projects/freeviewer/relay}
NODEPATH=${XR_LIBS:-/root/jarvis/node_modules}
LIBGCC=${XR_LIBGCC:-$WD/fx-root/usr/lib/libgcc_s.so.1}
SESSIONSECS=${XR_SESSION:-60}
CLIPSECS=$((SESSIONSECS * 2))
TAILSECS=${XR_TAIL:-30}
HOSTSECS=${XR_HOSTSECS:-240}
RELAYPORT=$((17000 + $$ % 1000))
pass=0; fail=0
ok()  { pass=$((pass+1)); printf '  OK    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }
for f in "$HOSTBIN" "$VIEWER" "$RELAYDIR/relay.js" "$WD/fxrun/spec.txt" "$LIBGCC"; do
    [ -e "$f" ] || { echo "XREMOTE: missing $f"; exit 1; }
done
for t in qemu-system-x86_64 node musl-gcc python3; do
    command -v "$t" >/dev/null 2>&1 || { echo "XREMOTE: skipped, $t missing"; exit 0; }
done
T=$(mktemp -d)
RP=""; VP=""
cleanup() {
    [ -n "$RP" ] && kill "$RP" 2>/dev/null
    [ -n "$VP" ] && kill "$VP" 2>/dev/null
    rm -rf "$T"
}
trap cleanup EXIT
OUT=${XR_OUT:-$T/out}
mkdir -p "$OUT" "$T/relay" "$T/home" "$T/fx"
musl-gcc -O2 -fPIE -pie -o "$T/xrprobe" tools/xremote/probe.c || { echo "XREMOTE: probe build failed"; exit 1; }
sed -e "s/@RELAYPORT@/$RELAYPORT/g" -e "s/@HOSTSECS@/$HOSTSECS/g" -e "s/@SESSIONSECS@/$SESSIONSECS/g" -e "s/@CLIPSECS@/$CLIPSECS/g" -e "s/@TAILSECS@/$TAILSECS/g" "${XR_GUEST:-tools/xremote/guest.sh}" > "$T/guest.sh"
grep -E '/@755$|^/(bin|sbin)/|^/usr/(bin|sbin)/[a-z0-9_.-]*->/bin/busybox|^/lib/(ld-musl|libc\.musl)' "$WD/fxrun/spec.txt" > "$T/fx/spec.txt"
{
    echo "/opt/@755"; echo "/opt/xr/@755"; echo "/usr/@755"; echo "/usr/lib/@755"
    echo "/usr/lib/libgcc_s.so.1=$LIBGCC@755"
    echo "/opt/xr/freeviewer-host=$HOSTBIN@755"
    echo "/opt/xr/xrprobe=$T/xrprobe@755"
} | awk '!seen[$0]++' >> "$T/fx/spec.txt"
mkdir -p "$T/wd/fxrun"; cp "$T/fx/spec.txt" "$T/wd/fxrun/spec.txt"
cp "$RELAYDIR"/*.js "$T/relay/"
(cd "$T/relay" && NODE_PATH="$NODEPATH" FV_PORT=$RELAYPORT FV_DATA="$T/relay/hosts.json" FV_BUCH=0 exec node relay.js > "$T/relay.log" 2>&1) &
RP=$!
sleep 2
kill -0 "$RP" 2>/dev/null && ok "relay up on port $RELAYPORT" || bad "relay did not start"
ACC=(); [ -w /dev/kvm ] && ACC=(-accel kvm -cpu host)
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
    sleep 3
    timeout 90 "$VIEWER" --connect "$ID" xrpass 5 > "$T/viewer.txt" 2>&1
    sleep 2
    timeout 90 "$VIEWER" --inputtest "$ID" xrpass > "$T/inputtest.txt" 2>&1
) &
VP=$!
KERNEL=${KERNEL:-} DONE=XR-END TMO=${XR_TMO:-900} MEM=1024 \
    KARGS="osum vfs nokbd nosched noproc nofs fremdtrace gfx nic nip=10.0.2.15/24 ngw=10.0.2.2" \
    QEMU_EXTRA="-vga std -netdev user,id=n0 -device virtio-net-pci,netdev=n0,mac=52:54:00:5b:1d:01" \
    SPEC="$T/wd/fxrun/spec.txt" bash tools/linuxapps/run.sh "$WD" "$T/guest.sh" "$OUT" > "$T/linuxapps.log" 2>&1
wait "$VP" 2>/dev/null; VP=""
S="$OUT/ser.clean"
tail -n 3 "$T/linuxapps.log" | sed 's/^/        /'
grep -aq '^XR1 rc=0' "$S" && ok "freeviewer-host --version rc=0 in the guest" || bad "freeviewer-host --version failed in the guest"
grep -a '^XR-SCREEN' "$S" | head -1 | sed 's/^/        /'
SW=$(grep -ao 'XR-SCREEN ready=1 width=[0-9]*' "$S" | head -1 | grep -o '[0-9]*$')
SH=$(grep -ao 'XR-SCREEN ready=1 width=[0-9]* height=[0-9]*' "$S" | head -1 | grep -o '[0-9]*$')
[ -n "$SW" ] && ok "kernel screen ${SW}x${SH} visible to a Linux process" || bad "osum_shot not ready for a Linux process"
grep -aq '^XR-GRAB' "$S" && ok "full SH_ARM + SH_GRAB from a Linux process" || bad "SH_GRAB failed from a Linux process"
grep -a '^XR-INPUT' "$S" | head -1 | grep -q 'total=0 ' && ok "control: no strokes before the session" || bad "control: strokes counted before the session"
[ -s "$T/hostid" ] && ok "host registered at the relay (ID $(cat "$T/hostid"))" || bad "host never printed an ID"
grep -aq "monitor 0: osum ${SW}x${SH}" "$T/viewer.txt" 2>/dev/null && ok "viewer sees monitor osum ${SW}x${SH}" || bad "viewer did not see the osum monitor"
FR=$(grep -ac '^frame ' "$T/viewer.txt" 2>/dev/null)
[ "${FR:-0}" -ge 2 ] && ok "viewer received $FR frames of the guest screen" || bad "viewer received ${FR:-0} frames"
grep -aq "frame [0-9]* ${SW}x${SH}" "$T/viewer.txt" 2>/dev/null && ok "frame size equals the kernel screen size" || bad "frame size differs from the kernel screen size"
IN_BASE=$(grep -a '^XR-INPUT' "$S" | sed -n 2p | grep -o 'total=[0-9]*' | cut -d= -f2); IN_LAST=$(grep -a '^XR-INPUT' "$S" | tail -1 | grep -o 'total=[0-9]*' | cut -d= -f2)
[ "${IN_LAST:-0}" -gt "${IN_BASE:-0}" ] && ok "viewer input arrived as $((IN_LAST - IN_BASE)) osum_tipp strokes after the baseline $IN_BASE" || bad "no osum_tipp strokes after the input test"
WL=$(grep -a '^XR-WHEEL' "$S" | head -1)
echo "$WL" | grep -q 'deny=-[0-9]* after_deny=0 ' && ok "wheel without a permit is refused and changes nothing" || bad "wheel without a permit: $WL"
echo "$WL" | grep -q 'arm=0 too_big=-[0-9]* bad_axis=-[0-9]* after_bad=0 ' && ok "wheel rejects 100 notches and axis 2" || bad "wheel argument checks: $WL"
echo "$WL" | grep -q 'down=0 up=0 sum=2 right=0 hsum=2 ' && ok "wheel +5/-3 vertical sums to 2, horizontal +2 adds to hwheel" || bad "wheel sums: $WL"
echo "$WL" | grep -q 'final=0 hfinal=0$' && ok "wheel counters restored to zero before the session" || bad "wheel counters not zero: $WL"
P0=$(grep -a '^XR-INPUT' "$S" | sed -n 2p)
P1=$(grep -a '^XR-INPUT' "$S" | tail -1)
echo "$P0" | grep -q 'wheel=0 hwheel=0 buttons=0$' && ok "control: wheel and buttons zero before the session" || bad "control: wheel/buttons not zero before the session: $P0"
echo "$P1" | grep -q 'wheel=2 hwheel=0 buttons=0$' && ok "viewer wheel (-3 then +1 lines) reached the kernel as a net 2 notches down" || bad "wheel after the session: $P1"
echo "$P1" | grep -q 'px=620 py=440 ' && ok "pointer at 620,440 after abs 2500/2500 plus relative +300/+240 read from the kernel" || bad "pointer after the session: $P1"
echo "$P0" | grep -q 'px=620 py=440 ' && bad "control: pointer already at the final position before the session" || ok "control: pointer not at the final position before the session"
grep -aq '^XR-CLIP get len=0 ' "$S" && ok "control: guest clipboard empty before the session" || bad "control: guest clipboard not empty before the session"
CW=$(grep -a '^XR-CLIP wait' "$S" | head -1)
echo "$CW" | grep -q 'head=FV-CLIP-' && ok "viewer clipboard text arrived in the guest clipboard ($CW)" || bad "viewer clipboard text missing in the guest: $CW"
grep -aq 'clip: from viewer [0-9]* bytes applied=true' "$S" && ok "host wrote the viewer text through the bus" || bad "host did not apply the viewer clipboard text"
CB=$(grep -a '^XR-CLIP putbig' "$S" | head -1)
CBS=$(echo "$CB" | grep -o 'sum=[0-9a-f]*' | cut -d= -f2)
[ -n "$CBS" ] && grep -aq "clip: to viewer 5000 bytes sum=$CBS" "$S" && ok "5000-byte guest clipboard text read by the host through a segment, checksum $CBS equal" || bad "host did not read the 5000-byte guest text intact ($CB)"
grep -aq 'Zwischenablage-Update(s) vom Host empfangen' "$T/inputtest.txt" 2>/dev/null && ok "viewer received the guest clipboard from the host" || bad "viewer received no clipboard from the host"
grep -aq 'FEHLER' "$T/inputtest.txt" 2>/dev/null && bad "inputtest reports FEHLER: $(grep -a FEHLER "$T/inputtest.txt" | head -1)" || ok "inputtest reports no FEHLER"
echo "== $pass ok, $fail fail"
if [ -n "${KEEP:-}" ]; then
    mkdir -p "${KEEP_DIR:-/tmp/xremote-keep}"; cp -r "$OUT" "$T/viewer.txt" "$T/inputtest.txt" "$T/relay.log" "${KEEP_DIR:-/tmp/xremote-keep}/" 2>/dev/null
fi
[ "$fail" -eq 0 ]
