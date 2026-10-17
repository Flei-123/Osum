#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/info/run.sh -- /proc/version (build hash + image id), /proc/usb
# (controllers + devices) and `jarvisctl info` (one call for the bridge).
#
#   bash tools/info/run.sh            # new tree
#   OLD=<worktree of old main> bash tools/info/run.sh   # COUNTER-PROOF: the same
#                                     # checks must go RED on the old tree
#
# Real guest under QEMU (qemu-xhci + usb-kbd + usb-tablet + e1000 with DHCP).
# Kernel is built with IMAGE_ID=gate42, so the image id in the guest is
# measured, not assumed. The default "dev" is checked on the build tool.
set -uo pipefail
cd "$(dirname "$0")/../.."
ROOT=$(pwd)
SRC=${OLD:-$ROOT}
export FIRNLIB="${FIRNLIB:-$SRC/lib}"
pass=0; fail=0
ok()  { pass=$((pass+1)); printf '  OK    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }
has() { grep -qaF -- "$2" "$1" && ok "$3" || bad "$3 -- '$2' missing"; }
hasre() { grep -qaE -- "$2" "$1" && ok "$3" || bad "$3 -- /$2/ missing"; }
part() { awk -v a="==$2==" -v b="==$3==" 'index($0,a){f=1;next} index($0,b){f=0} f' "$1"; }
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
: "${OSUM_QEMU_ACCEL:=tcg}"
[ -e /dev/kvm ] && [ "$OSUM_QEMU_ACCEL" = tcg ] && OSUM_QEMU_ACCEL=kvm
cd "$SRC"
bash vendor/firn/fetch-firnc.sh >/dev/null 2>&1

# --- build tool: default image id is "dev", IMAGE_ID overrides, junk is refused
if [ -z "${OLD:-}" ]; then
    C="$T/tree/kernel/lib"; mkdir -p "$C"
    cp kernel/lib/version.fi kernel/lib/brand.fi "$C/"
    python3 tools/marke-einsetzen.py "$T/tree" marke.conf abcd1234 > "$T/m1.txt" 2>&1
    grep -q "image id 'dev'" "$T/m1.txt" && ok "build tool: default image id is dev" || bad "build tool: default image id"
    python3 tools/marke-einsetzen.py "$T/tree" marke.conf abcd1234 "a b" > "$T/m2.txt" 2>&1 \
        && bad "build tool: an image id with a blank is refused" || ok "build tool: an image id with a blank is refused"
fi

mkdir -p "$T/bin"
PROGS="sh cat echo uname jarvisctl dhcp sleep"
bash tools/sync/build.sh "$T/bin" 0 $PROGS > "$T/b.txt" 2>&1
for p in cat jarvisctl; do [ -s "$T/bin/$p.elf" ] || { bad "program $p builds"; tail -5 "$T/b.txt"; }; done
IMAGE_ID=gate42 ./tools/build-kernel.sh "$T/k0.img" --stufe 0 > "$T/k.txt" 2>&1 \
    && ok "kernel builds" || { bad "kernel build"; tail -5 "$T/k.txt"; echo "INFO: $pass passed, $fail failed"; exit 1; }

cat > "$T/s.sh" <<'EOS'
echo ==VER==
cat /proc/version
uname
echo ==USB==
cat /proc/usb
echo ==NET==
dhcp
sleep 2
echo ==INFO==
jarvisctl info
echo ==END==
EOS
python3 tools/osum/mkfs.py build "$T/d.img" 20000 /lib/ \
    "/lib/mono.ttf=assets/osum-mono.ttf" "/lib/sans.ttf=assets/osum-sans.ttf" \
    /bin/ /t/ /tmp/ /proc/ /dev/ /system/ /etc/ /var/ /var/jarvis/ \
    $(for p in $PROGS; do echo "/bin/$p=$T/bin/$p.elf"; done) \
    "/t/s.sh=$T/s.sh" > "$T/mkfs.txt" 2>&1 || tail -3 "$T/mkfs.txt"
timeout 180 qemu-system-x86_64 -accel "$OSUM_QEMU_ACCEL" -smp 1 \
    -kernel "$T/k0.img" -m 512 \
    -device qemu-xhci -device usb-kbd -device usb-tablet \
    -netdev user,id=n0 -device e1000,netdev=n0,mac=52:54:00:aa:bb:cc \
    -append "osum vfs usb nic nip=169.254.10.1/16 nsvc=0 nwait=0 tz=60 tzrule=eu script=sh /t/s.sh;exit" \
    -serial "file:$T/o.txt" -display none -no-reboot \
    -drive "file=$T/d.img,format=raw,if=ide,index=0" \
    -device isa-debug-exit,iobase=0xf4,iosize=0x04 >/dev/null 2>&1
tr -cd '\11\12\15\40-\176' < "$T/o.txt" > "$T/o.klar"
part "$T/o.klar" VER USB > "$T/ver.txt"
part "$T/o.klar" USB NET > "$T/usb.txt"
part "$T/o.klar" INFO END > "$T/info.txt"

# --- /proc/version
hasre "$T/ver.txt" 'version [0-9]+ build [0-9a-f]{7,8}\+? image gate42$' "/proc/version: 'version N build <hash> image <id>'"
hasre "$T/ver.txt" '^[A-Za-z][A-Za-z ]* \(Firn\) version [0-9]+' "/proc/version: still starts '<name> (Firn) version N' (parseable)"
# --- /proc/usb
has "$T/usb.txt" "controller xhci " "/proc/usb: a controller line (xhci)"
hasre "$T/usb.txt" '^controller xhci [0-9a-f]{2}:[0-9a-f]{2}\.[0-9a-f] [0-9a-f]{4}:[0-9a-f]{4} ports=[0-9]+ state=up selected' "/proc/usb: controller line has bdf, ids, ports, state"
has "$T/usb.txt" "0627:0001" "/proc/usb: the usb-kbd"
has "$T/usb.txt" "driver=keyboard hc=xhci kind=hid-keyboard" "/proc/usb: keyboard has controller and kind"
hasre "$T/usb.txt" 'speed=[a-z]+ ' "/proc/usb: speed"
# --- jarvisctl info
for k in version build image clock uptime net usb; do
    has "$T/info.txt" "$k: " "info: key $k"
done
has "$T/info.txt" "image: gate42" "info: image id"
hasre "$T/info.txt" '^build: [0-9a-f]{7,8}\+?$' "info: build hash"
hasre "$T/info.txt" '^clock: 20[0-9]{2}-[01][0-9]-[0-3][0-9] [0-2][0-9]:[0-5][0-9]:[0-5][0-9] tz=-?[0-9]+ rule=[0-9]+$' "info: clock with effective tz offset and rule"
hasre "$T/info.txt" '^uptime: [0-9]+ ms' "info: uptime"
has "$T/info.txt" "usb: controllers=1 devices=2" "info: usb summary (kbd + tablet)"
has "$T/info.txt" "usb: controller xhci " "info: usb controller line"
hasre "$T/info.txt" '^net: ip=10\.0\.2\.' "info: network (ip from the DHCP lease)"
hasre "$T/info.txt" '^net: gateway=' "info: network gateway"
hasre "$T/info.txt" '^net: lease=' "info: network lease"
# bridge limit: the whole command is 2 words (limit is 6)
words=$(echo "/bin/jarvisctl info" | wc -w); [ "$words" -le 6 ] && ok "bridge command '/bin/jarvisctl info' has $words words (limit 6)" || bad "too many words"
if [ "$fail" != 0 ]; then echo "--- version/usb/info output:"; cat "$T/ver.txt" "$T/usb.txt" "$T/info.txt"; fi
echo "INFO: $pass passed, $fail failed"
[ "$fail" = 0 ]
