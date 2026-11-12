#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/xremote/service.sh -- gate for /bin/xremoted, the supervisor of the FreeViewer host (package xremote), in the Osum guest.
#
#   /root/jarvis/bin/heavy bash tools/xremote/service.sh
#
# Env: XR_WD (linuxapps workdir, default /root/fxhp), XR_HOST (v2 musl host with --password-file etc.), XR_VIEWER (glibc viewer),
#      XR_RELAY / XR_LIBS (relay dir / node_modules parent), XR_LIBGCC, KERNEL (prebuilt kernel), KEEP=1 keeps the output dir.
# Phases in the guest: A disabled (no host, no password) -> B enabled (host up, password, ID) -> viewer with a wrong password
#   is refused, viewer with the right password gets frames -> C disable kills the host (viewer gets nothing) -> D enabled but
#   package missing (no host) -> E package back (host again, NEW password, old one refused) -> F disabled again.
set -uo pipefail
cd "$(dirname "$0")/../.."
WD=${XR_WD:-/root/fxhp}
XRTOOLS=${XR_TOOLS:-/root/jarvis/data/orientos-xremote}
HOSTBIN=${XR_HOST:-$XRTOOLS/v2/freeviewer-host}
VIEWER=${XR_VIEWER:-$XRTOOLS/freeviewer-glibc}
RELAYDIR=${XR_RELAY:-/root/projects/freeviewer/relay}
NODEPATH=${XR_LIBS:-/root/jarvis/node_modules}
LIBGCC=${XR_LIBGCC:-$WD/fx-root/usr/lib/libgcc_s.so.1}
LDMUSL=${XR_LDMUSL:-$WD/fx-root/lib/ld-musl-x86_64.so.1}
HOSTSECS=${XR_HOSTSECS:-240}
WINDOW=${XR_WINDOW:-130}
WINDOW2=${XR_WINDOW2:-90}
AFTERSECS=${XR_AFTER:-45}
RELAYPORT=$((17000 + $$ % 1000))
pass=0; fail=0
ok()  { pass=$((pass+1)); printf '  OK    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }
chk() { if [ "$1" = 1 ]; then ok "$2"; else bad "$2"; fi; }
for f in "$HOSTBIN" "$VIEWER" "$RELAYDIR/relay.js" "$WD/fxrun/spec.txt" "$LIBGCC" "$LDMUSL"; do
    [ -e "$f" ] || { echo "XRSERVICE: missing $f"; exit 1; }
done
for t in qemu-system-x86_64 node python3; do
    command -v "$t" >/dev/null 2>&1 || { echo "XRSERVICE: skipped, $t missing"; exit 0; }
done
T=$(mktemp -d)
RP=""; VP=""; DP=""
cleanup() {
    [ -n "$DP" ] && kill "$DP" 2>/dev/null
    [ -n "$RP" ] && kill "$RP" 2>/dev/null
    [ -n "$VP" ] && kill "$VP" 2>/dev/null
    rm -rf "$T"
}
trap cleanup EXIT
OUT=${XR_OUT:-$T/out}
mkdir -p "$OUT" "$T/relay" "$T/home" "$T/fx"
sed -e "s/@RELAYPORT@/$RELAYPORT/g" -e "s/@HOSTSECS@/$HOSTSECS/g" -e "s/@WINDOW@/$WINDOW/g" -e "s/@WINDOW2@/$WINDOW2/g" -e "s/@AFTERSECS@/$AFTERSECS/g" -e "s/@REALRELAY@/${XR_REAL_RELAY:-0}/g" tools/xremote/service-guest.sh > "$T/svc.sh"
[ "${XR_DBG:-0}" = 1 ] && sed -i 's/^#DBG //' "$T/svc.sh"
cp tools/xremote/service-guest-boot.sh "$T/fx.sh"
grep -E '/@755$|^/(bin|sbin)/|^/usr/(bin|sbin)/[a-z0-9_.-]*->/bin/busybox|^/lib/(ld-musl|libc\.musl)' "$WD/fxrun/spec.txt" > "$T/fx/spec.txt"
OPKPY=${OPK:-$(python3 tools/lib/opkpfad.py)}
PKGSRC="$T/pkgsrc"; PKGROOT="$T/pkgroot"
mkdir -p "$PKGSRC/bau" "$PKGROOT"
cp pakete/xremote/INFO pakete/xremote/rezept "$PKGSRC/"
cp "$HOSTBIN" "$PKGSRC/bau/freeviewer-host"
cp "$LDMUSL" "$PKGSRC/bau/ld-musl-x86_64.so.1"
cp "$LIBGCC" "$PKGSRC/bau/libgcc_s.so.1"
python3 tools/k15/icon.py pakete/xremote/symbol.txt "$PKGSRC/bau/symbol" > /dev/null
(cd "$PKGSRC" && python3 "$OPKPY" bauen rezept -o "$T/xremote.opk") > "$T/opkbuild.log" 2>&1 || { echo "XRSERVICE: opk build failed"; cat "$T/opkbuild.log"; exit 1; }
python3 "$OPKPY" installieren --wurzel "$PKGROOT" "$T/xremote.opk" > "$T/opkinstall.log" 2>&1 || { echo "XRSERVICE: opk install failed"; cat "$T/opkinstall.log"; exit 1; }
APPDIR="$PKGROOT/apps/xremote.osp"
cp "$APPDIR/INFO" "$T/xr.info"
printf '1\n' > "$T/xr.current"
printf 'xremote\t%s\n' "$(printf 'a%.0s' $(seq 1 32))" > "$T/xr.plan"
[ "${XR_NO_PLAN:-0}" = 1 ] && : > "$T/xr.plan"
{
    echo "/apps/@755"; echo "/apps/xremote.osp/@755"
    (cd "$APPDIR" && find . -mindepth 1 -type d | sort) | while read -r d; do echo "/apps/xremote.osp/${d#./}/@755"; done
    (cd "$APPDIR" && find . -type f | sort) | while read -r f; do echo "/apps/xremote.osp/${f#./}=$APPDIR/${f#./}@644"; done
    echo "/system/@755"; echo "/system/generations/@755"; echo "/system/generations/1/@755"
    echo "/system/CURRENT=$T/xr.current@644"; echo "/system/generations/1/PLAN=$T/xr.plan@644"
    [ "${XR_REAL_RELAY:-0}" = 1 ] && echo "/etc/resolv.conf=$WD/fx-root/etc/resolv.conf@644"
    [ "${XR_DBG:-0}" = 1 ] && { echo "/opt/@755"; echo "/opt/xr/@755"; echo "/opt/xr/freeviewer-old=$XRTOOLS/freeviewer-host@755"; echo "/usr/@755"; echo "/usr/lib/@755"; echo "/usr/lib/libgcc_s.so.1=$LIBGCC@755"; }
    echo "/run/@755"; echo "/var/@755"; echo "/var/log/@755"; echo "/etc/@755"
} | awk '!seen[$0]++' >> "$T/fx/spec.txt"
awk '!seen[$0]++' "$T/fx/spec.txt" > "$T/fx/spec.dedup"
mkdir -p "$T/wd/fxrun"; cp "$T/fx/spec.dedup" "$T/wd/fxrun/spec.txt"
cp "$RELAYDIR"/*.js "$T/relay/"
(cd "$T/relay" && NODE_PATH="$NODEPATH" FV_PORT=$RELAYPORT FV_DATA="$T/relay/hosts.json" FV_BUCH=0 exec node relay.js > "$T/relay.log" 2>&1) &
RP=$!
sleep 2
kill -0 "$RP" 2>/dev/null && ok "relay up on port $RELAYPORT" || bad "relay did not start"
S="$OUT/ser.txt"
wait_marker() {
    local pat=$1 max=$2 i=0
    while [ $i -lt "$max" ]; do
        grep -aq -- "$pat" "$S" 2>/dev/null && return 0
        sleep 1; i=$((i + 1))
    done
    return 1
}
viewer() {
    local out=$1; shift
    HOME="$T/home" FV_RELAY="ws://127.0.0.1:$RELAYPORT/fv/ws" FV_ALLOW_INSECURE_RELAY=1 FV_NOP2P=1 timeout "$1" "$VIEWER" --connect "$2" "$3" "$4" > "$out" 2>&1
}
(
    wait_marker '^SV-PW [A-Z0-9]' $((HOSTSECS + 300)) || exit 0
    ID=$(grep -a '^SV-ID ' "$S" | head -1 | cut -d' ' -f2)
    PW=$(grep -a '^SV-PW ' "$S" | head -1 | cut -d' ' -f2)
    sleep 3
    viewer "$T/v_bad.txt" 40 "$ID" WRONGPW1 3
    viewer "$T/v_ok.txt" 50 "$ID" "$PW" 5
    wait_marker '^SV-DISABLED-DONE' 200 || exit 0
    viewer "$T/v_after.txt" 35 "$ID" "$PW" 3
    wait_marker '^SV-PW2 [A-Z0-9]' 300 || exit 0
    ID2=$(grep -a '^SV-ID2 ' "$S" | head -1 | cut -d' ' -f2)
    PW2=$(grep -a '^SV-PW2 ' "$S" | head -1 | cut -d' ' -f2)
    sleep 3
    viewer "$T/v_old.txt" 30 "$ID2" "$PW" 3
    viewer "$T/v_ok2.txt" 45 "$ID2" "$PW2" 5
) &
VP=$!
MONSOCK="$T/mon.sock"
(
    answered=0
    while true; do
        dialogs=$(grep -ac 'wm: trusted dialog up no=' "$S" 2>/dev/null)
        if [ "${dialogs:-0}" -gt "$answered" ]; then
            sleep 2
            printf 'sendkey j\n' > "$T/dialog-key.txt"
            python3 tools/wm/monitor.py "$MONSOCK" "$T/dialog-key.txt" 0.15 > /dev/null 2>&1
            answered=$((answered + 1))
        fi
        sleep 1
    done
) &
DP=$!
ACC=(); [ -w /dev/kvm ] && ACC=(-accel kvm -cpu host)
BOOTARGS="gfx disp wm wmdauer wmshell osum vfs bus fremdtrace nic nip=10.0.2.15/24 ngw=10.0.2.2 script=sh /etc/fx.sh;exit"
KERNEL=${KERNEL:-} DONE=SV-END TMO=${XR_TMO:-900} MEM=1024 GUI=1 GUI_EXTRA="xremoted settingsd apprights orientbus act" \
    EXTRA="/etc/svc.sh=$T/svc.sh@755 /etc/settings.schema=etc/settings.schema@644 /etc/actions.d/@755 /etc/actions.d/settings.actions=etc/actions.d/settings.actions@644" KARGS="$BOOTARGS" \
    QEMU_EXTRA="-monitor unix:$MONSOCK,server,nowait -vga std -netdev user,id=n0 -device virtio-net-pci,netdev=n0,mac=52:54:00:5b:1d:02" \
    SPEC="$T/wd/fxrun/spec.txt" bash tools/linuxapps/run.sh "$WD" "$T/fx.sh" "$OUT" > "$T/linuxapps.log" 2>&1
wait "$VP" 2>/dev/null; VP=""
kill "$DP" 2>/dev/null; DP=""
C="$OUT/ser.clean"
tail -n 3 "$T/linuxapps.log" | sed 's/^/        /'
line() { grep -a "^$1" "$C" | head -1; }
has() { echo "$1" | grep -q -- "$2" && echo 1 || echo 0; }
L=$(line 'SV-PKG');    chk "$(has "$L" 'host=1 ld=1 gcc=1')" "package files are in the guest ($L)"
L=$(line 'SV-BEFORE'); chk "$(has "$L" 'conf=0 pw=0')" "control: no config, password, info or log before the service ran ($L)"
L=$(line 'SV-RIGHTS')
if [ "${XR_NO_PLAN:-0}" = 1 ]; then
    chk "$(has "$L" 'mask=0 ')" "counter-proof: no signed plan, no automatic grant, mask stays 0 ($L)"
else
    chk "$(has "$L" 'mask=[0-9]* net')" "perm=net of the installed INFO is granted at load, no /etc/apprights.conf written by hand ($L)"
fi
L=$(line 'SV-BUS-GET0'); chk "$(has "$L" 'enabled=.*value=false')" "bus: remote.enabled reads false before the first switch-on ($L)"
L=$(line 'SV-BUS-SET true'); chk "$(has "$L" 'confirm [0-9]* settings.remote.enabled')" "bus: settings.set remote.enabled is critical and asks for a confirmation ($L)"
L=$(line 'SV-BUS-CONFIRM true'); chk "$(has "$L" 'use_dialog')" "bus: the window's own confirm is refused, only the system dialog says yes ($L)"
NK=$(grep -c '^setting ' etc/settings.schema)
grep -aq "settingsd: schema ok keys=$NK" "$C" && ok "settingsd loads the shipped schema with the remote.* keys (keys=$NK)" || bad "settingsd schema check: $(grep -a 'settingsd:' "$C" | head -1)"
grep -aq 'xremoted: started' "$C" && ok "xremoted started in the guest" || bad "xremoted did not start"
L=$(line 'SV-A ')
chk "$(has "$L" 'service=disabled password= pw=0 state=0 log=0')" "phase A: disabled -> status disabled, no password, no host state, no host log ($L)"
L=$(line 'SV-B ')
chk "$(has "$L" 'service=running pwlen=8 samepw=1')" "phase B: enabled -> running, 8-char password, info equals password file ($L)"
ID=$(grep -a '^SV-ID ' "$C" | head -1 | cut -d' ' -f2)
PW=$(grep -a '^SV-PW ' "$C" | head -1 | cut -d' ' -f2)
L=$(line 'SV-BUS-GET1'); chk "$(has "$L" "value=$ID")" "bus: settings.get remote.id returns the ID of the state file ($L)"
L=$(line 'SV-BUS-GET2'); chk "$(has "$L" "value=$PW")" "bus: settings.get remote.password returns the password ($L)"
L=$(line 'SV-BUS-GET3'); chk "$(has "$L" 'value=')" "bus: settings.get remote.status answers ($L)"
L=$(line 'SV-BUS-GET4'); chk "$(has "$L" 'value=true.*enabled=true')" "bus: remote.enabled reads true and /etc/xremote.conf says enabled=true ($L)"
echo "$ID" | grep -qE '^[0-9]+$' && ok "host registered at the relay, ID $ID, state file readable by the guest" || bad "no host ID in the state file: '$ID'"
echo "$PW" | grep -qE '^[A-Z2-9]{8}$' && ok "password has 8 characters from the unambiguous alphabet" || bad "password format: '$PW'"
FB=$(grep -ac '^frame ' "$T/v_bad.txt" 2>/dev/null)
[ "${FB:-0}" = 0 ] && ok "wrong password: viewer receives no frame" || bad "wrong password: viewer received $FB frames"
grep -aq 'Passwort falsch' "$T/v_bad.txt" && ok "wrong password: viewer is told the password is wrong" || bad "wrong password: viewer got no refusal: $(head -c 120 "$T/v_bad.txt")"
FO=$(grep -ac '^frame ' "$T/v_ok.txt" 2>/dev/null)
[ "${FO:-0}" -ge 2 ] && ok "right password: viewer received $FO frames" || bad "right password: viewer received ${FO:-0} frames ($(tail -n 2 "$T/v_ok.txt" 2>/dev/null | tr '\n' ';'))"
L=$(line 'SV-C ')
chk "$(has "$L" 'service=disabled password= pw=0 state=0')" "phase C: disable -> status disabled, password and host state removed ($L)"
L=$(line 'SV-BUS-SET false'); chk "$(has "$L" 'confirm [0-9]* settings.remote.enabled')" "bus: switching off asks as well ($L)"
L=$(line 'SV-BUS-GET5'); chk "$(has "$L" 'value=false.*enabled=false')" "bus: after the confirmed switch-off remote.enabled reads false and the conf says enabled=false ($L)"
FA=$(grep -ac '^frame ' "$T/v_after.txt" 2>/dev/null)
[ "${FA:-0}" = 0 ] && [ -e "$T/v_after.txt" ] && ok "after disable the old ID and password give no frame (host is gone)" || bad "after disable a viewer still got $FA frames"
N=$(grep -ac 'xremoted: host stopped' "$C")
[ "$N" -ge 2 ] && ok "xremoted logged $N host stops (disable and final disable)" || bad "xremoted logged $N host stops, want 2"
L=$(line 'SV-D ')
chk "$(has "$L" 'service=package-missing password= pw=0 state=0')" "phase D: enabled but package missing -> package-missing, no password, no host ($L)"
L=$(line 'SV-E ')
chk "$(has "$L" 'service=running pwlen=8 newpw=1')" "phase E: package back -> running with a NEW password ($L)"
chk "$(has "$L" 'sameid=1')" "the computer keeps its ID across the restart ($L)"
FOLD=$(grep -ac '^frame ' "$T/v_old.txt" 2>/dev/null)
[ "${FOLD:-0}" = 0 ] && [ -e "$T/v_old.txt" ] && ok "the old password is refused by the restarted host" || bad "old password got $FOLD frames"
FO2=$(grep -ac '^frame ' "$T/v_ok2.txt" 2>/dev/null)
[ "${FO2:-0}" -ge 2 ] && ok "new password: viewer received $FO2 frames" || bad "new password: viewer received ${FO2:-0} frames"
N=$(grep -ac 'xremoted: host started' "$C")
[ "$N" -ge 2 ] && ok "xremoted logged $N host starts (B and E)" || bad "xremoted logged $N host starts, want 2"
if [ "${XR_REAL_RELAY:-0}" = 1 ]; then
    L=$(line 'SV-G ')
    chk "$(has "$L" 'service=running id=[0-9]')" "phase G: default relay wss://freeviewer.fleitec.com/fv/ws registers a 9-digit ID from inside the guest ($L)"
fi
L=$(line 'SV-F ')
chk "$(has "$L" 'service=disabled pw=0 state=0')" "phase F: disabled again -> host gone, files removed ($L)"
AFTER=$(awk '/^SV-PKG/{f=1} f' "$C")
echo "$AFTER" | grep -aqE 'user fault|xremoted: host start failed' && bad "fault or start failure: $(echo "$AFTER" | grep -aE 'user fault|xremoted: host start failed' | head -1)" || ok "no user fault, no host start failure"
echo "== $pass ok, $fail fail"
if [ -n "${KEEP:-}" ]; then
    mkdir -p "${KEEP_DIR:-/tmp/xrservice-keep}"
    cp -r "$OUT" "$T"/v_*.txt "$T/relay.log" "${KEEP_DIR:-/tmp/xrservice-keep}/" 2>/dev/null
fi
[ "$fail" -eq 0 ]
