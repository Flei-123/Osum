#!/usr/bin/env bash
. "$(dirname "${BASH_SOURCE[0]}")/../../tools/lib/brand-env.sh"
# SPDX-License-Identifier: GPL-2.0-only
set -uo pipefail
cd "$(dirname "$0")/../.."
export FIRNLIB="${FIRNLIB:-$(pwd)/lib}"
pass=0; fail=0
ok()  { pass=$((pass+1)); printf '  OK    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }
has() { grep -qaF -- "$2" "$1" && ok "$3" || bad "$3 -- '$2' missing"; }
hasre() { grep -qaE -- "$2" "$1" && ok "$3" || bad "$3 -- /$2/ missing"; }
hasnot() { grep -qaF -- "$2" "$1" && bad "$3 -- '$2' is there" || ok "$3"; }
count() { grep -acF -- "$2" "$1"; }
. tools/lib/tmpdir.sh
D=$(mktemp -d); osum_tmp_guard "" "$D"
: "${OSUM_QEMU_ACCEL:=tcg}"
[ -e /dev/kvm ] && [ "$OSUM_QEMU_ACCEL" = tcg ] && OSUM_QEMU_ACCEL=kvm
keep() {
    [ -n "${LINUXKPI_OUT:-}" ] || return 0
    mkdir -p "$LINUXKPI_OUT" && cp "$D"/*.klar "$D"/*.screen "$D"/*.ppm "$LINUXKPI_OUT"/ 2>/dev/null
    return 0
}
fin() { keep; echo "LINUXKPI-QEMU: $pass passed, $fail failed"; [ "$fail" -eq 0 ]; exit $?; }
SCREEN="python3 -I compat/linuxkpi/hosttest/screen.py"
B="$D/b"
bash compat/linuxkpi/build.sh "$B" > "$D/build.txt" 2>&1 && ok "shim and bochs driver build, closure ok, modules signed" || { bad "build"; tail -5 "$D/build.txt"; fin; }
. tools/lib/firnenv.sh
PROGS="sh cat echo drvctl sleep"
mkdir -p "$D/bin"
bash tools/sync/build.sh "$D/bin" 0 $PROGS > "$D/p.txt" 2>&1 && ok "programs build" || { bad "programs"; head -10 "$D/p.txt"; fin; }
if [ -n "${LINUXKPI_KERNEL:-}" ]; then cp "$LINUXKPI_KERNEL" "$D/k0.img"; ok "kernel supplied"; else
    ./tools/build-kernel.sh "$D/k0.img" --stufe 0 > "$D/k.txt" 2>&1 && ok "kernel builds" || { bad "kernel"; tail -5 "$D/k.txt"; fin; }
fi

pack() { bash compat/linuxkpi/pack.sh bochs "$B/linuxkpi.omod" "$2" "$D/pk-$1" 2> "$D/pack-$1.txt"; }
PK_OK=$(pack ok "$B/bochs_drv.omod")
objcopy --redefine-sym drm_dev_put=drm_dev_put_gone "$B/bochs_drv.o" "$D/m1.o"
python3 -I tools/module/mkomod.py bauen "$D/m1.o" "$D/m1.omod" --name bochs --abi 1 > /dev/null
PK_SYM=$(pack sym "$D/m1.omod")
[ -d "$PK_OK" ] && [ -d "$PK_SYM" ] && ok "store packages built (good driver, missing-symbol mutant)" || { bad "packages"; fin; }

cat > "$D/show.sh" <<'EOS'
echo ==RUN==
cat /proc/drivers
drvctl list
echo ==HOLD==
sleep 12
echo ==END==
EOS
{
    echo ==RUN==
    echo drvctl unload lkpi-bochs
    for i in 1 2 3 4 5 6 7 8 9 10; do
        echo drvctl load lkpi-bochs
        echo drvctl unload lkpi-bochs
    done
    echo ==END==
} > "$D/cycle.sh"
printf 'tiers=native\n' > "$D/conf-native"
printf 'tiers=native+compat\n' > "$D/conf-both"

mkimg() {
    local name=$1 conf=$2 script=$3 pkg=$4 files="" f
    if [ -n "$pkg" ]; then
        files="/lib/drivers/ /lib/drivers/$(basename "$pkg")/"
        for f in $(ls "$pkg"); do files="$files /lib/drivers/$(basename "$pkg")/$f=$pkg/$f"; done
    fi
    bash tools/mkfsfi/mkfs.sh build "$D/d-$name.img" 20000 /lib/ \
        "/lib/mono.ttf=assets/osum-mono.ttf" "/lib/sans.ttf=assets/osum-sans.ttf" \
        /bin/ /t/ /tmp/ /proc/ /dev/ /system/ /etc/ /var/ \
        $(for p in $PROGS; do echo "/bin/$p=$D/bin/$p.elf"; done) \
        "/t/s.sh=$script" "/etc/drvstore.conf=$conf" $files > "$D/mkfs-$name.txt" 2>&1 || tail -3 "$D/mkfs-$name.txt"
}
runvm() {
    local name=$1 hold=$2 i=0 pid
    shift 2
    timeout 170 qemu-system-x86_64 -accel "$OSUM_QEMU_ACCEL" -smp 1 -kernel "$D/k0.img" -m 512 \
        -append "osum vfs script=sh /t/s.sh;exit" \
        -serial "file:$D/o-$name.txt" -display none -no-reboot \
        -drive "file=$D/d-$name.img,format=raw,if=ide,index=0" \
        -monitor "unix:$D/$name.sock,server,nowait" \
        -device isa-debug-exit,iobase=0xf4,iosize=0x04 "$@" > /dev/null 2>&1 &
    pid=$!
    if [ "$hold" = 1 ]; then
        while [ $i -lt 640 ]; do
            grep -qa "==HOLD==" "$D/o-$name.txt" 2>/dev/null && break
            kill -0 $pid 2>/dev/null || break
            sleep 0.25; i=$((i+1))
        done
        $SCREEN dump "$D/$name.sock" "$D/$name.ppm" quit
    fi
    wait $pid
    tr -cd '\11\12\15\40-\176' < "$D/o-$name.txt" > "$D/$name.klar"
    [ -s "$D/$name.ppm" ] && $SCREEN verify "$D/$name.ppm" "${VW:-1024}" "${VH:-768}" > "$D/$name.screen" 2>&1
}
DEV="-vga none -device bochs-display"
DEV_SMALL="-vga none -device bochs-display,vgamem=4194304"
mkimg ok "$D/conf-both" "$D/show.sh" "$PK_OK"
mkimg cycle "$D/conf-both" "$D/cycle.sh" "$PK_OK"
mkimg sym "$D/conf-both" "$D/show.sh" "$PK_SYM"
mkimg native "$D/conf-native" "$D/show.sh" "$PK_OK"
mkimg nodev "$D/conf-both" "$D/show.sh" "$PK_OK"
mkimg small "$D/conf-both" "$D/show.sh" "$PK_OK"
runvm ok 1 $DEV
runvm cycle 0 $DEV
runvm sym 1 $DEV
runvm native 1 $DEV
runvm nodev 1 -vga none
VW=800 VH=600 runvm small 1 $DEV_SMALL

BIND='^drvstore: bind lkpi-bochs -> [0-9a-f]{2}:[0-9a-f]{2}\.[0-9a-f] 1234:1111 '
for v in ok cycle sym native nodev small; do
    has "$D/$v.klar" "==END==" "$v: script ran to the end"
    hasnot "$D/$v.klar" "EXCEPTION" "$v: no kernel exception"
done
has "$D/ok.klar" "lkpi: shim ready" "ok: shim module initialised"
has "$D/ok.klar" "[drm] Found bochs VGA, ID 0xb0c5." "ok: unmodified bochs driver probed the device"
has "$D/ok.klar" "lkpi: modeset 1024x768 ok" "ok: mode set through the shim"
hasre "$D/ok.klar" "${BIND}ok" "ok: store bound lkpi-bochs to the display"
has "$D/ok.screen" "screen: 1024x768 exact=1 other=0" "ok: screen shows the pattern pixel-exact"
has "$D/small.klar" "lkpi: modeset 800x600 ok" "small: 4 MiB VRAM gets 800x600"
hasnot "$D/small.klar" "lkpi: modeset 1024x768" "small: never 1024x768 on 4 MiB VRAM"
hasre "$D/small.klar" "${BIND}ok" "small: store bound lkpi-bochs to the display"
has "$D/small.screen" "screen: 800x600 exact=1 other=0" "small: screen shows the pattern pixel-exact"
RECL='drvstore: frames reclaimed lkpi-bochs '
[ "$(count "$D/cycle.klar" "$RECL")" = 11 ] && ok "cycle: every unload reports its reclaimed runs (11 of 11)" || bad "cycle: reclaim lines $(count "$D/cycle.klar" "$RECL") of 11"
[ "$(count "$D/cycle.klar" "lkpi: modeset 1024x768 ok")" = 11 ] && ok "cycle: mode set after boot and after each of 10 reloads" || bad "cycle: mode set count $(count "$D/cycle.klar" "lkpi: modeset 1024x768 ok") of 11"
runs=$(grep -ao "${RECL}[0-9]*" "$D/cycle.klar" | sed "s/.* //" | sort -u | tr '\n' ' ')
case "$runs" in [1-9]*" ") [ "$(echo $runs | wc -w)" = 1 ] && ok "cycle: same non-zero run count every cycle ($runs)" || bad "cycle: run counts differ ($runs)";; *) bad "cycle: reclaimed run counts '$runs'";; esac
hasnot "$D/cycle.klar" "fail:" "cycle: no bind failure in any cycle"
for v in sym native nodev; do
    hasnot "$D/$v.klar" "lkpi: modeset" "$v: no mode set"
    hasnot "$D/$v.screen" "exact=1" "$v: screen shows no pattern"
done
hasre "$D/sym.klar" "${BIND}fail" "sym: bind fails when the driver needs a missing symbol"
has "$D/native.klar" "drvstore: pkg lkpi-bochs rejected 26" "native: compat package refused by tier policy"
hasnot "$D/native.klar" "lkpi: shim ready" "native: shim never loaded"
hasnot "$D/nodev.klar" "lkpi: shim ready" "nodev: shim never loaded without the device"
fin
