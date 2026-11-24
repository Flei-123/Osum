#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
set -uo pipefail
cd "$(dirname "$0")/../.."
export FIRNLIB="${FIRNLIB:-$(pwd)/lib}"
pass=0; fail=0
ok()  { pass=$((pass+1)); printf '  OK    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }
has() { grep -qaF -- "$2" "$1" && ok "$3" || bad "$3 -- '$2' missing"; }
hasnot() { grep -qaF -- "$2" "$1" && bad "$3 -- '$2' is there" || ok "$3"; }
hasre() { grep -qaE -- "$2" "$1" && ok "$3" || bad "$3 -- /$2/ missing"; }
command -v qemu-system-x86_64 >/dev/null || { echo "LKPI-IWL: skipped, no qemu"; exit 0; }
. tools/lib/tmpdir.sh
D=$(mktemp -d); osum_tmp_guard "" "$D"
. tools/lib/firnenv.sh
. compat/linuxkpi/flags.sh
ACC=tcg; [ -w /dev/kvm ] && ACC=kvm
keep() {
    [ -n "${LKPI_IWL_OUT:-}" ] || return 0
    mkdir -p "$LKPI_IWL_OUT" && cp "$D"/*.klar "$LKPI_IWL_OUT"/ 2>/dev/null
    return 0
}
fin() { keep; echo "LKPI-IWL: $pass passed, $fail failed"; [ "$fail" -eq 0 ]; exit $?; }
FW_FILE="${IWL_FW_FILE:-$(bash compat/linuxkpi/fetch.sh fw-iwlwifi-8265 "$D/fw" 2>/dev/null)}"
[ -f "$FW_FILE" ] || { echo "LKPI-IWL: skipped, firmware not fetchable from sources.tsv"; exit 0; }
FW_NAME=$(basename "$FW_FILE")

bash compat/linuxkpi/iwlmod.sh "$D/m" > "$D/mod.txt" 2>&1 && ok "iwlwifi (67 units) and shim build, closure ok, modules signed" || { bad "module build"; tail -5 "$D/mod.txt"; fin; }
FW_LINE=$(cat "$D/m/iwlwifi.fw")
PK_NATIVE=$(bash compat/linuxkpi/wifipack.sh "$D/m/linuxkpiwifi.omod" "$D/m/iwlwifi.omod" "$D/pk-native" lkpi-iwlwifi "pci 8086:24fd" "$FW_LINE" 2> "$D/pack-native.txt")
PK_LOAD=$(bash compat/linuxkpi/wifipack.sh "$D/m/linuxkpiwifi.omod" "$D/m/iwlwifi.omod" "$D/pk-load" lkpi-iwlload "pci 1234:11e8" "$FW_LINE" 2> "$D/pack-load.txt")
[ -f "$PK_NATIVE/driver.inf" ] && [ -f "$PK_LOAD/driver.inf" ] && ok "store packages built (8265 match, edu match for the load test)" || { bad "packages"; cat "$D/pack-native.txt"; fin; }
grep -qF "fw=$FW_LINE" "$PK_NATIVE/driver.inf" && ok "manifest pins the 8265 firmware by sha256" || bad "manifest firmware line"
FILE_SIZE=$(stat -c %s "$PK_NATIVE/iwlwifi.omod")
[ "$FILE_SIZE" -gt 524288 ] && ok "driver module is $FILE_SIZE bytes, above the old 512 KiB loader limit" || bad "module no longer above the old limit ($FILE_SIZE)"

PROGS="sh cat echo drvctl sleep"
mkdir -p "$D/bin"
bash tools/sync/build.sh "$D/bin" 0 $PROGS > "$D/p.txt" 2>&1 && ok "programs build" || { bad "programs"; head -10 "$D/p.txt"; fin; }
if [ -n "${LKPI_IWL_KERNEL:-}" ]; then cp "$LKPI_IWL_KERNEL" "$D/k0.img"; ok "kernel supplied"; else
    ./tools/build-kernel.sh "$D/k0.img" --stufe 0 > "$D/k.txt" 2>&1 && ok "kernel builds" || { bad "kernel"; tail -5 "$D/k.txt"; fin; }
fi
{
    echo 'echo ==START=='
    for i in 1 2 3 4; do echo 'sleep 5'; done
    echo 'echo ==WAITED=='
    echo 'cat /proc/drivers'
    echo 'drvctl list'
    echo 'echo ==END=='
} > "$D/s.sh"
printf 'tiers=native+compat\n' > "$D/conf-both"

mkimg() {
    local name=$1 pkg=$2 f files="/lib/drivers/ /lib/firmware/ /lib/firmware/$FW_NAME=$FW_FILE /lib/drivers/$(basename "$2")/"
    for f in $(ls "$pkg"); do files="$files /lib/drivers/$(basename "$pkg")/$f=$pkg/$f"; done
    bash tools/mkfsfi/mkfs.sh build "$D/d-$name.img" 40000 /lib/ \
        /bin/ /t/ /tmp/ /proc/ /dev/ /system/ /etc/ /var/ \
        $(for p in $PROGS; do echo "/bin/$p=$D/bin/$p.elf"; done) \
        "/t/s.sh=$D/s.sh" "/etc/drvstore.conf=$D/conf-both" $files > "$D/mkfs-$name.txt" 2>&1 || tail -3 "$D/mkfs-$name.txt"
}
runvm() {
    local name=$1 words=$2 net=$3
    timeout 400 qemu-system-x86_64 -accel "$ACC" -smp 1 -kernel "$D/k0.img" -m 768 \
        -append "osum vfs nic $words script=sh /t/s.sh;exit" \
        -serial "file:$D/o-$name.txt" -display none -no-reboot $net -device edu \
        -drive "file=$D/d-$name.img,format=raw,if=ide,index=0" \
        -device isa-debug-exit,iobase=0xf4,iosize=0x04 > /dev/null 2>&1
    tr -cd '\11\12\15\40-\176' < "$D/o-$name.txt" > "$D/$name.klar"
}
mkimg native "$PK_NATIVE"
mkimg compat "$PK_NATIVE"
mkimg load "$PK_LOAD"
runvm native "fakewlan" "-nic user,model=e1000" &
runvm compat "fakewlan iwlcompat" "-nic user,model=e1000" &
runvm load "" "-nic none" &
wait

for v in native compat load; do
    has "$D/$v.klar" "==END==" "$v: script ran to the end"
    hasnot "$D/$v.klar" "EXCEPTION" "$v: no kernel exception"
done
hasre "$D/native.klar" 'iwl: .*id=8086:24fd' "native: own iwl driver probes the 8265"
hasnot "$D/native.klar" "drvstore: bind lkpi-iwlwifi" "native: store does not bind a second driver to the claimed 8265"
hasnot "$D/native.klar" "lkpi:" "native: the compat module never ran"
hasre "$D/compat.klar" 'iwl: no device' "compat: word iwlcompat makes the native driver stand down"
hasnot "$D/compat.klar" "iwl: hw_rev" "compat: native driver never probed the 8265"
hasre "$D/compat.klar" 'drvstore: bind lkpi-iwlwifi -> [0-9a-f]{2}:[0-9a-f]{2}\.[0-9a-f] 8086:24fd ok' "compat: store binds lkpi-iwlwifi to the 8265 and the real iwl_pci_probe returns ok"
hasnot "$D/compat.klar" "probe failed" "compat: real probe reports no failure"
has "$D/compat.klar" "drvstore: fw ok $FW_NAME" "compat: firmware served to the real driver"
has "$D/load.klar" "drvstore: fw ok $FW_NAME" "load: kernel served the pinned firmware to the module"
hasnot "$D/load.klar" "drvstore: fw error" "load: no firmware error"
hasnot "$D/load.klar" "module: too big" "load: loader accepts the module above 512 KiB"
fin
