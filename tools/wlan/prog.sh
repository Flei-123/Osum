#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/wlan/prog.sh -- /bin/wlan WIRKLICH LAUFEN LASSEN.
#
# `status`, `chips` und `verbinden`.
#
set -uo pipefail
cd "$(dirname "$0")/../.."
ROOT=$(pwd)
export FIRNLIB="$ROOT/lib"
. tools/lib/firnenv.sh
W=${1:-/tmp/wlanprog-w}
mkdir -p "$W"

pass=0
fail=0
ok()  { pass=$((pass+1)); printf '  OK    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }

# 1. Uebersetzt es ueberhaupt?
if $FIRNC kernel/user/wlan.fi -o "$W/wlan" > "$W/bau.txt" 2>&1; then
    ok "kernel/user/wlan.fi uebersetzt (und bindet lib/wlan/usbchip.fi)"
else
    bad "kernel/user/wlan.fi uebersetzt nicht"
    head -20 "$W/bau.txt"
    echo "WLANPROG: $pass Zusagen, $fail Fehler"
    exit 1
fi

for f in tools/loader/build.sh tools/install/build.sh; do
    if grep -q '\bwlan\b' "$f"; then
        ok "$f fuehrt wlan in seiner Programmliste"
    else
        bad "$f does not know wlan -- so it is missing from the image"
    fi
done

#    jemand die Ehrlichkeit herausnimmt.
if grep -q 'no device -- there is no driver' kernel/user/wlan.fi; then
    ok "'wlan status' says there is no device instead of staying silent"
else
    bad "'wlan status' claims something else"
fi
if grep -q '0600\|384' kernel/user/wlan.fi; then
    ok "/etc/wlan.conf gets mode 0600 (the PMK is a secret)"
else
    bad "the permissions of /etc/wlan.conf are not set"
fi
if grep -q 'SYS_UNLINK' kernel/user/wlan.fi; then
    ok "if setting the mode fails, the file is DELETED AGAIN"
else
    bad "a file with wrong permissions would stay behind"
fi

if ! command -v qemu-system-x86_64 > /dev/null 2>&1; then
    ok "no QEMU available -- the run is skipped (not claimed)"
else
    if HWNET_PROGS="sh ls cat echo mkdir wlan" \
        bash tools/hwnet/build.sh "$W/img" 0 > "$W/img.txt" 2>&1; then
        ok "an image with /bin/wlan in it builds"
        timeout 150 qemu-system-x86_64 -kernel "$W/img/k.mb" -m 256 \
            -append "osum script=wlan status;mkdir /etc;wlan verbinden MeinNetz geheim12345;cat /etc/wlan.conf;wlan verbinden X kurz;wlan vergessen;wlan fw;exit" \
            -serial "file:$W/lauf.txt" -display none -no-reboot \
            -drive "file=$W/img/disk.img,format=raw,if=ide,index=0" \
            -device isa-debug-exit,iobase=0xf4,iosize=0x04 > /dev/null 2>&1
        RC=$?
        if [ "$RC" = 21 ]; then
            ok "Osum boots and shuts down cleanly with /bin/wlan (exit value 21)"
        else
            bad "the run ends with $RC instead of 21"
        fi
        L="$W/lauf.txt"
        grep -qa 'wlan: no device -- there is no driver' "$L" \
            && ok "'wlan status' says during the RUN that there is no device" \
            || bad "'wlan status' says nothing like that in the run"
        grep -qa 'wlan: /etc/wlan.conf written for network MeinNetz' "$L" \
            && ok "'wlan connect' creates /etc/wlan.conf wirklich an" \
            || bad "/etc/wlan.conf is not created in the run"
        grep -qa 'wlan fw: file missing' "$L" \
            && ok "'wlan fw' reports honestly during the RUN: firmware file missing (no crash)" \
            || bad "'wlan fw' says nothing fitting in the run"
        grep -qa '^ssid MeinNetz' "$L" && grep -qa '^psk geheim12345' "$L" \
            && ok "in /etc/wlan.conf really contains ssid and psk" \
            || bad "the content of /etc/wlan.conf is wrong"
        grep -qa 'wlan: the password must be 8 to 63 characters' "$L" \
            && ok "a too short password is rejected instead of accepted" \
            || bad "a too short password gets through"
        grep -qa 'wlan: /etc/wlan.conf deleted' "$L" \
            && ok "'wlan vergessen' deletes the file again" \
            || bad "'wlan vergessen' deletes nothing"
        grep -qa 'wlan: this does NOT connect' "$L" \
            && ok "after setup the program says explicitly that it does NOT connect" \
            || bad "the program leaves open whether it connects"
    else
        bad "the image with /bin/wlan does not build"
        tail -5 "$W/img.txt"
    fi
fi

echo
echo "WLANPROG: $pass Zusagen, $fail Fehler"
[ "$fail" = "0" ] || exit 1
exit 0
