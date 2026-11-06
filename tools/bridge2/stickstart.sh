#!/usr/bin/env bash
set -uo pipefail
cd "$(dirname "$0")/../.."
ROOT=$(pwd)
export FIRNLIB="$ROOT/lib"
W=${STICK_W:-/tmp/bruecke-stick}
BUILDD=${DESIGNBUILD:-/tmp/osum-eh5build-e9e5f1ff94da}
rm -rf "$W"; mkdir -p "$W"
pass=0; fail=0
ok()  { pass=$((pass+1)); printf '  OK    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }
note(){ printf '        %s\n' "$1"; }

command -v qemu-system-x86_64 >/dev/null || { echo "kein qemu"; exit 0; }
[ -s "$BUILDD/k0.mb" ] || { echo "kein Kern in $BUILDD"; exit 1; }

./tools/build-kernel.sh "$W/k0.mb" > "$W/k.log" 2>&1 || {
    echo "the kernel does not build"; tail -20 "$W/k.log"; exit 1; }
note "kernel $(stat -c%s "$W/k0.mb") Oktette"

[ -s "${STICK_ROOT:-/tmp/m11-img2/root.img}" ] && cp "${STICK_ROOT:-/tmp/m11-img2/root.img}" "$W/disk.img"
[ -s "$W/disk.img" ] || { echo "no disk -- run tools/design/eh5.sh first"; exit 1; }

APPEND="osum gfx fbres=1280x800 wm wig desk wmshell wmdauer tafel herz"
APPEND="$APPEND crashhalt nopuls tz=120 lang=en"
APPEND="$APPEND nic nip=169.254.10.1/16 nsvc=0 nwait=0 dhcp jarvis"
APPEND="$APPEND nosched noproc nofs"
note "append $APPEND"

timeout 240 qemu-system-x86_64 -kernel "$W/k0.mb" -m 512 \
    -append "$APPEND" \
    -serial "file:$W/serial.txt" -display none -no-reboot \
    -device "VGA,edid=on,xres=1280,yres=800,vgamem_mb=32" \
    -drive "file=$W/disk.img,format=raw,if=ide,index=0" \
    -netdev user,id=n0 -device e1000,netdev=n0 \
    > "$W/qemu.log" 2>&1 &
QPID=$!
i=0
while [ $i -lt 700 ]; do
    grep -qa 'PAIRING CODE\|jarvisd: signed in' "$W/serial.txt" 2>/dev/null && break
    kill -0 "$QPID" 2>/dev/null || break
    sleep 0.2; i=$((i+1))
done
sleep 5
kill "$QPID" 2>/dev/null; wait "$QPID" 2>/dev/null

echo "== what was on the wire =="
grep -aE 'dhcp:|jarvisd:|desk: start' "$W/serial.txt" | head -20 | sed 's/^/        /'

grep -qa 'desk: start /bin/jarvisd\|jarvisd: ready' "$W/serial.txt" \
    && ok "the kernel starts /bin/jarvisd BY ITSELF" \
    || bad "jarvisd is not started"
grep -qa 'resolv.conf geschrieben' "$W/serial.txt" \
    && ok "dhcp hat /etc/resolv.conf geschrieben" \
    || bad "no resolv.conf -- then there is no name resolution"
grep -qa 'jarvisd: der Name laesst sich nicht aufloesen' "$W/serial.txt" \
    && bad "the name does not resolve" \
    || ok "store.fleitec.com loest auf"
grep -qa 'PAIRING CODE' "$W/serial.txt" \
    && ok "the device shows a PAIRING CODE" \
    || bad "kein Kopplungscode"

HEX=$(grep -a 'PAIRING CODE' "$W/serial.txt" | tail -1 | awk '{print $NF}')
if [ -n "$HEX" ]; then
    note "Code, den Justin vorliest: $(python3 -c "import sys;print(bytes.fromhex(sys.argv[1]).decode())" "$HEX" 2>/dev/null)"
fi

echo "== and what the service says about it =="
journalctl -u bruecke --since '-4 min' --no-pager 2>/dev/null \
    | grep -iE 'KOPPLUNG NOETIG|ANGEMELDET' | tail -3 | sed 's/^/        /'
journalctl -u bruecke --since '-4 min' --no-pager 2>/dev/null \
    | grep -qi 'KOPPLUNG NOETIG' \
    && ok "the service issued the code" \
    || bad "nothing in the log of the service"

echo
echo "STICKSTART: $pass bestanden, $fail durchgefallen"
[ "$fail" -eq 0 ]
