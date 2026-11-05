#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/battery/run.sh -- battery data validity: unusable firmware packets must read as "unknown", never as 0 %.
#   bash tools/battery/run.sh   (BATTERY_KERNEL=<k0.img> reuses a built kernel)
set -uo pipefail
cd "$(dirname "$0")/../.."
T=${BATTERY_KEEP:-$(mktemp -d)}; [ -n "${BATTERY_KEEP:-}" ] || trap 'rm -rf "$T"' EXIT
pass=0; fail=0
ok()  { pass=$((pass+1)); echo "  OK    $1"; }
bad() { fail=$((fail+1)); echo "  FAIL  $1"; }
: "${OSUM_QEMU_ACCEL:=tcg}"
[ -w /dev/kvm ] && [ "$OSUM_QEMU_ACCEL" = tcg ] && OSUM_QEMU_ACCEL=kvm
export FIRNLIB="$PWD/lib"
command -v iasl >/dev/null 2>&1 && command -v qemu-system-x86_64 >/dev/null 2>&1 || { echo "  SKIP  iasl or qemu missing"; exit 0; }
mkdir -p "$T/bin"
bash tools/sync/build.sh "$T/bin" 0 sh echo sleep cat powerd > "$T/b.txt" 2>&1 && ok "user programs build" || { bad "user programs do not build"; tail -5 "$T/b.txt"; }
K="${BATTERY_KERNEL:-$T/k0.img}"
if [ -z "${BATTERY_KERNEL:-}" ]; then
    ./tools/build-kernel.sh "$K" --stufe 0 > "$T/k.txt" 2>&1 && ok "the kernel builds" || { bad "the kernel does not build"; tail -5 "$T/k.txt"; }
fi
cat > "$T/s.sh" <<'SCRIPT'
sleep -m 500
echo ==PROC==
cat /proc/battery
sleep -m 500
echo ==STATUS==
powerd status
sleep -m 500
echo ==END==
SCRIPT
run_case() {
    local n=$1 full=$2 state=$3 rate=$4 rem=$5 volt=$6 kernel=${7:-$K} template=${8:-plain}
    sed "s/@FULL@/$full/g; s/@STATE@/$state/; s/@RATE@/$rate/; s/@REM@/$rem/; s/@VOLT@/$volt/" "tools/battery/asl/$template.asl" > "$T/$n.asl"
    ( cd "$T" && iasl "$n.asl" > "$n.iasl.txt" 2>&1 ) || { bad "$n.asl does not compile"; return; }
    bash tools/mkfsfi/mkfs.sh build "$T/$n.img" 20000 /bin/ /etc/ /run/ /tmp/ /t/ /proc/ /dev/ /system/ /var/ \
        "/bin/sh=$T/bin/sh.elf" "/bin/echo=$T/bin/echo.elf" "/bin/sleep=$T/bin/sleep.elf" "/bin/cat=$T/bin/cat.elf" \
        "/bin/powerd=$T/bin/powerd.elf" "/t/s.sh=$T/s.sh" > "$T/$n.mkfs" 2>&1 || { bad "$n mkfs failed"; return; }
    timeout 240 qemu-system-x86_64 -accel "$OSUM_QEMU_ACCEL" -kernel "$kernel" -m 512 \
        -append "osum vfs nokbd nosched acpiev script=sh /t/s.sh;exit" \
        -acpitable "file=$T/$n.aml" -serial "file:$T/$n.ser" -display none -no-reboot \
        -drive "file=$T/$n.img,format=raw,if=ide,index=0" \
        -device isa-debug-exit,iobase=0xf4,iosize=0x04 >/dev/null 2>&1
    tr -cd '\11\12\15\40-\176' < "$T/$n.ser" | tr -d '\r' > "$T/$n.txt"
}
has() { sed -n '/^sh: ready/,$p' "$T/$1.txt" | grep -qaF -- "$2" && ok "$3" || bad "$3 -- '$2' missing"; }
echo "== 1. firmware default packets (full=rem=0xFFFFFFFF)"
run_case dflt 0xFFFFFFFF 0 0xFFFFFFFF 0xFFFFFFFF 0xFFFFFFFF
has dflt "present=1 valid=0 percent=0" "default packets: battery present, data NOT valid"
has dflt "bif=1 bst=1" "both methods ran and returned packages"
has dflt "tray=6" "tray model reports UNKNOWN (6), not critical"
echo "== 2. zero full-charge capacity"
run_case zero 0 0 0 0x100 0x2A30
has zero "present=1 valid=0" "full=0: not valid"
echo "== 3. counter-proof: realistic data"
run_case good 5000 1 0x200 2500 0x2A30
has good "present=1 valid=1 percent=50" "valid data: 50 %"
has good "tray=1" "tray model: discharging, not unknown"
echo "== 4. a failed earlier evaluation must not poison later ones"
run_case poison 0 0 0 0 0 "$K" poison
has poison "bst=1" "_BST evaluates after _BIF failed once"
has poison "biferr=" "the AML error code of the failed _BIF is reported"
has poison "bsterr=0" "no stale error code on _BST"
if [ -z "${BATTERY_KERNEL:-}" ]; then
    mkdir -p "$T/old"
    tar --exclude=.git -cf - . | tar -xf - -C "$T/old"
    perl -0pi -e 's/(amlev\.stack_base\(state\)\n    )amlns\.err_clear\(state\)/$1amlns.err_set(state, amlns.ERR_OK)/g' "$T/old/kernel/acpi/aml.fi"
    perl -0pi -e 's/(E_B(?:IF|ST)ERR, amlns\.err\(state\)\)\n        )amlns\.err_clear\(state\)/$1amlns.err_set(state, amlns.ERR_OK)/g' "$T/old/kernel/acpi/acpiev.fi"
    cmp -s kernel/acpi/acpiev.fi "$T/old/kernel/acpi/acpiev.fi" && bad "control acpiev identical to the fixed one"
    cmp -s kernel/acpi/aml.fi "$T/old/kernel/acpi/aml.fi" && bad "control kernel identical to the fixed one"
    (cd "$T/old" && ./tools/build-kernel.sh "$T/old.img" --stufe 0 > "$T/kold.txt" 2>&1) && ok "control kernel (sticky error) builds" || { bad "control kernel does not build"; tail -5 "$T/kold.txt"; }
    run_case poisonold 0 0 0 0 0 "$T/old.img" poison
    has poisonold "bst=2" "control: sticky error makes _BST fail after a failed _BIF"
fi
echo; echo "battery: $pass ok, $fail fail"
[ "$fail" -eq 0 ]
