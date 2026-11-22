#!/usr/bin/env bash
set -uo pipefail
cd "$(dirname "$0")/../.."
ROOT=$(pwd)
export FIRNLIB="${FIRNLIB:-$ROOT/lib}"
. tools/lib/qemu.sh
. tools/lib/firnenv.sh

FEED=${STOREPKGS_FEED:-/srv/store/osum/aktuell}
OUT=${STOREPKGS_OUT:-$(mktemp -d)}
KERNEL=${STOREPKGS_KERNEL:-}
BLOCKS=${BLOCKS:-200000}
PROGS="sh ls cat echo sleep opk ps kill"
mkdir -p "$OUT/bin"
[ -n "${STOREPKGS_OUT:-}" ] || trap 'rm -rf "$OUT"' EXIT

bash tools/sync/build.sh "$OUT/bin" 0 $PROGS > "$OUT/build.log" 2>&1 || { tail -10 "$OUT/build.log"; exit 1; }
if [ -z "$KERNEL" ]; then
    KERNEL=$OUT/k0.img
    ./tools/build-kernel.sh "$KERNEL" --stufe 0 > "$OUT/kernel.log" 2>&1 || { tail -5 "$OUT/kernel.log"; exit 1; }
fi

PKGS=$(cut -f1 "$FEED/INDEX")
{
    for p in $PKGS; do
        echo "echo ==P-$p=="
        echo "opk install /q/$p-1.opk"
        echo "opk list"
        echo "ls /apps"
        echo "/apps/$p.osp/start &"
        echo "sleep 3"
        echo "ps"
        echo "echo ==R-$p=="
        echo "opk remove $p"
        echo "ls /apps"
    done
    echo "echo ==DONE=="
} > "$OUT/s.sh"

A=(build "$OUT/img" "$BLOCKS" --v3 --inodes=512 --karten=64 /lib/
    "/lib/mono.ttf=assets/osum-mono.ttf" "/lib/sans.ttf=assets/osum-sans.ttf"
    /bin/ /t/ /tmp/ /proc/ /dev/ /system/ /etc/ /apps/ /store/ /users/ /var/ /var/log/ /q/)
for p in $PROGS; do A+=("/bin/$p=$OUT/bin/$p.elf"); done
A+=("/system/schluessel.pub=$FEED/schluessel.pub" "/t/s.sh=$OUT/s.sh")
for p in $PKGS; do A+=("/q/$p-1.opk=$FEED/$p-1.opk" "/q/$p-1.opk.sig=$FEED/$p-1.opk.sig"); done
bash tools/mkfsfi/mkfs.sh "${A[@]}" > "$OUT/mkfs.txt" 2>&1 || { tail -3 "$OUT/mkfs.txt"; exit 1; }

timeout "${STOREPKGS_SECS:-900}" $QEMU_X86 -cpu Haswell -smp 1 -kernel "$KERNEL" -m 768 \
    -append "osum vfs nokbd bus nic nip=10.0.2.15/24 ngw=10.0.2.2 nsvc=0 nwait=0 script=sh /t/s.sh;exit" \
    -serial "file:$OUT/serial.txt" -display none -no-reboot \
    -drive "file=$OUT/img,format=raw,if=ide,index=0" \
    -device isa-debug-exit,iobase=0xf4,iosize=0x04 >/dev/null 2>&1
tr -cd '\11\12\15\40-\176' < "$OUT/serial.txt" > "$OUT/serial.clean"
for p in $PKGS; do
    awk -v a="==P-$p==" -v b="==R-$p==" 'index($0,a){f=1} f{print} index($0,b){exit}' "$OUT/serial.clean" > "$OUT/pkg-$p.txt"
    inst=no; grep -q "opk: installed $p" "$OUT/pkg-$p.txt" && inst=yes
    printf '%s\tinstalled=%s\n' "$p" "$inst"
done
grep -q "==DONE==" "$OUT/serial.clean" && echo "DONE reached" || echo "DONE missing"
[ -z "${STOREPKGS_OUT:-}" ] || echo "out: $OUT"
