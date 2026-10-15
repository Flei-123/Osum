#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/privacy/run.sh -- E4: WHO CALLS HOME? (/bin/privacy), MEASURED.
#
#   bash tools/privacy/run.sh
#
# Real guest under QEMU with KNOWN /etc/ota.conf and /etc/ntp.conf:
#   - the report names telemetry "none" and shows the update source and the
#     clock server READ FROM THE FILES (not from a fixed text)
#   - switch rows follow the files: auto=ja -> ON, `privacy auto update off`
#     writes auto=nein (other lines stay), the report then says OFF, `on`
#     writes auto=ja again; same for the clock (auto=false / auto=true)
#   - COUNTER-PROBE: a config WITHOUT auto= reads ON for the update check
#     (default ON, same as stored) and OFF for the clock (needs auto=true)
#   - a bad argument is refused (exit text, nothing written)
#   - static: privacy + sysinfo are in the stick image list, the installer
#     says "no telemetry" in both languages, the three programs fit the stick
set -uo pipefail
cd "$(dirname "$0")/../.."
export FIRNLIB="${FIRNLIB:-$(pwd)/lib}"
pass=0; fail=0
ok()  { pass=$((pass+1)); printf '  OK    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }
has() { grep -qaF -- "$2" "$1" && ok "$3" || bad "$3 -- '$2' missing"; }
hasnot() { grep -qaF -- "$2" "$1" && bad "$3 -- '$2' is there and should not be" || ok "$3"; }
part() { awk -v a="==$2==" -v b="==$3==" 'index($0,a){f=1;next} index($0,b){f=0} f' "$1"; }
TMPD=$(mktemp -d); trap 'rm -rf "$TMPD"' EXIT
: "${OSUM_QEMU_ACCEL:=tcg}"
[ -e /dev/kvm ] && [ "$OSUM_QEMU_ACCEL" = tcg ] && OSUM_QEMU_ACCEL=kvm
bash vendor/firn/fetch-firnc.sh >/dev/null 2>&1
mkdir -p "$TMPD/bin"
PROGS="sh cat echo privacy sysinfo"
if bash tools/sync/build.sh "$TMPD/bin" 0 $PROGS > "$TMPD/b.txt" 2>&1; then
    ok "privacy + sysinfo build"
else
    bad "build"; head -20 "$TMPD/b.txt"; echo "PRIVACY: $pass passed, $fail failed"; exit 1
fi
if ./tools/build-kernel.sh "$TMPD/k0.img" --stufe 0 > "$TMPD/k.txt" 2>&1; then
    ok "kernel builds"
else
    bad "kernel"; tail -5 "$TMPD/k.txt"; echo "PRIVACY: $pass passed, $fail failed"; exit 1
fi
printf 'quelle=https://updates.example.test/feed\nauto=ja\nabstand=3600\n' > "$TMPD/ota.conf"
printf 'server=time.example.test\nauto=true\nabstand=900\n' > "$TMPD/ntp.conf"
cat > "$TMPD/s.sh" <<'EOS'
echo ==R1==
privacy
echo ==UOFF==
privacy auto update off
cat /etc/ota.conf
echo ==R2==
privacy
echo ==UON==
privacy auto update on
cat /etc/ota.conf
echo ==COFF==
privacy auto clock off
cat /etc/ntp.conf
echo ==R3==
privacy
echo ==BAD==
privacy auto update maybe
privacy auto toaster on
echo ==BADCONF==
cat /etc/ota.conf
echo ==NOAUTO==
echo quelle=https://x.test/f > /etc/ota.conf
echo server=t.test > /etc/ntp.conf
privacy
echo ==END==
EOS
python3 tools/osum/mkfs.py build "$TMPD/d.img" 20000 /lib/ \
    "/lib/mono.ttf=assets/osum-mono.ttf" "/lib/sans.ttf=assets/osum-sans.ttf" \
    /bin/ /t/ /tmp/ /proc/ /dev/ /system/ /etc/ /var/ \
    $(for p in $PROGS; do echo "/bin/$p=$TMPD/bin/$p.elf"; done) \
    "/etc/ota.conf=$TMPD/ota.conf" "/etc/ntp.conf=$TMPD/ntp.conf" \
    "/t/s.sh=$TMPD/s.sh" > "$TMPD/mkfs.txt" 2>&1 || tail -3 "$TMPD/mkfs.txt"
timeout 150 qemu-system-x86_64 -accel "$OSUM_QEMU_ACCEL" -smp 1 \
    -kernel "$TMPD/k0.img" -m 512 \
    -append "osum vfs nokbd script=sh /t/s.sh;exit" \
    -serial "file:$TMPD/o.txt" -display none -no-reboot \
    -drive "file=$TMPD/d.img,format=raw,if=ide,index=0" \
    -device isa-debug-exit,iobase=0xf4,iosize=0x04 >/dev/null 2>&1
tr -cd '\11\12\15\40-\176' < "$TMPD/o.txt" > "$TMPD/o.klar"
for s in "R1 UOFF" "UOFF R2" "R2 UON" "UON COFF" "COFF R3" "R3 BAD" "BAD BADCONF" "BADCONF NOAUTO" "NOAUTO END"; do
    set -- $s; part "$TMPD/o.klar" "$1" "$2" > "$TMPD/$1.txt"
done
has "$TMPD/R1.txt" "OrientOS privacy report" "report: header"
has "$TMPD/R1.txt" "telemetry:    none" "report: telemetry is none"
has "$TMPD/R1.txt" "account:      not required" "report: no account needed"
has "$TMPD/R1.txt" "https://updates.example.test/feed" "report: update source comes from /etc/ota.conf"
has "$TMPD/R1.txt" "time.example.test" "report: clock server comes from /etc/ntp.conf"
has "$TMPD/R1.txt" "3600 s" "report: update interval from the file"
has "$TMPD/R1.txt" "900 s" "report: clock interval from the file"
[ "$(grep -ac 'switch:   ON' "$TMPD/R1.txt")" = 2 ] && ok "report: both switches ON (auto=ja, auto=true)" || bad "report: both switches ON"
has "$TMPD/UOFF.txt" "ok: update off" "update off: confirmed"
has "$TMPD/UOFF.txt" "auto=nein" "update off: the file says auto=nein"
has "$TMPD/UOFF.txt" "quelle=https://updates.example.test/feed" "update off: the source line stays"
[ "$(grep -ac 'switch:   OFF' "$TMPD/R2.txt")" = 1 ] && [ "$(grep -ac 'switch:   ON' "$TMPD/R2.txt")" = 1 ] && ok "report after off: update OFF, clock still ON" || bad "report after off"
has "$TMPD/UON.txt" "auto=ja" "update on: the file says auto=ja again"
has "$TMPD/COFF.txt" "auto=false" "clock off: the file says auto=false"
has "$TMPD/COFF.txt" "server=time.example.test" "clock off: the server line stays"
[ "$(grep -ac 'switch:   OFF' "$TMPD/R3.txt")" = 1 ] && [ "$(grep -ac 'switch:   ON' "$TMPD/R3.txt")" = 1 ] && ok "report: update ON, clock OFF" || bad "report: update ON, clock OFF"
has "$TMPD/BAD.txt" "usage: privacy auto update|clock on|off" "bad argument: usage text"
hasnot "$TMPD/BADCONF.txt" "maybe" "bad argument: nothing was written"
[ "$(grep -ac 'switch:   ON' "$TMPD/NOAUTO.txt")" = 1 ] && [ "$(grep -ac 'switch:   OFF' "$TMPD/NOAUTO.txt")" = 1 ] \
    && ok "COUNTER-PROBE: no auto= -> update ON (default), clock OFF" || bad "COUNTER-PROBE: no auto= defaults"
# static checks
grep -q ' sysinfo massren privacy welcome"}' tools/usbimg/build.sh && ok "usbimg PROGS has sysinfo + privacy" || bad "usbimg PROGS"
for l in de en; do
    grep -q '^installer.privacy = ' locale/$l/messages && ok "installer.privacy in $l" || bad "installer.privacy in $l"
done
grep -qi 'telemetr' locale/de/messages && ok "de text names telemetry" || bad "de text"
sz=$(( $(stat -c %s "$TMPD/bin/privacy.elf") + $(stat -c %s "$TMPD/bin/sysinfo.elf") ))
[ "$sz" -lt 262144 ] && ok "privacy + sysinfo together $sz bytes (< 256 KiB, stick has 5.4 MiB free)" || bad "size $sz"
echo "PRIVACY: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
