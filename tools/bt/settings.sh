#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
HERE="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$HERE"
export FIRNLIB="$HERE/lib"
command -v qemu-system-x86_64 >/dev/null || { echo "BTSETTINGS: skipped, no qemu"; exit 0; }
T=$(mktemp -d)
pass=0; fail=0
ok()  { pass=$((pass+1)); printf '  OK    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }
cleanup() { for f in "$T"/*.pid; do [ -f "$f" ] && kill "$(cat "$f")" 2>/dev/null; done; rm -rf "$T"; }
trap cleanup EXIT
bash vendor/firn/fetch-firnc.sh >/dev/null 2>&1
export DESIGNBUILD="$T/build"
export AUDIT_TIMEOUT=${AUDIT_TIMEOUT:-600}
SCRIPT_COMMON=$'warte 12\nklick 24,780\nwarte 3\nklickauf start_Settings\nwarte 12\nklicksuche srecttab31 140,300\nwarte 4\nfoto bt-page\n'
printf '%s' "$SCRIPT_COMMON" > "$T/none.txt"
printf '%s' "$SCRIPT_COMMON" > "$T/full.txt"
cat >> "$T/full.txt" <<'EOF'
klickauf srectbtscan
warte 8
foto bt-scan1
klickauf srectbtscan
warte 8
foto bt-scan2
klickauf srectbtpwr
warte 4
foto bt-off
klickauf srectbtpwr
warte 4
foto bt-on
EOF

run_audit() {
    local lang_arg=${4:-}
    local n=$1 script=$2 extra=$3
    mkdir -p "$T/$n"
    AUDIT_PROC=1 AUDIT_QEMU_EXTRA="$extra" bash tools/design/audit.sh "$T/$n" accel=kvm fs=an uitrace=yes halt=${BT_HALT:-300} $lang_arg extra="usb usbpoll" drehbuch="$script" > "$T/$n.log" 2>&1
    tr -cd '\11\12\15\40-\176' < "$T/$n/serial.txt" > "$T/$n.klar"
}
chk() { grep -aq -- "$3" "$T/$1.klar" && ok "$1: $2" || bad "$1: $2 (missing: $3)"; }
nochk() { grep -aq -- "$3" "$T/$1.klar" && bad "$1: $2 (found: $3)" || ok "$1: $2"; }
count() { grep -ac -- "$2" "$1" 2>/dev/null; true; }

start_gadget() {
    rm -f "$T/g.sock" "$T/g.gadget" "$T/g.unplug"
    : > "$T/g.trig"
    ( while [ ! -S "$T/g.sock" ]; do sleep 0.2; done
      exec python3 -I tools/usbredir/usbdev.py --sock "$T/g.sock" --profile btdongle --trigger "$T/g.trig" --unplug "$T/g.unplug" \
        --log "$T/g.gadget" --max-secs 300 --bt normal ) &
    echo $! > "$T/g.pid"
}
stop_gadget() { kill "$(cat "$T/g.pid")" 2>/dev/null; }
XDEV="-device qemu-xhci,id=x0 -chardev socket,id=r0,path=$T/g.sock,server=on,wait=off -device usb-redir,chardev=r0"
want() { case " ${CASES:-full none de} " in *" $1 "*) return 0;; esac; return 1; }
CASES="$*"
if want full; then
start_gadget
run_audit full "$T/full.txt" "$XDEV"
stop_gadget
chk full "page opened" 'settings: bluetooth'
chk full "adapter bound" 'driver=btusb'
HINT=$(grep -an 't=Plug in a USB Bluetooth adapter' "$T/full.klar" | tail -n 1 | cut -d: -f1)
READY=$(grep -an 't=Ready' "$T/full.klar" | tail -n 1 | cut -d: -f1)
[ -z "$HINT" ] || [ "${READY:-0}" -gt "$HINT" ] && ok "full: no adapter hint after the adapter is ready" || bad "full: adapter hint still shown last"
chk full "power switch rect" 'settings: rect name=btpwr'
chk full "search button rect" 'settings: rect name=btscan'
chk full "status ready" 't=Ready'
SCANS=$(count "$T/g.gadget" 'command 0401')
[ "$SCANS" = 2 ] && ok "full: inquiry command sent once per search click ($SCANS)" || bad "full: expected 2 inquiry commands, got $SCANS"
chk full "device list shows extended name" 't=.*Test Laptop'
chk full "found counter" 'Devices found: 3'
chk full "power off text" 't=Bluetooth is off'
chk full "power back on" 'bt: inquiry done n=3'
grep -aq 'bt violations=0' "$T/g.gadget" && ok "full: model saw no malformed command" || bad "full: model violations"
grep -aiq 'panic\|exception\|#PF\|#GP\|#UD' "$T/full.klar" && bad "full: panic/exception in log" || ok "full: no panic/exception"

fi
if want none; then
run_audit none "$T/none.txt" ""
chk none "no adapter hint" 't=Plug in a USB Bluetooth adapter'
nochk none "no search button without adapter" 'settings: rect name=btscan'
nochk none "no power switch without adapter" 'settings: rect name=btpwr'
grep -aiq 'panic\|exception\|#PF\|#GP\|#UD' "$T/none.klar" && bad "none: panic/exception in log" || ok "none: no panic/exception"

fi
if want de; then
printf '%s' "$SCRIPT_COMMON" > "$T/de.txt"
printf 'klickauf srectbtscan\nwarte 8\nfoto bt-de\n' >> "$T/de.txt"
start_gadget
run_audit de "$T/de.txt" "$XDEV" lang=de
stop_gadget
chk de "German note with umlauts" 't=Kopfh'
UM=(
  "Kopfhörer, Mäuse, Tastaturen und andere Funkgeräte verbinden."
  "Nach Geräten suchen"
)
for u in "${UM[@]}"; do
    out=$(python3 -I tools/look/umlaut.py "$T/de/serial.txt" "$T/de/bt-de.ppm" Einstellungen "$u" --ink 2>&1 | tail -n 1)
    echo "$out" | grep -q '0 falsch\|rc=0\|: 0 ' && ok "de: ink '$u'" || bad "de: ink '$u' ($out)"
done
fi

printf '\nBTSETTINGS: %d ok, %d fail\n' "$pass" "$fail"
if [ -n "${BTSETTINGS_KEEP:-}" ]; then
    mkdir -p "$BTSETTINGS_KEEP"
    cp "$T"/*.klar "$T"/*.log "$T"/g.gadget "$BTSETTINGS_KEEP"/ 2>/dev/null
    for d in full none de; do [ -d "$T/$d" ] && cp "$T/$d"/*.ppm "$BTSETTINGS_KEEP"/ 2>/dev/null && cp "$T/$d/serial.txt" "$BTSETTINGS_KEEP/$d.serial" 2>/dev/null; done
fi
[ "$fail" = 0 ]
