#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/xremote/fps.sh -- gate for the picture rate and the change-to-picture delay of the X-Remote host.
#
#   /root/jarvis/bin/heavy bash tools/xremote/fps.sh
#
# Env: XR_WD, XR_HOST, XR_RELAY, XR_LIBS, XR_LIBGCC (as in run.sh), XR_PERF_VIEWER (viewer with --perftest),
#      KERNEL (prebuilt kernel image; the counter-probe is a kernel built from the commit before the grab fix),
#      XR_MIN_FPS (15), XR_MAX_LATENCY_MS (300), XR_MAX_GRAB_MS (80, per 1920x1080 frame), KEEP=1 keeps the output dir.
# Proves: with the desktop running, the viewer receives >= XR_MIN_FPS frames/s while the pointer sweeps the screen, a pointer
#         move on a still screen shows up in the viewer within XR_MAX_LATENCY_MS, and one full-screen kernel grab
#         (osum_shot, what the host does per frame) stays within XR_MAX_GRAB_MS scaled to 1920x1080.
set -uo pipefail
cd "$(dirname "$0")/../.."
WD=${XR_WD:-/root/fxhp}
XRTOOLS=${XR_TOOLS:-/root/jarvis/data/orientos-xremote}
HOSTBIN=${XR_HOST:-$XRTOOLS/freeviewer-host}
VIEWER=${XR_PERF_VIEWER:-$XRTOOLS/freeviewer-perf}
RELAYDIR=${XR_RELAY:-/root/projects/freeviewer/relay}
NODEPATH=${XR_LIBS:-/root/jarvis/node_modules}
LIBGCC=${XR_LIBGCC:-$WD/fx-root/usr/lib/libgcc_s.so.1}
MIN_FPS=${XR_MIN_FPS:-15}
MAX_LATENCY_MS=${XR_MAX_LATENCY_MS:-300}
MAX_GRAB_MS=${XR_MAX_GRAB_MS:-80}
HOSTSECS=${XR_HOSTSECS:-240}
TAILSECS=${XR_TAIL:-75}
RELAYPORT=$((18000 + $$ % 1000))
FULLHD_PIXELS=2073600
pass=0; fail=0
ok()  { pass=$((pass+1)); printf '  OK    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }
for f in "$HOSTBIN" "$VIEWER" "$RELAYDIR/relay.js" "$WD/fxrun/spec.txt" "$LIBGCC"; do
    [ -e "$f" ] || { echo "XRFPS: missing $f"; exit 1; }
done
for t in qemu-system-x86_64 node musl-gcc python3; do
    command -v "$t" >/dev/null 2>&1 || { echo "XRFPS: skipped, $t missing"; exit 0; }
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
mkdir -p "$OUT" "$T/relay" "$T/home" "$T/fx" "$T/wd/fxrun"
musl-gcc -O2 -fPIE -pie -o "$T/xrprobe" tools/xremote/probe.c || { echo "XRFPS: probe build failed"; exit 1; }
sed -e "s/@RELAYPORT@/$RELAYPORT/g" -e "s/@HOSTSECS@/$HOSTSECS/g" -e "s/@TAILSECS@/$TAILSECS/g" tools/xremote/guest-fps.sh > "$T/xr3.sh"
cp tools/xremote/guest-desktop.sh "$T/guest.sh"
grep -E '/@755$|^/(bin|sbin)/|^/usr/(bin|sbin)/[a-z0-9_.-]*->/bin/busybox|^/lib/(ld-musl|libc\.musl)' "$WD/fxrun/spec.txt" > "$T/fx/spec.txt"
{
    echo "/opt/@755"; echo "/opt/xr/@755"; echo "/usr/@755"; echo "/usr/lib/@755"
    echo "/usr/lib/libgcc_s.so.1=$LIBGCC@755"
    echo "/opt/xr/freeviewer-host=$HOSTBIN@755"
    echo "/opt/xr/xrprobe=$T/xrprobe@755"
} | awk '!seen[$0]++' >> "$T/fx/spec.txt"
cp "$T/fx/spec.txt" "$T/wd/fxrun/spec.txt"
cp "$RELAYDIR"/*.js "$T/relay/"
(cd "$T/relay" && NODE_PATH="$NODEPATH" FV_PORT=$RELAYPORT FV_DATA="$T/relay/hosts.json" FV_BUCH=0 exec node relay.js > "$T/relay.log" 2>&1) &
RP=$!
sleep 2
kill -0 "$RP" 2>/dev/null && ok "relay up on port $RELAYPORT" || bad "relay did not start"
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
    timeout 120 "$VIEWER" --perftest "$ID" xrpass > "$T/perf.txt" 2>&1
) &
VP=$!
BOOTARGS="gfx disp wm wmdauer wmshell osum vfs bus fremdtrace nic nip=10.0.2.15/24 ngw=10.0.2.2 script=sh /etc/fx.sh;exit"
env GUI=1 "EXTRA=/etc/xr3.sh=$T/xr3.sh@755" KERNEL=${KERNEL:-} DONE=XR-END TMO=${XR_TMO:-900} MEM=1024 \
    KARGS="$BOOTARGS" \
    QEMU_EXTRA="-vga std -netdev user,id=n0 -device virtio-net-pci,netdev=n0,mac=52:54:00:5b:1d:01" \
    SPEC="$T/wd/fxrun/spec.txt" bash tools/linuxapps/run.sh "$WD" "$T/guest.sh" "$OUT" > "$T/linuxapps.log" 2>&1
wait "$VP" 2>/dev/null; VP=""
S="$OUT/ser.clean"
tail -n 3 "$T/linuxapps.log" | sed 's/^/        /'
[ -s "$T/hostid" ] && ok "host registered at the relay (ID $(cat "$T/hostid"))" || bad "host never printed an ID"

GB=$(grep -a '^XR-GRABBENCH' "$S" | head -1)
GW=$(echo "$GB" | grep -o 'width=[0-9]*' | cut -d= -f2); GH=$(echo "$GB" | grep -o 'height=[0-9]*' | cut -d= -f2)
GUS=$(echo "$GB" | grep -o 'mean_us=[0-9]*' | cut -d= -f2)
if [ -n "$GUS" ] && [ -n "$GW" ] && [ -n "$GH" ]; then
    GMS=$((GUS * FULLHD_PIXELS / (GW * GH) / 1000))
    echo "        grab ${GW}x${GH}: ${GUS} us per frame = ${GMS} ms per 1920x1080 frame"
    [ "$GMS" -le "$MAX_GRAB_MS" ] && ok "full-screen grab $GMS ms per 1920x1080 frame <= $MAX_GRAB_MS" || bad "full-screen grab $GMS ms per 1920x1080 frame > $MAX_GRAB_MS"
else
    bad "grab benchmark missing: $GB"
fi

FPSLINE=$(grep -a '^PERF fps=' "$T/perf.txt" 2>/dev/null | head -1)
FPS=$(echo "$FPSLINE" | grep -o 'fps=[0-9.]*' | cut -d= -f2)
echo "        $FPSLINE"
[ -n "$FPS" ] && awk -v f="$FPS" -v m="$MIN_FPS" 'BEGIN{exit !(f>=m)}' && ok "viewer receives $FPS frames/s while the pointer sweeps (>= $MIN_FPS)" || bad "viewer frame rate ${FPS:-none} < $MIN_FPS"

LATLINE=$(grep -a '^PERF latency median_ms=' "$T/perf.txt" 2>/dev/null | head -1)
LAT=$(echo "$LATLINE" | grep -o 'median_ms=[0-9]*' | cut -d= -f2)
ANS=$(echo "$LATLINE" | grep -o 'answered=[0-9]*' | cut -d= -f2)
echo "        $LATLINE"
[ -n "$LAT" ] && [ "$LAT" -le "$MAX_LATENCY_MS" ] && ok "pointer move visible in the viewer after ${LAT} ms median (<= $MAX_LATENCY_MS)" || bad "change-to-picture median ${LAT:-none} ms > $MAX_LATENCY_MS"
[ "${ANS:-0}" -ge 10 ] && ok "viewer saw a new frame after $ANS of 12 moves" || bad "viewer answered only ${ANS:-0} of 12 moves"
grep -aq 'Aufnahme: osum [0-9]*x[0-9]*' "$S" && ok "host captures the osum screen" || bad "host log has no osum capture line"

echo "== $pass ok, $fail fail"
if [ -n "${KEEP:-}" ]; then
    mkdir -p "${KEEP_DIR:-/tmp/xremote-fps-keep}"; cp -r "$OUT" "$T/perf.txt" "$T/relay.log" "${KEEP_DIR:-/tmp/xremote-fps-keep}/" 2>/dev/null
fi
[ "$fail" -eq 0 ]
