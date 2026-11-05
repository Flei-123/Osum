#!/usr/bin/env bash
. "$(dirname "${BASH_SOURCE[0]}")/../lib/brand-env.sh"
# SPDX-License-Identifier: GPL-2.0-only
set -uo pipefail
cd "$(dirname "$0")/../.."
export FIRNLIB="${FIRNLIB:-$(pwd)/lib}"
pass=0; fail=0
ok()  { pass=$((pass+1)); printf '  OK    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }
has() { grep -qaF -- "$2" "$1" && ok "$3" || bad "$3 -- '$2' missing"; }
hasnot() { grep -qaF -- "$2" "$1" && bad "$3 -- '$2' is there" || ok "$3"; }
D=$(mktemp -d); [ -z "${DRVHW_KEEP:-}" ] && trap 'rm -rf "$D"' EXIT
: "${OSUM_QEMU_ACCEL:=tcg}"
[ -e /dev/kvm ] && [ "$OSUM_QEMU_ACCEL" = tcg ] && OSUM_QEMU_ACCEL=kvm
bash vendor/firn/fetch-firnc.sh >/dev/null 2>&1
fin() { echo "DRVHW: $pass passed, $fail failed"; [ "$fail" -eq 0 ]; exit $?; }
bash tools/module/build.sh "$D/hwdemo.omod" --quelle module/store/hwdemo.fi > "$D/m.txt" 2>&1 && ok "hwdemo module builds and is signed" || { bad "hwdemo module"; tail -5 "$D/m.txt"; fin; }
bash tools/module/build.sh "$D/hwleak.omod" --quelle module/store/hwleak.fi > "$D/ml.txt" 2>&1 && ok "hwleak module builds and is signed" || { bad "hwleak module"; tail -5 "$D/ml.txt"; fin; }
PROGS="sh cat echo drvctl"
mkdir -p "$D/bin" "$D/pk"
bash tools/sync/build.sh "$D/bin" 0 $PROGS > "$D/b.txt" 2>&1 && ok "programs build" || { bad "programs"; head -10 "$D/b.txt"; fin; }
if [ -n "${DRVHW_KERNEL:-}" ]; then cp "$DRVHW_KERNEL" "$D/k0.img"; ok "kernel supplied"; else
./tools/build-kernel.sh "$D/k0.img" --stufe 0 > "$D/k.txt" 2>&1 && ok "kernel builds" || { bad "kernel"; tail -5 "$D/k.txt"; fin; }; fi
cat > "$D/s.sh" <<'EOS'
echo ==RUN==
cat /proc/drivers
drvctl load hwleak
drvctl load hwleak
drvctl load hwleak
echo ==UNLOAD==
drvctl unload hwdemo
echo ==RELOAD==
drvctl load hwdemo
drvctl unload hwdemo
echo ==END==
EOS
variants="full none mmio cfgdma"
rights_full="pci-cfg,mmio,dma"
rights_none=""
rights_mmio="mmio"
rights_cfgdma="pci-cfg,dma"
mkimg() {
    local name=$1; shift
    bash tools/mkfsfi/mkfs.sh build "$D/d-$name.img" 20000 /lib/ /lib/drivers/ \
        "/lib/mono.ttf=assets/osum-mono.ttf" "/lib/sans.ttf=assets/osum-sans.ttf" \
        /bin/ /t/ /tmp/ /proc/ /dev/ /system/ /etc/ /var/ \
        $(for p in $PROGS; do echo "/bin/$p=$D/bin/$p.elf"; done) \
        "/t/s.sh=$D/s.sh" /lib/drivers/hwleak/ $(for f in $(ls "$D/pk-leak/hwleak"); do echo "/lib/drivers/hwleak/$f=$D/pk-leak/hwleak/$f"; done) "$@" > "$D/mkfs-$name.txt" 2>&1 || tail -3 "$D/mkfs-$name.txt"
}
runvm() {
    local name=$1; shift
    timeout 150 qemu-system-x86_64 -accel "$OSUM_QEMU_ACCEL" -smp 1 -kernel "$D/k0.img" -m 512 \
        -append "osum vfs script=sh /t/s.sh;exit" \
        -serial "file:$D/o-$name.txt" -display none -no-reboot \
        -drive "file=$D/d-$name.img,format=raw,if=ide,index=0" \
        -device isa-debug-exit,iobase=0xf4,iosize=0x04 "$@" >/dev/null 2>&1
    tr -cd '\11\12\15\40-\176' < "$D/o-$name.txt" > "$D/$name.klar"
}
mkdir -p "$D/pk-leak"
python3 tools/drvstore/mkpkg.py build "$D/pk-leak" --module "$D/hwleak.omod" --name hwleak --match "pci 1234:11e8" --rights pci-cfg,dma > /dev/null
for v in $variants; do
    r=rights_$v
    rargs=()
    [ -n "${!r}" ] && rargs=(--rights "${!r}")
    mkdir -p "$D/pk-$v"
    python3 tools/drvstore/mkpkg.py build "$D/pk-$v" --module "$D/hwdemo.omod" --name hwdemo --match "pci 1234:1111" "${rargs[@]}" > /dev/null
    files="/lib/drivers/hwdemo/"
    for f in $(ls "$D/pk-$v/hwdemo"); do files="$files /lib/drivers/hwdemo/$f=$D/pk-$v/hwdemo/$f"; done
    mkimg "$v" $files
    runvm "$v" -vga none -device bochs-display -device edu
done
mkdir -p "$D/pk-gone"
mkimg gone
runvm gone -vga none -device bochs-display -device edu

ID=286331444
CFG_OK="id=$ID far=4294967295 odd=4294967295 cmd=0 hdw=1 edge=1 bar=1 hdr=1 hi=1"
CFG_NO="id=4294967295 far=4294967295 odd=4294967295 cmd=1 hdw=1 edge=1 bar=1 hdr=1 hi=1"
BAR_OK="rc=0 bar0s=16 mem0=1 bar2s=4096 bar6=3"
BAR_NO="rc=1 bar0s=0 mem0=0 bar2s=0 bar6=1"
NEG="past=0 big=0 other=0 zero=0 wrap=0 cross=0"
MAP_OK="map=1 span=1 same=1 dispi=1 $NEG"
MAP_MM="map=1 span=1 same=1 dispi=0 $NEG"
MAP_NO="map=0 span=0 same=0 dispi=0 $NEG"
FR_OK="fr=1 low=1 zero=1 rw=1 over=0 nul=0 badfr=1 badn=1 free=0 twice=1 full=8 big=1 max=1"
FR_NO="fr=0 low=0 zero=0 rw=0 over=0 nul=0 badfr=1 badn=1 free=1 twice=1 full=0 big=0 max=0"
check() {
    local v=$1 cfg=$2 bar=$3 map=$4 fr=$5 held=$6 f="$D/$1.klar"
    has "$f" "==END==" "$v: script ran to the end"
    has "$f" "drvstore: bind hwdemo -> " "$v: module bound to the device"
    has "$f" "hwdemo: cfg $cfg" "$v: config cases"
    has "$f" "hwdemo: bar $bar" "$v: BAR cases"
    has "$f" "hwdemo: map $map" "$v: mapping cases"
    has "$f" "hwdemo: fr $fr" "$v: frame cases"
    has "$f" "hwdemo: done" "$v: init completed"
    hasnot "$f" "EXCEPTION" "$v: no kernel exception"
    has "$f" "hwdemo: exit map=0 fr=0 cfg=4294967295" "$v: no hardware access outside the bind window"
    has "$f" "drvstore: frames reclaimed hwdemo $held" "$v: unload reclaims exactly the runs held by the module"
    has "$f" "==RELOAD==" "$v: reload step ran"
    [ "$(grep -caF -- "hwdemo: fr $fr" "$f")" = 2 ] && ok "$v: reload sees the same frame cases (no leak across cycles)" || bad "$v: frame cases differ after reload"
    [ "$(grep -caF -- "frames reclaimed hwdemo $held" "$f")" = 2 ] && ok "$v: second unload reclaims the same count" || bad "$v: second unload count differs"
    [ "$(grep -caF -- "hwleak: run=1" "$f")" -ge 4 ] && ok "$v: failing package allocated runs on every attempt" || bad "$v: hwleak did not allocate"
    hasnot "$f" "frames reclaimed hwleak" "$v: failed bind never reaches the unload path"
}
check full "$CFG_OK" "$BAR_OK" "$MAP_OK" "$FR_OK" 2
check none "$CFG_NO" "$BAR_NO" "$MAP_NO" "$FR_NO" 0
check mmio "$CFG_NO" "$BAR_NO" "$MAP_MM" "$FR_NO" 0
check cfgdma "$CFG_OK" "$BAR_OK" "$MAP_NO" "$FR_OK" 2
hasnot "$D/gone.klar" "hwdemo: cfg" "counter-proof: no package, no module run"
fin
