#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/hotnote/run.sh -- hotplug and crash notifications read like sentences, not like bus codes.
#
#   bash tools/hotnote/run.sh
#
# 1. USB keyboard plugged in at run time (QEMU monitor device_add): the toast says
#    "Keyboard or mouse connected", and "... disconnected" after device_del.
# 2. `notify "usb+ /medien/usb0"` (what the kernel posts for a stick) reads "USB drive connected (usb0)".
# 3. A program that dies on a null write (/bin/segv): toast "segv stopped unexpectedly".
# 4. The notification centre lists the same sentences, not the codes.
# COUNTER-PROOF: no raw "ev+ " / "usb+ " / "crash " text reaches a toast line.
set -uo pipefail
cd "$(dirname "$0")/../.."
TMPD=$(mktemp -d)
trap 'rm -rf "$TMPD"' EXIT
export DESIGNBUILD="$TMPD/build"
pass=0; fail=0
ok()  { pass=$((pass+1)); printf '  OK    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }

PROGS="desktop taskbar settings launcher explorer netview taskmgr edit sh echo ls cat ps uname date df mkdir rm cp mv grep head tail wc find du chmod id whoami touch true false sleep kill sort uniq notify segv"
cat > "$TMPD/dreh.txt" <<'DEOF'
warteauf 'taskbar: steht|taskbar: geom' || 120
warte 6
klick 300,200
warte 2
taste ret
warte 1
monitor device_add usb-kbd,id=hk1
warte 6
foto 01-plug
monitor device_del hk1
warte 6
tippe notify usb+ /medien/usb0
taste ret
warte 5
tippe notify ev+ jack
taste ret
warte 5
tippe notify usb+ /medien/usb0 14900
taste ret
warte 5
tippe notify ev+ input 046d:c077
taste ret
warte 5
tippe notify ev+ screen
taste ret
warte 5
tippe notify ev+ screen
taste ret
warte 5
tippe segv
taste ret
warte 8
foto 02-crash
klickauf glocke
warte 4
foto 03-bell
klickauf ncrow0
warte 6
foto 04-act
DEOF
bash tools/design/eh6.sh "$TMPD/o" res=1280x800 accel=kvm progs="$PROGS" \
    drehbuch="$TMPD/dreh.txt" > "$TMPD/o.log" 2>&1
S="$TMPD/o/serial.txt"
if [ -n "${HOTNOTE_OUT:-}" ]; then mkdir -p "$HOTNOTE_OUT"; cp "$TMPD"/o/*.ppm "$S" "$HOTNOTE_OUT/" 2>/dev/null; fi
if [ ! -s "$S" ]; then bad "no serial output: $(tail -n 3 "$TMPD/o.log" | tr '\n' ' ')"; echo "HOTNOTE: $pass passed, $fail failed"; exit 1; fi
t() { grep -aq "taskbar: toast \[$1\]" "$S"; }
t 'QEMU keyboard connected' && ok "keyboard plug-in toast names the device" || bad "no 'QEMU keyboard connected' toast"
t 'QEMU keyboard disconnected' && ok "keyboard unplug toast names the device" || bad "no 'QEMU keyboard disconnected' toast"
t 'USB drive connected (usb0)' && ok "stick toast with drive name" || bad "no 'USB drive connected (usb0)' toast"
t 'Headphones or microphone plugged in' && ok "jack toast" || bad "no jack toast"
t 'Display connected' && ok "display toast" || bad "no display toast"
t 'USB drive connected (usb0, 14.5 GB)' && ok "stick toast with drive name and size" || bad "no stick size toast"
t 'Logitech keyboard or mouse connected' && ok "vendor name plus kind" || bad "no vendor toast"
grep -aq 'notifc: row [0-9]* prio=1 text=Display connected (x2)' "$S" && ok "bell groups equal neighbours" || bad "bell did not group"
grep -aq 'notifc: act row=0 path=/var/crash' "$S" && ok "clicking the crash row opens the report folder" || bad "row click did not act"
grep -aq 'taskbar: toast \[segv stopped unexpectedly\]' "$S" && ok "crash toast names the program" || bad "no crash toast"
if grep -aq 'taskbar: toast \[\(ev[+-] \|usb[+-^] \|crash \)' "$S"; then
    bad "raw bus code reached a toast: $(grep -a 'taskbar: toast \[\(ev[+-] \|usb[+-^] \|crash \)' "$S" | head -1)"
else
    ok "no raw bus code in any toast"
fi
echo; echo "HOTNOTE: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
