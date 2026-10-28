#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
set -uo pipefail
cd "$(dirname "$0")/../.."
HERE="$PWD"
export FIRNLIB="$HERE/lib"
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
pass=0; fail=0
ok()  { pass=$((pass+1)); printf '  OK    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }
has() { grep -qaF -- "$2" "$1" && ok "$3" || bad "$3 -- '$2' missing"; }
hasnot() { grep -qaF -- "$2" "$1" && bad "$3 -- '$2' present" || ok "$3"; }
ACC=tcg; [ -w /dev/kvm ] && ACC=kvm
bash vendor/firn/fetch-firnc.sh >/dev/null 2>&1
mkdir -p "$T/blobs" "$T/bin"
python3 -I tools/iwlfh/ref.py gen "$T/blobs" || { bad "reference generator"; exit 1; }
FWPATH=/lib/firmware/intel/iwlwifi/iwlwifi-8265-36.ucode
bash tools/sync/build.sh "$T/bin" 0 sh echo cat sleep wlanctl > "$T/b.txt" 2>&1 \
    && ok "programs build" || { bad "programs build"; tail "$T/b.txt"; echo "WLANCTL: $pass ok, $fail fail"; exit 1; }
./tools/build-kernel.sh "$T/k.img" --stufe 0 > "$T/k.txt" 2>&1 \
    && ok "kernel builds" || { bad "kernel build"; tail -30 "$T/k.txt"; echo "WLANCTL: $pass ok, $fail fail"; exit 1; }

cat > "$T/s.sh" <<'EOS'
echo ==START==
sleep 4
echo ==SCAN==
wlanctl scan
echo ==BADPSK==
wlanctl connect OrientFake short
echo ==BADCOUNT==
wlanctl connect OrientFake
echo ==CONNECT==
wlanctl connect OrientFake orient-fake-pw1
echo ==PROC==
cat /proc/wlan
echo ==CONF==
cat /etc/wlan.conf
echo ==FORGET==
wlanctl forget
sleep 3
cat /proc/wlan
echo ==NOCONF==
cat /etc/wlan.conf
echo ==WRONG==
wlanctl connect OrientFake wrong-password-9
echo ==END==
EOS
python3 tools/osum/mkfs.py build "$T/a.img" 20000 --v3 /bin/ /t/ /etc/ /proc/ /lib/ /lib/firmware/ /lib/firmware/intel/ /lib/firmware/intel/iwlwifi/ \
    /bin/sh="$T/bin/sh.elf" /bin/echo="$T/bin/echo.elf" /bin/cat="$T/bin/cat.elf" /bin/sleep="$T/bin/sleep.elf" /bin/wlanctl="$T/bin/wlanctl.elf" \
    "/t/s.sh=$T/s.sh" "$FWPATH=$T/blobs/v7.bin" > "$T/mkfs.txt" 2>&1 || { bad "image"; tail -3 "$T/mkfs.txt"; exit 1; }
run() { # name words
    timeout 600 qemu-system-x86_64 -accel "$ACC" -smp 1 -kernel "$T/k.img" -m 512 \
        -append "osum vfs $2 script=sh /t/s.sh;exit" \
        -serial "file:$T/$1.txt" -display none -no-reboot \
        -drive "file=$T/a.img,format=raw,if=ide,index=0" \
        -device isa-debug-exit,iobase=0xf4,iosize=0x04 >/dev/null 2>&1
    tr -cd '\11\12\15\40-\176' < "$T/$1.txt" > "$T/$1.klar"
}
run a "iwlfhtest iwlfhbind"
A="$T/a.klar"
sec() { awk -v s="==$1==" 'f&&/^==[A-Z]+==$/{exit} f{print} $0==s{f=1}' "$A" > "$T/sec.txt"; }
has "$A" '==END==' "script ran to the end"
sec SCAN
has "$T/sec.txt" 'OrientFake ch=' "scan lists OrientFake with channel"
has "$T/sec.txt" 'CafeOpen ch=' "scan lists CafeOpen"
has "$T/sec.txt" 'sec=wpa2' "scan shows the security class"
has "$T/sec.txt" 'seq=' "scan reports the sequence counter"
sec BADPSK
has "$T/sec.txt" 'passphrase must be 8..63' "short passphrase refused"
sec BADCOUNT
has "$T/sec.txt" 'usage: wlanctl connect' "wrong argument count refused"
sec CONNECT
has "$T/sec.txt" 'connected' "connect reports connected"
has "$T/sec.txt" 'ip=192.168.77.50' "connect prints the DHCP lease"
sec PROC
has "$T/sec.txt" 'auto=up rc=0' "proc shows auto=up"
has "$T/sec.txt" 'diag: step=none err=0 cmd=0x0 ok=0x3e' "proc diag line: no failed step, all five steps ok"
sec CONF
has "$T/sec.txt" 'ssid OrientFake' "conf holds the ssid"
sec FORGET
has "$T/sec.txt" 'forgotten' "forget acknowledged"
has "$A" 'auto=no-conf' "after forget the autostart state is no-conf"
sec WRONG
grep -qa '^connected' "$T/sec.txt" && bad "wrong password never connects" || ok "wrong password never connects"
has "$T/sec.txt" 'not connected' "wrong password reports failure"
echo "WLANCTL: $pass ok, $fail fail"
[ "$fail" = 0 ]
