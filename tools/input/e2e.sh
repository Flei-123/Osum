#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/input/e2e.sh IMAGE -- end to end: synthetic reports -> HID layer -> tracker -> /proc/touchev -> ring-3 demo app (lib/touchev API).
set -uo pipefail
cd "$(dirname "$0")/../.."
ROOT=$(pwd)
export FIRNLIB="$ROOT/lib"
export PYTHONDONTWRITEBYTECODE=1
IMG=${1:?usage: e2e.sh IMAGE}
: "${OSUM_QEMU_ACCEL:=tcg}"
[ -e /dev/kvm ] && [ "$OSUM_QEMU_ACCEL" = tcg ] && OSUM_QEMU_ACCEL=kvm
pass=0; fail=0
ok()  { pass=$((pass+1)); printf '  OK    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }
T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT
PROGS="sh cat echo sleep touchdemo"
mkdir -p "$T/bin"
bash vendor/firn/fetch-firnc.sh >/dev/null 2>&1
if bash tools/sync/build.sh "$T/bin" 0 $PROGS > "$T/b.txt" 2>&1; then
    ok "the demo app and its shell build"
else
    bad "programs do not build"; sed 's/^/        /' "$T/b.txt" | head -10
    echo "e2e: $pass ok, $fail fail"; exit 1
fi
printf "touchdemo\nsleep 2\ntouchdemo\nsleep 2\n" > "$T/s.sh"
A=(build "$T/disk.img" 4000 /lib/ /bin/ /t/ /tmp/ /proc/ /dev/ /system/ /etc/)
for p in $PROGS; do A+=("/bin/$p=$T/bin/$p.elf"); done
A+=("/t/s.sh=$T/s.sh")
python3 tools/osum/mkfs.py "${A[@]}" > "$T/mkfs.txt" 2>&1 || { bad "mkfs failed"; tail -3 "$T/mkfs.txt"; }
timeout 120 qemu-system-x86_64 -accel "$OSUM_QEMU_ACCEL" -kernel "$IMG" -m 512 \
    -append "osum vfs nokbd bus touchsim script=sh /t/s.sh;exit" \
    -serial "file:$T/out.txt" -display none -no-reboot \
    -drive "file=$T/disk.img,format=raw,if=ide,index=0" \
    -device isa-debug-exit,iobase=0xf4,iosize=0x04 >/dev/null 2>&1
tr -cd '\11\12\15\40-\176' < "$T/out.txt" > "$T/out.clean" 2>/dev/null
cp "$T/out.clean" "${E2E_OUT:-/dev/null}" 2>/dev/null || true
if python3 -I tools/input/e2e_check.py "$T/out.clean"; then
    ok "demo app output matches the independent expectation"
else
    bad "demo app output differs"
fi
echo "e2e: $pass ok, $fail fail"
[ "$fail" = 0 ]
